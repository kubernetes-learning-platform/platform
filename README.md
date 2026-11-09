# platform

> **Shared tooling for every repo:** reusable CI workflows, canonical lint configs, the team's conventions, the infrastructure code, and the files that deploy the demo machines.

Part of [kubernetes-learning-platform](https://github.com/kubernetes-learning-platform/docs), a live Kubernetes lab with an optional AI helper. The [docs repository](https://github.com/kubernetes-learning-platform/docs) describes the overall system.

**Owner:** Filip · **Status:** planned layout, scaffolding lands in M1. Nothing in here runs as a service.

---

## Overview

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/platform-dark.svg">
  <img src="assets/platform-light.svg" width="100%" alt="Left to right: the contracts, sandbox, api and web repos call four reusable workflows in platform. proto-ci publishes to GitHub Packages, release-binary publishes envmgr and the harness to GitHub Releases, vm-image builds the VM template, and container-publish pushes the api and web images to GHCR. Releases and the template go to the Proxmox box, the images go to the Hetzner box, and both sit on a WireGuard mesh with the demo laptop.">
</picture>

`platform` contains what the other repositories share apart from product code: CI workflows, lint rules, infrastructure code and deployment files. Nothing in this repository runs as a service.

| Folder | Purpose |
|---|---|
| `.github/workflows/` | Reusable CI workflows called by every repository |
| `lint/` | Shared formatting and analysis rules for C#, TypeScript and Protobuf |
| `infra/` | OpenTofu code for long-lived infrastructure: the Hetzner server, and the network and permissions on the Proxmox box |
| `deploy/` | Deployment files per machine, and the WireGuard configuration that connects the machines |
| `dev/` | Docker Compose file for local development |

### Delivery path

1. A pull request in any repository runs a workflow from this repository. The calling CI file is about ten lines.
2. A merge or a tag publishes that repository's outputs: packages from `contracts`, binaries and the VM template from `sandbox`, container images from `api` and `web`.
3. The deployment files install those outputs on the target machine: the Compose stack on the Hetzner box, `envmgr` and the VM template on the Proxmox box.
4. The machines communicate only over a private WireGuard mesh. Only WireGuard and SSH on the Hetzner box are reachable from the internet.

Currently implemented: `pr-title.yml` and `copilot-review.yml`. The remaining sections describe the planned layout.

## Reusable workflows

Every workflow here is reusable (`on: workflow_call`). The other repositories call them instead of copying CI. `pr-title.yml` and `copilot-review.yml` also run on this repo's own PRs.

| Workflow | Does | Used by |
|---|---|---|
| `dotnet-ci.yml` | Format check, build, test | `contracts`, `sandbox`, `api` |
| `node-ci.yml` | ESLint, Prettier, typecheck, test, build | `contracts`, `web` |
| `proto-ci.yml` | `buf lint` / `buf breaking`, codegen, pack, publish | `contracts` |
| `container-publish.yml` | buildx → GHCR, multi-arch, tagged with the commit SHA and version | `api`, `web`, scenario images |
| `release-binary.yml` | `dotnet publish` for linux-x64 and linux-arm64 → GitHub Release | `sandbox` |
| `vm-image.yml` | Builds the Proxmox VM template with Packer, with the pinned harness and scenario images. Runs on the **self-hosted runner** in an LXC on the Proxmox box, because GitHub-hosted runners can't reach Proxmox. | `sandbox` |
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
| TypeScript | ESLint flat config, Prettier, `tsc --noEmit` |
| Protobuf | `buf lint` |

## Conventions

- **Conventional Commits, strictly:** `feat: short description`. One line, no body, no co-author trailers.
- **PR titles** use the same format, at most 72 characters, no trailing period. PRs are squash-merged and the squash commit is the PR title, so `main` reads as one clean line per change. The `pr-title` check fails any PR whose title breaks this.
- **Copilot review:** `copilot-review` asks Copilot for one review when a PR opens or is marked ready. It skips drafts, bots, Markdown-only PRs and PRs labelled `skip-copilot`. It needs Copilot on your own account, which is free through GitHub Student.
- **Branches** are `type/anything`, e.g. `feat/warm-pool`, `fix/harness-reconnect`, `ci/pr-title-check`. Same types as commits, no issue number needed, not checked by CI. Short-lived, cut from `main`, deleted after merge.
- **Branches for an issue:** use the issue's **Create a branch** button and replace GitHub's suggested name (`12-add-warm-pool`) with one that follows the convention. The branch and its PR stay linked to the issue. From the CLI: `gh issue develop 12 --name feat/warm-pool --checkout`.
- Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`, `style`.

## Machines

Three machines on one WireGuard mesh ([ADR 0001](https://github.com/kubernetes-learning-platform/docs/blob/main/adr/0001-hosting-and-harness-transport.md)). Nothing is public.

| Machine | Runs | Mesh address | Open to the internet |
|---|---|---|---|
| **Hetzner box** | Docker Compose: Caddy, `web`, `api`, Postgres, RabbitMQ | `10.66.0.1` | WireGuard (UDP 51820) and SSH only |
| **Proxmox box** (home) | Proxmox VE, `envmgr` (systemd), sandbox VMs, the self-hosted runner (LXC) | `10.66.0.2` | Nothing; it dials out |
| **Demo laptop** | The browser | `10.66.0.3` | Nothing; it dials out |

The Hetzner box is the only peer with a public endpoint, so neither the home network nor the demo venue needs port forwarding. More peers (teammates, a graders' laptop) get their own address in `10.66.0.0/24`.

## infra/

OpenTofu for everything long-lived. Run it from a machine on the mesh. State is never committed in plain text.

| Folder | Creates | Provider |
|---|---|---|
| `infra/hetzner/` | The server and its cloud firewall (WireGuard + SSH in, nothing else) | `hcloud` |
| `infra/proxmox/` | The sandbox bridge `vmbr1`, the `kl-sandboxes` resource pool, `envmgr`'s user, role and API token, the self-hosted runner's LXC | `bpg/proxmox` |

The Proxmox VM template is built by Packer from `sandbox/images/base/` (through `vm-image.yml`), not from here. **Sandboxes are not IaC:** `envmgr` creates and deletes them with its own reconcile loop, because a state file per session and a plan/apply cycle on every create would be slow and go stale whenever a VM is deleted outside the tool.

## deploy/

One folder per machine:

| File | Purpose |
|---|---|
| `hetzner/docker-compose.yml` | `proxy` (Caddy), `web`, `api`, `postgres`, `rabbitmq`, with image tags pinned through `.env`. Caddy and RabbitMQ are published only on the mesh address `10.66.0.1`, and RabbitMQ is firewalled to sandbox hosts. |
| `hetzner/Caddyfile` | `tls internal`; `/` → web, `/api` and `/ws` → api. The demo laptop trusts Caddy's root CA once. |
| `hetzner/install.sh` | Runs `docker compose up`, ordered after `wg-quick@wg0` so the mesh address exists when Docker binds to it |
| `proxmox/envmgr.service` | systemd unit for `envmgr` on the Proxmox host. It needs no `/dev/kvm` or `/dev/net/tun`: Proxmox runs the VMs. |
| `proxmox/nftables.conf` | Sandbox isolation: the bridge can reach only `envmgr`'s harness endpoint (`10.67.0.1:7071`), and the gRPC port (`10.66.0.2:7070`) accepts only the Hetzner box |
| `proxmox/install.sh` | Fetches the `envmgr` release, installs the unit and the firewall rules |
| `wireguard/` | Peer config templates for the Hetzner box, the Proxmox box and the demo laptop. Private keys are never committed. |
| `*.env.example` | Config templates (`hetzner/api.env.example`, `proxmox/envmgr.env.example`). The real `.env` files are never committed. |

## dev/

`docker-compose.dev.yml` runs Postgres and api against a **fake** sandbox with no broker, so `api` and `web` can be developed on any laptop without KVM. Using the Docker-provider sandbox adds RabbitMQ.

## Layout

```
platform/
├── .github/workflows/     # the reusable workflows above
├── lint/                  # .editorconfig, Directory.Build.props, eslint + prettier configs, sync.sh
├── infra/                 # OpenTofu: hetzner/, proxmox/
├── deploy/                # hetzner/ (compose, Caddyfile), proxmox/ (envmgr unit, nftables), wireguard/
└── dev/                   # local dev compose
```

## Further reading

- [ARCHITECTURE §8 CI/CD & shared tooling](https://github.com/kubernetes-learning-platform/docs/blob/main/ARCHITECTURE.md#8-cicd--shared-tooling-filip)
- [ARCHITECTURE §3 Runtime architecture](https://github.com/kubernetes-learning-platform/docs/blob/main/ARCHITECTURE.md#3-runtime-architecture) (machines, mesh and sandbox network)
- [ADR 0001](https://github.com/kubernetes-learning-platform/docs/blob/main/adr/0001-hosting-and-harness-transport.md): why the stack and the sandboxes are on different machines

## License

[MIT](LICENSE)
