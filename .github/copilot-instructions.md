# Copilot instructions: platform

This repo holds shared tooling for every kubernetes-learning-platform repo: reusable GitHub Actions workflows, canonical lint configs, the infrastructure code (OpenTofu), the per-machine deploy files (Hetzner box, Proxmox box, WireGuard mesh) and the local dev Compose. Nothing here runs as a service. Changes here affect **every** repo. The full design is in the `docs` repo (ARCHITECTURE.md §8).

## When reviewing, focus on
- **Blast radius.** Call out any change to a reusable workflow's inputs, outputs or behaviour that would break the repos calling it at `@main`.
- **Workflow security.**
  - Reusable workflows are `on: workflow_call`.
  - `permissions` defaults to `{}`, with each job granting only what it needs.
  - Never interpolate `${{ github.event.* }}` or other untrusted input directly into `run:`. Pass it through `env:`.
  - Pin third-party actions to a full commit SHA.
  - Every job has a `timeout-minutes`.
- **Secrets.** Only `*.env.example` files are committed, never real env files, tokens, WireGuard private keys or OpenTofu state.
- **Shell scripts.** `set -euo pipefail`, quoted variables, and the scripts should pass shellcheck.
- **Deploy files.** Compose image tags are pinned through `.env`. Caddy routes `/` to web and `/api` and `/ws` to api, and is published only on the Hetzner box's mesh address (`10.66.0.1`). `envmgr` runs under systemd on the Proxmox host, not in Compose. Flag anything that exposes the stack on a public address.
- **Network isolation.** Sandboxes on `vmbr1` may reach only `10.67.0.1:7071`, and envmgr's gRPC port accepts only `10.66.0.1`. Flag rule changes that widen either.
- **Infra code.** OpenTofu stays limited to long-lived infrastructure; sandboxes are created by envmgr, not here. The Proxmox token for envmgr stays scoped to the `kl-sandboxes` pool.
- **Self-hosted runner.** Only `vm-image.yml` runs on it. Flag other workflows that target it.
- **Lint configs.** A change in `lint/` changes the rules for every repo. Say which repos it affects.

## Conventions this repo enforces
- PR titles are Conventional Commits (`feat: short description`), one line, at most 72 characters, no trailing period. `pr-title.yml` checks this for every repo.
- `copilot-review.yml` requests one Copilot review per PR, because reviews cost AI credits. Flag changes that make it run more often: triggering on `synchronize`, or dropping a skip (drafts, bots, forks, Markdown-only PRs, the `skip-copilot` label, already reviewed).
- Branches are `type/anything`, e.g. `feat/warm-pool`.
- Files are UTF-8 with LF line endings.

## Don't
- Don't comment on formatting that `.editorconfig` handles.
- Keep reviews short. Skip praise and summaries of the diff.
