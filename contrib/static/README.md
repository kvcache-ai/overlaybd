# Static OverlayBD CLI release

This directory builds self-contained Linux archives for the OverlayBD command-line
tools used by AgentENV:

- `overlaybd-create`
- `overlaybd-apply`
- `overlaybd-commit`
- `overlaybd-resize`

The executables are linked against musl and contain no dynamic loader or shared
library dependencies. The build pins external source archives by commit and SHA-256,
runs a create/apply/resize/commit smoke test, and verifies the final ELF metadata.

Build an x86_64 archive locally with Docker Buildx:

```bash
docker buildx build \
  --platform linux/amd64 \
  --build-arg RELEASE_VERSION=dev \
  --build-arg SOURCE_COMMIT="$(git rev-parse HEAD)" \
  --file contrib/static/Dockerfile \
  --output type=local,dest=dist \
  .
```

The `Static CLI` workflow validates both `linux/amd64` and `linux/arm64` on pull
requests. After the change is merged, pushing a tag named `static-v<version>` at a
commit contained in `origin/main` publishes both archives and their checksum files
as a GitHub release. A tag on an unmerged commit fails before the Docker build starts.
The `static-` prefix keeps this release path separate from the existing
distro-package workflow, which uses `v*` tags.
