# Concourse REVSYS utilities

Reusable **Concourse task image**, not a custom resource type. Includes:

- Python 3.14 (default), plus Python 3.12 and a `python312` alias for existing hooks
- `uv`, `uvx`, `prek`, and PyPI's `vinnie`
- Latest stable `just`, Git, SSH client, curl, jq, CA certificates, and C build tools
- Debian Bookworm; Linux `amd64` and `arm64`

Tools are resolved at image build time. Project-specific pre-commit hooks are **not** baked in; `prek` installs them from each repository's configuration. Hooks requiring other runtimes or system libraries may need additional setup. Downloads require network access. For reproducible consumers, pin the published image's manifest digest rather than `latest`.

## Publish from Concourse

The release job builds and smoke-tests the image, creates the initial Git tag `0.0.1` (when no semantic version tags exist), and subsequently runs `vinnie --no-push patch`. It pushes only the selected Git tag, publishes a multi-platform version tag, tests both platforms, then promotes that manifest to `latest`.

Retries reuse the semantic version tag already on the commit. A failure can leave a reserved Git tag or partially tested version image; rerun the same build to finish publishing. Image version tags can be rebuilt on retry (tools are not pinned), so use digests for immutable references. Only one pipeline should own release tags. Do not rerun historical commits after newer releases: that would move `latest` backward.

Prerequisites:

- A Linux Concourse worker supporting **privileged tasks**, nested Docker, and QEMU/binfmt registration. The task registers emulators on the worker; use a dedicated trusted release worker where appropriate.
- A GitHub repository with these files on the release branch. No repository URL is hardcoded.
- A GitHub token with repository contents write permission for Git tags.
- A GHCR publishing credential: normally a classic PAT with `write:packages` (and `read:packages`), authorized for organization SSO if required. `ghcr-username` is its owning GitHub username. Keep credentials in Concourse's credential manager.
- A lowercase GHCR owner/organization name.

Configure these variables (`github-token` and `ghcr-token` should be supplied through your credential manager):

```yaml
repository-url: https://github.com/YOUR-ORG/concourse-revsys-utils.git
release-branch: main
ghcr-owner: your-org
ghcr-username: your-publishing-user
```

```sh
fly -t ci set-pipeline -p concourse-revsys-utils \
  -c .concourse/pipeline.yml -l vars.yml
fly -t ci unpause-pipeline -p concourse-revsys-utils
```

The release task executes repository code with publishing credentials. Only trusted contributors should be able to change the release branch; do not use it for untrusted pull requests. The Docker build context is restricted to the Dockerfile. Git and registry credentials are not baked into images.

### Make the image public (required one-time step)

GHCR creates new packages as **private**, even for public source repositories. After the first push, open the owner/organization's **Packages → concourse-revsys-utils → Package settings → Change visibility → Public**. Organization policy must allow public packages. The pipeline itself does not change package visibility.

Verify anonymous access using an empty Docker credential directory:

```sh
config=$(mktemp -d)
DOCKER_CONFIG="$config" docker buildx imagetools inspect \
  ghcr.io/YOUR-ORG/concourse-revsys-utils:latest
rm -rf "$config"
```

Once public, consumers need no GHCR credentials. The OCI source label links the image to its GitHub repository.

## Use for linting

Replace foundation's lint task with the following (substitute your lowercase owner). The existing Python 3.12 hook configuration can remain unchanged. There is no apt setup or `uvx` bootstrap required:

```yaml
platform: linux
image_resource:
  type: registry-image
  source:
    repository: ghcr.io/YOUR-ORG/concourse-revsys-utils
    tag: latest
inputs:
  - name: source
caches:
  - path: cache/uv
  - path: cache/prek
run:
  path: sh
  args:
    - -ec
    - |
      export UV_CACHE_DIR="$PWD/cache/uv"
      export PREK_HOME="$PWD/cache/prek"
      cd source
      prek run --all-files
```

For version-management tasks, use the same image and run `vinnie --no-push patch` inside the Git checkout, then push the selected tag with separately supplied Git credentials. Prefer installed `prek`/`vinnie` over `uvx prek`/`uvx vinnie`, which resolve separate tool environments.

## Local check

```sh
docker build --pull --no-cache -t concourse-revsys-utils:test .
docker run --rm concourse-revsys-utils:test sh -ec '
  python --version; python312 --version
  uv --version; uvx --version; prek --version
  vinnie --help; just --version
'
```

The release pipeline intentionally uses a fresh, disposable Docker daemon instead of caching its privileged Docker storage. Release builds resolve moving upstream tools; schedule or manually trigger a new source commit when you want updated dependencies published under a new version.
