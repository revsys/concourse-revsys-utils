#!/usr/bin/env bash
set -euo pipefail

# actions/checkout supplies authenticated Git access, outside the build context.
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git fetch origin '+refs/tags/*:refs/tags/*'

# Reuse the reserved version if a previous attempt failed after tagging.
version=$(git tag --points-at HEAD | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
if [[ -z "$version" ]]; then
    versions=$(git tag --list | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)
    if [[ -z "$versions" ]]; then
        git tag 0.0.1
        version=0.0.1
    else
        docker run --rm -v "$PWD:/workspace" -w /workspace ci-utils:smoke sh -ec '
            git config --global --add safe.directory /workspace
            vinnie --no-push patch
        '
        version=$(git tag --points-at HEAD | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    fi
fi
[[ -n "$version" ]]
# Never force: a conflicting tag must fail rather than overwrite a release.
git push origin "refs/tags/$version"
echo "version=$version" >> "${GITHUB_OUTPUT:?}"
