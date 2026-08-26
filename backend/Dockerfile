ARG PYTHON_BASE_IMAGE=python:3.11.15-slim-bookworm@sha256:77923445c077d8eb971b14b2b114a1d9cd4a87edb4c75654820ca4832ee8cb15
ARG UV_VERSION=0.11.13

FROM ${PYTHON_BASE_IMAGE} AS builder

ARG UV_VERSION

RUN apt-get update && \
    apt-get -y install --no-install-recommends build-essential ca-certificates git && \
    rm -rf /var/lib/apt/lists/*
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

# Run as a fixed non-root identity. Application code stays root-owned and
# read-only; Python/temp consumers use only the two declared writable paths.
RUN groupadd --system --gid 10001 omi && \
    useradd --system --uid 10001 --gid omi --no-create-home omi && \
    mkdir -p /tmp/omi-runtime /tmp/omi-parity-pack && \
    chown -R omi:omi /tmp/omi-runtime /tmp/omi-parity-pack && \
    chmod 0755 /tmp && \
    chmod -R a-w /app
ENV TMPDIR=/tmp/omi-runtime
USER 10001:10001

EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080", "--loop", "uvloop"]
