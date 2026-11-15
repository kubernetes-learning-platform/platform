# Copilot instructions: platform

This repo holds shared tooling for every kubernetes-learning-platform repo: reusable GitHub Actions workflows, canonical lint configs, the install script and deploy files for the course VM, and the local dev Compose. Nothing here runs as a service. Changes here affect **every** repo. The full design is in the `docs` repo (ARCHITECTURE.md §8).

## When reviewing, focus on
- **Blast radius.** Call out any change to a reusable workflow's inputs, outputs or behaviour that would break the repos calling it at `@main`. Flag a renamed job in `dotnet-ci.yml`, `node-ci.yml` or `proto-ci.yml`: its name is part of the callers' required check names.
- **Workflow security.**
  - Reusable workflows are `on: workflow_call`.
  - `permissions` defaults to `{}`, with each job granting only what it needs.
  - Never interpolate `${{ github.event.* }}` or other untrusted input directly into `run:`. Pass it through `env:`.
  - Pin third-party actions to a full commit SHA.
  - Every job has a `timeout-minutes`.
- **Secrets.** Only `*.env.example` files are committed, never real env files, tokens, Tailscale auth keys or the Cloudflare token.
- **Shell scripts.** `set -euo pipefail`, quoted variables, and the scripts should pass shellcheck.
- **Deploy files.** Image tags are pinned, never `latest`. Caddy routes `/` to web and `/api` and `/ws` to api, and listens only on the VM's Tailscale address, with its certificate from DNS-01. `envmgr` runs under systemd on the host, not in the stack. The deploy format (Compose or Helm on k3s) is OPEN, so flag a change that commits to one without an ADR. Flag anything that exposes the stack on a public address.
- **Network isolation.** Sandboxes on the isolated libvirt network may reach only `10.67.0.1:7071`, and envmgr's gRPC port accepts only the stack. Sandboxes can't reach RabbitMQ. The tailnet ACL allows only SSH and the app's HTTPS port. Flag rule changes that widen any of these.
- **No infrastructure code.** The course VM is set up by `deploy/vm/install.sh`; sandboxes are created by envmgr, not here.
- **Self-hosted runner.** Only the deploy workflow and `sandbox-template.yml` run on it, started from the private deploy repo. The repos are public and the runner group blocks public repos. Flag other workflows that target it.
- **Update bot.** `contracts-bump.yml` and `lint-sync.yml` push to a repo's `main` with the GitHub App's token only after the build and tests pass; otherwise they open a PR. Flag changes that let them push without a passing build, and any job that can use the App's key from a pull request. `pr-assign.yml` must stay on `pull_request` and never check out PR code.
- **Lint configs.** A change in `lint/` changes the rules for every repo. Say which repos it affects. Platform's root `.editorconfig` must stay identical to `lint/.editorconfig`, and the Biome version in `biome.json`'s `$schema` is the one every repo pins. `lint/sync.sh` records the `platform` commit and its flags in each repo's `.lint-sync`.

## Conventions this repo enforces
- PR titles are Conventional Commits (`feat: short description`), one line, at most 72 characters, no trailing period. `pr-title.yml` checks this for every repo.
- `copilot-review.yml` requests one Copilot review per PR, because reviews cost AI credits. Flag changes that make it run more often: triggering on `synchronize`, or dropping a skip (drafts, bots, forks, Markdown-only PRs, the `skip-copilot` label, already reviewed).
- Branches are `type/anything`, e.g. `feat/warm-pool`, taken from the issue's `Branch:` line.
- Files are UTF-8 with LF line endings.

## Don't
- Don't comment on formatting that `.editorconfig` handles.
- Keep reviews short. Skip praise and summaries of the diff.
