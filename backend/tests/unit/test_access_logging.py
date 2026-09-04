import io
import logging

from utils.access_logging import install_uvicorn_access_log_sanitizer


def test_uvicorn_access_log_omits_oauth_query_credentials() -> None:
    output = io.StringIO()
    handler = logging.StreamHandler(output)
    handler.setFormatter(logging.Formatter('%(message)s'))
    logger = logging.getLogger('test.uvicorn.access')
    logger.handlers = [handler]
    logger.propagate = False
    logger.setLevel(logging.INFO)

    install_uvicorn_access_log_sanitizer(logger)
    logger.info(
        '%s - "%s %s HTTP/%s" %d',
        '127.0.0.1:50000',
        'GET',
        '/v1/auth/callback/google?code=one-time-secret&state=session-secret',
        '1.1',
        200,
    )

    rendered = output.getvalue()
    assert rendered == '127.0.0.1:50000 - "GET /v1/auth/callback/google HTTP/1.1" 200\n'
    assert 'one-time-secret' not in rendered
    assert 'session-secret' not in rendered
