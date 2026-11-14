# platform

> **Shared tooling for every repo:** reusable CI workflows, canonical lint configs, the team's conventions, and the files that set up and deploy the course VM.

Part of [kubernetes-learning-platform](https://github.com/kubernetes-learning-platform/docs), a live Kubernetes lab with an optional AI helper. The [docs repository](https://github.com/kubernetes-learning-platform/docs) describes the overall system.

**Owner:** Filip · **Status:** planned layout, scaffolding lands in M1. Nothing in here runs as a service.

---

## Overview

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/platform-dark.svg">
  <img src="assets/platform-light.svg" width="100%" alt="Left to right: the contracts, sandbox, api and web repos call four reusable workflows in platform. proto-ci publishes to GitHub Packages, release-binary publishes envmgr and the harness to GitHub Releases, sandbox-template builds the sandbox template, and container-publish pushes the api and web images to GHCR. The releases, the template and the images all end up on the course VM, which the team reaches over Tailscale.">
</picture>

`platform` contains what the other repositories share apart from product code: CI workflows, lint rules, the VM install script and deployment files. Nothing in this repository runs as a service.

| Folder | Purpose |
|---|---|
| `.github/workflows/` | Reusable CI workflows called by every repository |
| `lint/` | Shared formatting and analysis rules for C#, TypeScript and Protobuf |
| `deploy/vm/` | The install script and config files for the course VM |
| `dev/` | Docker Compose file for local development |

### Delivery path

1. A pull request in any repository runs a workflow from this repository. The calling CI file is about ten lines.
2. A merge or a tag publishes that repository's outputs: packages from `contracts`, binaries and the sandbox template from `sandbox`, container images from `api` and `web`.
3. A manual deploy from a private deploy repo puts a chosen version of the stack on the course VM. `envmgr` and the sandbox template are installed on the same VM.
4. The VM is reached only over Tailscale. No port is open to the internet.

Currently implemented: `pr-title.yml` and `copilot-review.yml`. The remaining sections describe the planned layout.

## Reusable workflows

Every workflow here is reusable (`on: workflow_call`). The other repositories call them instead of copying CI. `pr-title.yml` and `copilot-review.yml` also run on this repo's own PRs.

| Workflow | Does | Used by |
|---|---|---|
| `dotnet-ci.yml` | Format check, build, test | `contracts`, `sandbox`, `api` |
| `node-ci.yml` | `biome ci` (lint + format check), typecheck, test, build | `contracts`, `web` |
| `proto-ci.yml` | `buf lint` / `buf breaking`, codegen, pack. On `main`, publishes a release when the schema changed, with the version taken from the commit type, then notifies the consumers. | `contracts` |
| `contracts-bump.yml` | Sets a new `contracts` version, builds and tests, then pushes `build(deps): bump contracts to X.Y.Z` to `main`. If the build fails, it opens a PR for the repo's owner instead. | `sandbox`, `api`, `web` |
| `container-publish.yml` | buildx → GHCR, multi-arch, tagged with the commit SHA, and with the version on a tag. A merge to `main` publishes an image. | `api`, `web`, scenario images |
| `release-binary.yml` | `dotnet publish` for linux-x64 and linux-arm64 → GitHub Release | `sandbox` |
| `sandbox-template.yml` | Builds the qcow2 sandbox template with Packer, with the pinned harness and scenario images. Runs on the **self-hosted runner** on the course VM, because it needs KVM. | `sandbox` |
| `pr-title.yml` | Fails a PR whose title isn't a Conventional Commit (max 72 characters, no trailing period) | every repo |
| `copilot-review.yml` | Requests one Copilot review when a PR opens or is marked ready. Skips drafts, bots, Markdown-only PRs and the `skip-copilot` label. | every repo |

A consuming repository's CI file:

```yaml
name: ci
on:
  pull_request:
  push:
    branches: [main]

jobs:
  ci:
    uses: kubernetes-learning-platform/platform/.github/workflows/dotnet-ci.yml@main
    secrets: inherit
```

## Lint configs

The canonical copies live in `lint/`. `sync.sh` copies them into a repo, and the reusable CI fails if a repo's copy drifts.

| Language | Rules |
|---|---|
| C# | `.editorconfig`, `dotnet format --verify-no-changes`, `TreatWarningsAsErrors`, `AnalysisLevel=latest-recommended` |
| TypeScript | Biome for linting and formatting (`biome.json`, checked with `biome ci`), `tsc --noEmit` |
| Protobuf | `buf lint` |

## Conventions

- **Conventional Commits, strictly:** `feat: short description`. One line, no body, no co-author trailers.
- **PR titles** use the same format, at most 72 characters, no trailing period. PRs are squash-merged and the squash commit is the PR title, so `main` reads as one clean line per change. The `pr-title` check fails any PR whose title breaks this.
- **Copilot review:** `copilot-review` asks Copilot for one review when a PR opens or is marked ready. It skips drafts, bots, Markdown-only PRs and PRs labelled `skip-copilot`. It needs Copilot on your own account, which is free through GitHub Student.
- **Branches** are `type/anything`, e.g. `feat/warm-pool`, `fix/harness-reconnect`, `ci/pr-title-check`. Same types as commits, no issue number, not checked by CI. Short-lived, cut from `main`, deleted after merge.
- **Branches for an issue:** every issue names its branch in a `Branch:` line. Create it with `gh issue develop 12 --name feat/warm-pool --checkout`, or with the issue's **Create a branch** button and that name instead of GitHub's suggestion (`12-add-warm-pool`). The branch and its PR stay linked to the issue.
- **Where changes land:** while the repos are still empty, documentation is committed straight to `main`. From the setup issues on, every change goes through a PR.
- Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`, `style`.

## The course VM

One course-provided VM (16 vCPU, 32 GB RAM, full root access) runs everything ([ADR 0003](https://github.com/kubernetes-learning-platform/docs/blob/main/adr/0003-course-vm-hosting.md)). Nothing is public.

| On the VM | Runs |
|---|---|
| **The stack** | Caddy, `web`, `api`, Postgres, RabbitMQ. The deploy format, Docker Compose or a Helm chart on single-node k3s, is OPEN. |
| **`envmgr`** | A systemd service on the host, because it needs `/dev/kvm` and libvirt |
| **The sandboxes** | QEMU/libvirt VMs on an isolated network if the VM supports nested virtualization, otherwise Sysbox containers (OPEN, platform#6) |
| **The self-hosted runner** | Deploys and the sandbox template build. Its own user and label, registered only to private repos. |
| **Observability** (testing) | Prometheus, Grafana, Loki and a log collector, with no published port |

- **Access:** the VM is in the team's Tailscale tailnet. A tailnet ACL allows only SSH and the app's HTTPS port. Teammates and graders join the tailnet.
- **HTTPS:** Caddy, built with the Cloudflare DNS module, listens only on the VM's Tailscale address. A DNS-only record on our Cloudflare domain points there, and the certificate comes from the DNS-01 challenge.
- **No infrastructure code:** the VM isn't ours to create, so `deploy/vm/install.sh` sets it up instead of OpenTofu.

The sandbox template is built by Packer from `sandbox/images/base/` (through `sandbox-template.yml`), not from here. **Sandboxes are not IaC:** `envmgr` creates and deletes them with its own reconcile loop, because a state file per session and a plan/apply cycle on every create would be slow and go stale whenever a VM is deleted outside the tool.

## deploy/vm/

Planned files for the course VM (platform#11). The stack's own files wait until the deploy format is chosen.

| File | Purpose |
|---|---|
| `install.sh` | Sets up the base system, Tailscale, libvirt and the runner (platform#8 to #10, #14), and installs the `envmgr` release |
| `envmgr.service` | systemd unit for `envmgr` on the host |
| `libvirt-network.xml` | The isolated sandbox network, with no route to the internet or the host network |
| `nftables.conf` | Sandbox isolation: a sandbox can reach only `envmgr`'s harness endpoint (`10.67.0.1:7071`), and the gRPC port accepts only the stack |
| `Caddyfile` | Our domain, certificate through DNS-01; `/` → web, `/api` and `/ws` → api |
| `*.env.example` | Config templates (`api.env.example`, `envmgr.env.example`). The real `.env` files are never committed. |

Deploys run from a private deploy repo: a manual `workflow_dispatch` takes the image SHAs, updates the stack, smoke-tests `/healthz` and rolls back if the test fails (platform#15). Each deploy is recorded as a deployment on `api` and `web` (platform#16).

## dev/

`docker-compose.dev.yml` runs Postgres and RabbitMQ with named volumes, so the backend can run on any laptop without KVM (platform#5). `api` can use a **fake** sandbox with no broker. A `sandbox` profile adds `envmgr` with the Docker provider and a privileged DinD container, for a real sandbox locally (platform#13).

## Layout

```
platform/
├── .github/workflows/     # the reusable workflows above
├── lint/                  # .editorconfig, Directory.Build.props, biome.json, sync.sh
├── deploy/vm/             # install script, envmgr unit, libvirt network, nftables, Caddyfile
└── dev/                   # local dev Compose
```

## Further reading

- [ARCHITECTURE §8 CI/CD & shared tooling](https://github.com/kubernetes-learning-platform/docs/blob/main/ARCHITECTURE.md#8-cicd--shared-tooling-filip)
- [ARCHITECTURE §3 Runtime architecture](https://github.com/kubernetes-learning-platform/docs/blob/main/ARCHITECTURE.md#3-runtime-architecture) (hosting and the sandbox network)
- [ADR 0003](https://github.com/kubernetes-learning-platform/docs/blob/main/adr/0003-course-vm-hosting.md): one course-provided VM, reached over Tailscale

## License

[MIT](LICENSE)
