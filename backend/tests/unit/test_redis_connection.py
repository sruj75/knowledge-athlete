from __future__ import annotations

from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
import importlib
import ipaddress
from pathlib import Path
import socket
import ssl
from threading import Event, Thread

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID


def _reload(monkeypatch, *, stage='prod'):
    monkeypatch.setenv('OMI_ENV_STAGE', stage)
    import database.redis_connection as connection

    connection.reset_redis_client_for_testing()
    return importlib.reload(connection)


def _hosted_env(monkeypatch):
    monkeypatch.setenv('REDIS_DB_HOST', 'redis.internal.example')
    monkeypatch.setenv('REDIS_DB_PORT', '6378')
    monkeypatch.setenv('REDIS_DB_PASSWORD', 'not-a-real-secret')
    monkeypatch.setenv('REDIS_DB_CA_CERT_PEM', '-----BEGIN CERTIFICATE-----\nFAKE\n-----END CERTIFICATE-----')


def _certificate_chain(*, hostname: str = 'localhost') -> tuple[bytes, bytes, bytes]:
    now = datetime.now(timezone.utc)
    ca_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'S-27 Redis test CA')])
    ca_cert = (
        x509.CertificateBuilder()
        .subject_name(ca_name)
        .issuer_name(ca_name)
        .public_key(ca_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=1))
        .not_valid_after(now + timedelta(days=1))
        .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
        .sign(ca_key, hashes.SHA256())
    )
    server_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    server_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, hostname)])
    server_cert = (
        x509.CertificateBuilder()
        .subject_name(server_name)
        .issuer_name(ca_cert.subject)
        .public_key(server_key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - timedelta(minutes=1))
        .not_valid_after(now + timedelta(days=1))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(hostname)]), critical=False)
        .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
        .sign(ca_key, hashes.SHA256())
    )
    return (
        ca_cert.public_bytes(serialization.Encoding.PEM),
        server_cert.public_bytes(serialization.Encoding.PEM),
        server_key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption(),
        ),
    )


@contextmanager
def _tls_listener(tmp_path: Path, *, hostname: str = 'localhost'):
    ca_pem, cert_pem, key_pem = _certificate_chain(hostname=hostname)
    cert_path = tmp_path / 'server-cert.pem'
    key_path = tmp_path / 'server-key.pem'
    cert_path.write_bytes(cert_pem)
    key_path.write_bytes(key_pem)
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(('127.0.0.1', 0))
    listener.listen(1)
    listener.settimeout(3)
    port = listener.getsockname()[1]
    finished = Event()

    def serve_once() -> None:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=cert_path, keyfile=key_path)
        try:
            client, _ = listener.accept()
            try:
                with context.wrap_socket(client, server_side=True):
                    pass
            except ssl.SSLError:
                client.close()
        except (OSError, TimeoutError):
            pass
        finally:
            listener.close()
            finished.set()

    thread = Thread(target=serve_once, daemon=True)
    thread.start()
    try:
        yield port, ca_pem.decode('ascii')
    finally:
        listener.close()
        finished.wait(timeout=3)
        thread.join(timeout=1)


def _open_transport(client):
    connection = client.connection_pool.make_connection()
    try:
        transport = connection._connect()
        transport.close()
    finally:
        connection.disconnect()


def test_hosted_client_is_lazy_and_uses_auth_with_verified_tls(monkeypatch):
    _hosted_env(monkeypatch)
    connection = _reload(monkeypatch)
    calls = []
    fake_client = object()
    monkeypatch.setattr(connection.redis, 'Redis', lambda **kwargs: calls.append(kwargs) or fake_client)

    assert calls == []
    assert connection.get_redis_client() is fake_client
    assert calls == [
        {
            'host': 'redis.internal.example',
            'port': 6378,
            'username': 'default',
            'password': 'not-a-real-secret',
            'health_check_interval': 30,
            'ssl': True,
            'ssl_cert_reqs': 'required',
            'ssl_check_hostname': True,
            'ssl_ca_data': '-----BEGIN CERTIFICATE-----\nFAKE\n-----END CERTIFICATE-----',
        }
    ]


@pytest.mark.parametrize('missing', ['REDIS_DB_HOST', 'REDIS_DB_PASSWORD', 'REDIS_DB_CA_CERT_PEM'])
def test_hosted_client_fails_closed_when_tls_or_auth_input_is_missing(monkeypatch, missing):
    _hosted_env(monkeypatch)
    monkeypatch.delenv(missing, raising=False)
    connection = _reload(monkeypatch)

    with pytest.raises(connection.RedisConfigurationError, match=missing):
        connection.get_redis_client()


def test_local_client_keeps_explicit_plaintext_harness_seam(monkeypatch):
    monkeypatch.setenv('REDIS_DB_HOST', '127.0.0.1')
    monkeypatch.setenv('REDIS_DB_PORT', '6379')
    monkeypatch.delenv('REDIS_DB_PASSWORD', raising=False)
    monkeypatch.delenv('REDIS_DB_CA_CERT_PEM', raising=False)
    connection = _reload(monkeypatch, stage='offline')
    calls = []
    monkeypatch.setattr(connection.redis, 'Redis', lambda **kwargs: calls.append(kwargs) or object())

    connection.get_redis_client()

    assert calls == [
        {
            'host': '127.0.0.1',
            'port': 6379,
            'username': 'default',
            'password': None,
            'health_check_interval': 30,
        }
    ]


def test_injected_client_is_the_process_scoped_boundary(monkeypatch):
    connection = _reload(monkeypatch, stage='offline')
    fake = type('FakeRedis', (), {'get': lambda self, key: key})()
    connection.set_redis_client_for_testing(fake)

    assert connection.get_redis_client().get('cache-key') == 'cache-key'


def test_production_client_completes_a_verified_tls_handshake(monkeypatch, tmp_path):
    with _tls_listener(tmp_path) as (port, ca_pem):
        monkeypatch.setenv('REDIS_DB_HOST', 'localhost')
        monkeypatch.setenv('REDIS_DB_PORT', str(port))
        monkeypatch.setenv('REDIS_DB_PASSWORD', 'test-auth-value')
        monkeypatch.setenv('REDIS_DB_CA_CERT_PEM', ca_pem)
        connection = _reload(monkeypatch)

        _open_transport(connection.get_redis_client())


def test_production_client_rejects_an_untrusted_ca(monkeypatch, tmp_path):
    with _tls_listener(tmp_path) as (port, _trusted_ca):
        unrelated_ca, _, _ = _certificate_chain(hostname='unrelated')
        monkeypatch.setenv('REDIS_DB_HOST', 'localhost')
        monkeypatch.setenv('REDIS_DB_PORT', str(port))
        monkeypatch.setenv('REDIS_DB_PASSWORD', 'test-auth-value')
        monkeypatch.setenv('REDIS_DB_CA_CERT_PEM', unrelated_ca.decode('ascii'))
        connection = _reload(monkeypatch)

        with pytest.raises(ssl.SSLCertVerificationError):
            _open_transport(connection.get_redis_client())


def test_production_client_rejects_a_hostname_mismatch(monkeypatch, tmp_path):
    with _tls_listener(tmp_path) as (port, ca_pem):
        monkeypatch.setenv('REDIS_DB_HOST', str(ipaddress.ip_address('127.0.0.1')))
        monkeypatch.setenv('REDIS_DB_PORT', str(port))
        monkeypatch.setenv('REDIS_DB_PASSWORD', 'test-auth-value')
        monkeypatch.setenv('REDIS_DB_CA_CERT_PEM', ca_pem)
        connection = _reload(monkeypatch)

        with pytest.raises(ssl.SSLCertVerificationError):
            _open_transport(connection.get_redis_client())
