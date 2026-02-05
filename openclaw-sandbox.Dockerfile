FROM debian:bookworm-slim

# Minimal runtime for OpenClaw sandbox exec.
# Includes: bash/sh, coreutils, ca-certs, python3 (for local scripts), git (optional).
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    coreutils \
    curl \
    git \
    jq \
    python3 \
    python3-pip \
    python3-venv \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
