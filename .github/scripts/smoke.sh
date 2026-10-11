#!/bin/sh
set -eu
python -c 'import sys; assert sys.version_info[:2] == (3, 14)'
python312 -c 'import sys; assert sys.version_info[:2] == (3, 12)'
uv --version
uvx --version
prek --version
vinnie --help >/dev/null
just --version
git --version

# Verify that prek can resolve foundation's existing interpreter spelling.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
git init -q
cat >.pre-commit-config.yaml <<'EOF'
default_language_version:
  python: python312
repos:
  - repo: local
    hooks:
      - id: python-check
        name: Python 3.12 hook
        language: python
        entry: python -c 'import sys; assert sys.version_info[:2] == (3, 12)'
        always_run: true
        pass_filenames: false
EOF
prek run --all-files
