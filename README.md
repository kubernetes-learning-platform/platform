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

Currently implemented: `pr-title.yml`, `copilot-review.yml`, `pr-assign.yml`, `dotnet-ci.yml`, `node-ci.yml`, `proto-ci.yml`, `platform-check.yml` and `lint/`. The remaining sections describe the planned layout.

## Reusable workflows

The workflows here are reusable (`on: workflow_call`), so the other repositories call them instead of copying CI. `pr-title.yml`, `pr-assign.yml` and `copilot-review.yml` also run on this repo's own PRs, and `platform-check.yml` runs only here.

| Workflow | Does | Used by |
|---|---|---|
| `dotnet-ci.yml` | Lint copies, `dotnet format --verify-no-changes`, Release build | `sandbox`, `api` |
| `node-ci.yml` | Lint copies, `npm ci`, `biome ci` (lint and format check), `npm run build`, `tsc --noEmit` | `web` |
| `proto-ci.yml` | Lint copies, `buf lint`, `buf format`, and on PRs `buf breaking` against the base commit: a break fails unless the PR title has `!`. Then `buf generate`, and the same .NET and TypeScript checks as the two workflows above for the two packages. Publishing on `main` is added by contracts#2. | `contracts` |
| `contracts-bump.yml` | Sets a new `contracts` version, builds and tests, then pushes `build(deps): bump contracts to X.Y.Z` to `main` with the GitHub App's token, which is on each repo's ruleset bypass list. If the build fails, it opens a PR for the repo's owner instead. | `sandbox`, `api`, `web` |
| `lint-sync.yml` | Runs `lint/sync.sh` at the `platform` commit sent after a change to `lint/`, with the flags in the repo's `.lint-sync`, builds and tests, then pushes `chore: sync lint configs` to `main` with the GitHub App's token. If the build fails, it opens a PR instead. It pushes nothing when no copy changed. | `contracts`, `sandbox`, `api`, `web` |
| `container-publish.yml` | buildx → GHCR, multi-arch, tagged with the commit SHA, and with the version on a tag. A merge to `main` publishes an image. | `api`, `web`, scenario images |
| `release-binary.yml` | `dotnet publish` for linux-x64 and linux-arm64 → GitHub Release | `sandbox` |
| `sandbox-template.yml` | Builds the qcow2 sandbox template with Packer, with the pinned harness and scenario images. Runs on the **self-hosted runner** on the course VM, because it needs KVM. Public repos can't use that runner, so it is started from the private deploy repo. | deploy repo |
| `platform-check.yml` | Runs on `platform`'s own PRs: actionlint, shellcheck on every `*.sh`, and `lint/sync.sh --check .`. Required in `platform`'s ruleset. | `platform` |
| `pr-title.yml` | Fails a PR whose title isn't a Conventional Commit (max 72 characters, no trailing period) | every repo |
| `pr-assign.yml` | Assigns each PR to the person who opened it. Skips forks and bots. | every repo |
| `copilot-review.yml` | Requests one Copilot review when a PR opens or is marked ready. Skips drafts, bots, Markdown-only PRs and the `skip-copilot` label. | every repo |

"Lint copies" means the workflow fetches `platform` at the commit in the repo's `.lint-sync` and runs `lint/sync.sh --check` with the repo's flags, so a hand edit fails. None of the CI workflows runs tests yet; a test step comes once the repos have tests.

A repository's `ci.yml`:

```yaml
name: ci

on:
  pull_request:

permissions: {}

jobs:
  ci:
    permissions:
      contents: read
    uses: kubernetes-learning-platform/platform/.github/workflows/dotnet-ci.yml@main
```

CI runs on pull requests only. Branches must be up to date with `main` before merging, so the PR checks already cover what lands there, and a second run on `main` would repeat them. `contracts` calls `proto-ci.yml` instead, with `types: [opened, edited, reopened, synchronize]` under `pull_request`, so adding `!` to a PR title re-runs the breaking check.

| Workflow | Inputs (default) | Check name, with the `ci` job above |
|---|---|---|
| `dotnet-ci.yml` | `dotnet-version` (`10.0.x`) | `ci / .NET checks` |
| `node-ci.yml` | `node-version` (`24`), `working-directory` (`.`) | `ci / Node checks` |
| `proto-ci.yml` | `buf-version` (`1.75.0`), `dotnet-version`, `node-version`, `dotnet-project` (`dotnet/KubernetesLearning.Contracts`), `ts-directory` (`ts`) | `ci / Protobuf checks` |

A Node package needs a `package-lock.json`, a `build` script, and `@biomejs/biome` and `typescript` as dev dependencies.

The job names are fixed, so the check names don't change. Once a repository's `ci.yml` has run, add its check to that repository's `main` ruleset as required, next to the PR title check. Don't add it earlier: a required check that has never reported blocks every merge.

## Lint configs

The canonical copies live in `lint/`. Every repo commits its own copy at its root, made with `lint/sync.sh` from a `platform` checkout:

```bash
lint/sync.sh --dotnet --node ../contracts
```

| File | Copied | Sets |
|---|---|---|
| `.editorconfig` | always | UTF-8, LF, final newline, 4-space indent (2 for web, config and Markdown files), and the C# style and naming rules |
| `Directory.Build.props` | with `--dotnet` | `TreatWarningsAsErrors`, `AnalysisLevel=latest-recommended`, `EnforceCodeStyleInBuild`, nullable reference types, the latest C# version, and XML docs, which the unused-usings rule needs to run on build |
| `biome.json` | with `--node` | Biome's recommended lint rules, formatting for TypeScript, JavaScript, JSON and CSS (2 spaces, 100 columns), import sorting and Tailwind directives. Biome adds the Next.js and React rules when `package.json` lists them, and skips files in `.gitignore`. Markdown is off, so the docs keep the same hand-written style as in the repos without Biome. |

| Repo | Flags |
|---|---|
| `contracts` | `--dotnet --node` |
| `sandbox`, `api` | `--dotnet` |
| `web` | `--node` |
| `platform` | none |

`docs` isn't synced. It has no code, so it keeps its own `.editorconfig`.

`sync.sh` also writes `.lint-sync` in the repo: the `platform` commit the copies came from, and the flags. A later run without flags reuses them. The file is rewritten only when a copy or the flags change, and `platform` itself has none. `sync.sh` refuses to run from uncommitted changes in `lint/`, because `.lint-sync` must name a commit that holds the copied files, and it won't write through a symlink.

After a change to `lint/` merges, the update bot (platform#31) runs `lint-sync.yml` in each repo with lint copies. It syncs, builds and tests, then pushes `chore: sync lint configs` to `main`, or opens a PR for the repo's owner if the build fails. Only the first sync, while scaffolding a repo, is done by hand.

`--check` changes nothing: it prints a diff for each copy that differs and exits 1. The reusable CI checks out `platform` at the commit in `.lint-sync` and runs it, so a hand edit fails, but a newer change in `platform` doesn't block a repo while its sync is pending. Don't edit the copies in a repo. Settings for one repo go in its project files, in a nested `Directory.Build.props` that imports the root one, or in a nested `biome.json` with `"extends": "//"`.

| Language | Checked with |
|---|---|
| C# | `dotnet format --verify-no-changes` and the build. Most style rules fail both; `this.` and `Int32` for `int` (IDE0003, IDE0049) fail only `dotnet format`. Underscores in names (CA1707) are allowed under `tests/`, for test names like `Method_Condition_Result`. |
| TypeScript | `biome ci` and `tsc --noEmit`. Repos pin `@biomejs/biome` to the version in `biome.json`'s `$schema` (2.6.4). |
| Protobuf | `buf lint` |

Projects fresh from `dotnet new` don't pass as generated. Run `dotnet format` once, because the templates ship CRLF line endings and a byte order mark, then seal the template's types (CA1852) and add their access modifiers (IDE0040).

## Conventions

- **Conventional Commits, strictly:** `feat: short description`. One line, no body, no co-author trailers.
- **PR titles** use the same format, at most 72 characters, no trailing period. PRs are squash-merged and the squash commit is the PR title, so `main` reads as one clean line per change. The `pr-title` check fails any PR whose title breaks this.
- **Copilot review:** `copilot-review` asks Copilot for one review when a PR opens or is marked ready. It skips drafts, bots, Markdown-only PRs and PRs labelled `skip-copilot`. It needs Copilot on your own account, which is free through GitHub Student.
- **Branches** are `type/anything`, e.g. `feat/warm-pool`, `fix/harness-reconnect`, `ci/pr-title-check`. Same types as commits, no issue number, not checked by CI. Short-lived, cut from `main`, deleted after merge.
- **Branches for an issue:** every issue names its branch in a `Branch:` line. Create it with `gh issue develop 12 --name feat/warm-pool --checkout`, or with the issue's **Create a branch** button and that name instead of GitHub's suggestion (`12-add-warm-pool`). The branch and its PR stay linked to the issue.
- **Reviews:** `main` is protected by a ruleset in every repo: no force-push or deletion, PRs only, squash merges, the `pr-title` check must pass on a branch that is up to date with `main`, and one approval from someone other than the author. `.github/CODEOWNERS` requests Filip's review on every PR, and `pr-assign` assigns the author. Repo admins can bypass the ruleset.
- **Where changes land:** in the code repos, every change goes through a PR, and its README and doc updates go in the same PR as the feature they describe. The `docs` repo is only documentation, so it commits straight to `main`.
- Types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`, `style`.
- **AI agents:** every repo has an `AGENTS.md` that explains the repo and these rules, and a `CLAUDE.md` symlinked to it. Agents ask before creating a branch or committing. The commit, branch and PR rules are identical in all six; change them everywhere at once.

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
