# syntax=docker/dockerfile:1
FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim

ENV UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_PYTHON_BIN_DIR=/usr/local/bin

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       bash build-essential ca-certificates curl git jq openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Keep Python 3.14 as the default; foundation's hooks request Python 3.12.
RUN uv python install 3.12 \
    && ln -s /usr/local/bin/python3.12 /usr/local/bin/python312 \
    && uv tool install --python /usr/local/bin/python3.14 prek \
    && uv tool install --python /usr/local/bin/python3.14 vinnie \
    && uv cache clean

# Resolve the latest stable just release for each target architecture.
RUN set -eu; \
    case "$(dpkg --print-architecture)" in \
      amd64) target=x86_64-unknown-linux-musl ;; \
      arm64) target=aarch64-unknown-linux-musl ;; \
      *) echo 'Unsupported architecture' >&2; exit 1 ;; \
    esac; \
    version="$(curl --fail --silent --show-error --retry 3 \
      https://api.github.com/repos/casey/just/releases/latest | jq -er '.tag_name')"; \
    curl --fail --silent --show-error --location --retry 3 \
      "https://github.com/casey/just/releases/download/${version}/just-${version}-${target}.tar.gz" \
      -o /tmp/just.tar.gz; \
    tar -xzf /tmp/just.tar.gz -C /usr/local/bin just; \
    rm /tmp/just.tar.gz; \
    just --version

WORKDIR /workspace
CMD ["bash"]
