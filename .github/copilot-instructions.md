# Copilot instructions: platform

This repo holds shared tooling for every kubernetes-learning-platform repo: reusable GitHub Actions workflows, canonical lint configs, the demo-host deploy files and the local dev Compose. Nothing here runs as a service. Changes here affect **every** repo. The full design is in the `docs` repo (ARCHITECTURE.md §8).

## When reviewing, focus on
- **Blast radius.** Call out any change to a reusable workflow's inputs, outputs or behaviour that would break the repos calling it at `@main`.
- **Workflow security.**
  - Reusable workflows are `on: workflow_call`.
  - `permissions` defaults to `{}`, with each job granting only what it needs.
  - Never interpolate `${{ github.event.* }}` or other untrusted input directly into `run:`. Pass it through `env:`.
  - Pin third-party actions to a full commit SHA.
  - Every job has a `timeout-minutes`.
- **Secrets.** Only `*.env.example` files are committed, never real env files, tokens or keys.
- **Shell scripts.** `set -euo pipefail`, quoted variables, and the scripts should pass shellcheck.
- **Deploy files.** Compose image tags are pinned through `.env`. Caddy routes `/` to web and `/api` and `/ws` to api. `envmgr` runs under systemd on the host, not in Compose.
- **Lint configs.** A change in `lint/` changes the rules for every repo. Say which repos it affects.

## Conventions this repo enforces
- PR titles are Conventional Commits (`feat: short description`), one line, at most 72 characters, no trailing period. `pr-title.yml` checks this for every repo.
- Branches are `type/anything`, e.g. `feat/warm-pool`.
- Files are UTF-8 with LF line endings.

## Don't
- Don't comment on formatting that `.editorconfig` handles.
- Keep reviews short. Skip praise and summaries of the diff.
