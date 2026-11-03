# platform

> **Shared tooling for every repo:** reusable CI workflows, canonical lint configs, the team's conventions, and the files that deploy the demo host.

Part of [**kubernetes-learning-platform**](https://github.com/kubernetes-learning-platform/docs), an AI tutor with a live Kubernetes lab. Start at the [docs hub](https://github.com/kubernetes-learning-platform/docs) for the big picture.

**Owner:** Filip · **Status:** planned layout, scaffolding lands in M1. Nothing in here runs as a service.

---

## ⚙️ Reusable workflows

Every workflow here is `on: workflow_call`. The other repos call them instead of copying CI.

| Workflow | Does | Used by |
|---|---|---|
| `dotnet-ci.yml` | Format check, build, test | `contracts`, `sandbox`, `api` |
| `node-ci.yml` | ESLint, Prettier, typecheck, test, build | `contracts`, `web` |
| `proto-ci.yml` | `buf lint` / `buf breaking`, codegen, pack, publish | `contracts` |
| `container-publish.yml` | buildx → GHCR, tagged with the commit SHA and version | `api`, `web`, lesson images |
| `release-binary.yml` | `dotnet publish` for linux-x64 and linux-arm64 → GitHub Release | `sandbox` |
| `vm-image.yml` | Builds the VM base image with the pinned harness and lesson images | `sandbox` |
| `pr-title.yml` | Fails a PR whose title isn't a Conventional Commit (max 72 characters, no trailing period) | every repo |

A repo's whole CI file is about this long:

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

## 🧹 Lint configs

The canonical copies live in `lint/`. `sync.sh` copies them into a repo, and the reusable CI fails if a repo's copy drifts.

| Language | Rules |
|---|---|
| C# | `.editorconfig`, `dotnet format --verify-no-changes`, `TreatWarningsAsErrors`, `AnalysisLevel=latest-recommended` |
| TypeScript | ESLint flat config, Prettier, `tsc --noEmit` |
| Protobuf | `buf lint` |

## 📏 Conventions

- **Conventional Commits, strictly:** `feat: short description`. One line, no body, no co-author trailers.
- **PR titles** use the same format. PRs are squash-merged and the squash commit is the PR title, so `main` reads as one clean line per change.
- **Trunk-based:** short-lived branches off `main`, deleted after merge.
- Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `ci`, `build`, `chore`.

## 🚀 deploy/

Everything the single demo host needs (Linux + KVM):

| File | Purpose |
|---|---|
| `docker-compose.yml` | `proxy` (Caddy), `web`, `api`, `postgres`, with image tags pinned through `.env` |
| `Caddyfile` | `/` → web, `/api` and `/ws` → api |
| `envmgr.service` | systemd unit for `envmgr` (it runs on the host, not in Compose) |
| `envmgr.env.example` · `api.env.example` | Config templates. The real `.env` files are never committed. |
| `install.sh` | Fetches the envmgr release and VM image, installs the unit, runs `docker compose up` |

## 🧪 dev/

`docker-compose.dev.yml` runs Postgres and api against a **fake** (or Docker-provider) sandbox, so `api` and `web` can be developed on any laptop without KVM.

## 📁 Layout

```
platform/
├── .github/workflows/     # the reusable workflows above
├── lint/                  # .editorconfig, Directory.Build.props, eslint + prettier configs, sync.sh
├── deploy/                # demo host: compose, Caddyfile, systemd unit, env examples, install.sh
└── dev/                   # local dev compose
```

## 📚 More

- [ARCHITECTURE §8 CI/CD & shared tooling](https://github.com/kubernetes-learning-platform/docs/blob/main/ARCHITECTURE.md#8-cicd--shared-tooling-filip)
- [ARCHITECTURE §3 Runtime architecture](https://github.com/kubernetes-learning-platform/docs/blob/main/ARCHITECTURE.md#3-runtime-architecture)

## 📄 License

[MIT](LICENSE)
