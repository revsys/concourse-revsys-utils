#!/bin/sh
set -eu
: "${IMAGE:?}" "${GHCR_USERNAME:?}" "${GHCR_TOKEN:?}" "${GITHUB_TOKEN:?}" "${REPOSITORY_URL:?}"

# This privileged task requires a worker permitting nested Docker and binfmt.
apk add --no-cache git
export DOCKER_HOST=unix:///var/run/docker.sock
export DOCKER_CONFIG="$(mktemp -d)"
cleanup() {
    rm -rf "$DOCKER_CONFIG"
    rm -f /tmp/ci-git-askpass
    if [ -n "${daemon_pid:-}" ]; then kill "$daemon_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
# vfs avoids overlay-on-overlay problems inside Concourse containers.
dockerd --host="$DOCKER_HOST" --storage-driver=vfs >/tmp/dockerd.log 2>&1 &
daemon_pid=$!
attempt=0
until docker info >/dev/null 2>&1; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge 60 ]; then tail -100 /tmp/dockerd.log; exit 1; fi
    sleep 2
done
printf '%s' "$GHCR_TOKEN" | docker login ghcr.io --username "$GHCR_USERNAME" --password-stdin
unset GHCR_TOKEN

docker run --privileged --rm tonistiigi/binfmt --install amd64,arm64
docker buildx create --name release --driver docker-container --use
docker buildx inspect --bootstrap
cd source
root=$PWD
revision=$(git rev-parse HEAD)

# First build and exercise the tools natively, before reserving a release tag.
docker buildx build --pull --no-cache --load -t ci-utils:smoke .
docker run --rm ci-utils:smoke sh -ec '
    python --version
    python312 --version
    uv --version
    uvx --version
    prek --version
    vinnie --help >/dev/null
    just --version
    git --version
'

# Credentials stay outside the build context and image layers.
cat >/tmp/ci-git-askpass <<'EOF'
#!/bin/sh
case "$1" in
    *Username*) printf '%s\n' x-access-token ;;
    *Password*) printf '%s\n' "$GITHUB_TOKEN" ;;
esac
EOF
chmod 700 /tmp/ci-git-askpass
export GIT_ASKPASS=/tmp/ci-git-askpass GIT_TERMINAL_PROMPT=0
git remote set-url origin "$REPOSITORY_URL"
git config --unset-all credential.helper || true
git config user.name 'Concourse CI'
git config user.email 'ci@users.noreply.github.com'
git fetch origin '+refs/tags/*:refs/tags/*'

# Reuse an existing version on retries (including a failed registry push).
version=$(git tag --points-at HEAD | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)
if [ -z "$version" ]; then
    if ! git tag --list | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
        git tag 0.0.1
        version=0.0.1
    else
        docker run --rm -v "$root:/workspace" -w /workspace ci-utils:smoke \
            vinnie --no-push patch
        version=$(git tag --points-at HEAD | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
    fi
fi
[ -n "$version" ]
# No force push: a competing publisher must not overwrite a release.
git push origin "refs/tags/$version"
unset GITHUB_TOKEN GIT_ASKPASS
rm -f /tmp/ci-git-askpass

# Publish the version first. latest is promoted only after platform smoke tests.
docker buildx build --pull --platform linux/amd64,linux/arm64 \
    --label "org.opencontainers.image.source=$REPOSITORY_URL" \
    --label "org.opencontainers.image.revision=$revision" \
    --label "org.opencontainers.image.version=$version" \
    --tag "$IMAGE:$version" --push .
for platform in linux/amd64 linux/arm64; do
    docker run --rm --platform "$platform" "$IMAGE:$version" sh -ec '
        python --version; python312 --version
        uv --version; uvx --version; prek --version
        vinnie --help >/dev/null; just --version
    '
done
docker buildx imagetools create --tag "$IMAGE:latest" "$IMAGE:$version"
printf 'Published %s:%s and %s:latest\n' "$IMAGE" "$version" "$IMAGE"
