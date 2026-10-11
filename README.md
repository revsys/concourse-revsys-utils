# Concourse REVSYS utilities

Reusable **Concourse task image**, not a custom resource type. Includes:

- Python 3.14 (default), plus Python 3.12 and a `python312` alias for existing hooks
- `uv`, `uvx`, `prek`, and PyPI's `vinnie`
- Latest stable `just`, Git, SSH client, curl, jq, CA certificates, and C build tools
- Debian Bookworm; Linux `amd64` and `arm64`

Tools are resolved at image build time. Project-specific pre-commit hooks are **not** baked in; `prek` installs them from each repository's configuration. Hooks requiring other runtimes or system libraries may need additional setup. Downloads require network access. For reproducible consumers, pin the published image's manifest digest rather than `latest`.

## Publish with GitHub Actions

`.github/workflows/release.yml` runs on pushes to `main` and manual dispatches on `main`. It publishes **ghcr.io/revsys/concourse-revsys-utils** using GitHub-hosted runners and the built-in `GITHUB_TOKEN`; no Concourse installation, PAT, or custom secrets are required.

The workflow builds and smoke-tests the tools, creates the initial Git tag `0.0.1` (when no semantic version tags exist), and subsequently runs `vinnie --no-push patch`. It pushes only the selected Git tag, publishes a Linux `amd64`/`arm64` version tag, tests both platforms using QEMU, then promotes the tested manifest digest to `latest`. Tag pushes do not trigger another release.

Releases are serialized without cancelling active runs. Retries reuse the semantic version tag already on the commit. A failure can leave a reserved Git tag or partially tested version image; rerun the same build to finish publishing. Image version tags can be rebuilt on retry (tools are not pinned), so use digests for immutable references. Runs on obsolete commits are rejected before building. A manual run on an already released commit reuses its version; commit a change to create a new patch release.

Repository/organization settings must allow Actions, `contents: write`, and `packages: write`. Tag protection rules must permit the Actions bot to create release tags. If the GHCR package already exists, grant this repository Actions access under the package settings.

Only trusted contributors should be able to change `main`: release workflows execute repository code with publishing permissions. No publishing workflow runs for pull requests. The Docker build context is restricted to the Dockerfile; Git and registry credentials are not baked into images.

### Make the image public (required one-time step)

GHCR creates new packages as **private**, even for public source repositories. After the first push, open the owner/organization's **Packages → concourse-revsys-utils → Package settings → Change visibility → Public**. Organization policy must allow public packages. The workflow itself does not change package visibility; a public GitHub repository does not automatically make its GHCR package public.

Verify anonymous access using an empty Docker credential directory:

```sh
config=$(mktemp -d)
DOCKER_CONFIG="$config" docker buildx imagetools inspect \
  ghcr.io/revsys/concourse-revsys-utils:latest
rm -rf "$config"
```

Once public, consumers need no GHCR credentials. The OCI source label links the image to its GitHub repository.

## Use for linting

Replace foundation's lint task with the following. The existing Python 3.12 hook configuration can remain unchanged. There is no apt setup or `uvx` bootstrap required:

```yaml
platform: linux
image_resource:
  type: registry-image
  source:
    repository: ghcr.io/revsys/concourse-revsys-utils
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

Release builds use fresh GitHub-hosted runners and resolve moving upstream tools. Push a new commit to `main` when you want updated dependencies published under a new version.
