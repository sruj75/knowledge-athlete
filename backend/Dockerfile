ARG PYTHON_BASE_IMAGE=gcr.io/based-hardware-dev/python:3.11-slim-forky
ARG UV_VERSION=0.11.13

FROM ${PYTHON_BASE_IMAGE} AS builder

ARG UV_VERSION

RUN python -m venv /opt/venv
RUN python3 -m pip install --no-cache-dir "uv==${UV_VERSION}"
ENV PATH="/opt/venv/bin:$PATH"

# Install Python requirements from the checked-in runtime lock.
WORKDIR /opt/venv
COPY backend/pylock.runtime.toml /tmp/pylock.runtime.toml
RUN uv pip sync /tmp/pylock.runtime.toml --python /opt/venv/bin/python --compile-bytecode

FROM ${PYTHON_BASE_IMAGE}

WORKDIR /app
ENV PATH="/opt/venv/bin:$PATH"
RUN apt-get update && apt-get -y install ffmpeg curl libjemalloc2 && rm -rf /var/lib/apt/lists/*

# jemalloc eliminates glibc malloc fragmentation that causes RSS to grow linearly
# under high-churn bytearray allocations from WebSocket audio streams (#6938)
# Use soname-only form so ld.so resolves via standard search paths (arch-portable)
ENV LD_PRELOAD=libjemalloc.so.2

COPY --from=builder /opt/venv /opt/venv
COPY .github/scripts/desktop_release_manifest.py /app/desktop_release_manifest_contract.py
COPY .github/scripts/desktop_qualification_admission.py /app/desktop_qualification_admission_contract.py
COPY .github/scripts/desktop_qualification_evidence.py /app/desktop_qualification_evidence_contract.py
COPY backend/ .

# Run as a non-root user: a compromise of the app process (e.g. via a
# dependency RCE) shouldn't hand the attacker root inside the container by
# default. /app stays writable for retained multipart voice-message staging.
RUN groupadd --system --gid 10001 omi && \
    useradd --system --uid 10001 --gid omi --no-create-home omi && \
    chown -R omi:omi /app
USER omi

EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--loop", "uvloop"]
