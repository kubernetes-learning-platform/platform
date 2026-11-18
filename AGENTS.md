# AGENTS.md: platform

Instructions for AI coding agents working in this repository. `CLAUDE.md` is a symlink to this file, so Claude Code reads the same instructions.

## What this repo is

Shared tooling for every kubernetes-learning-platform repo. Nothing here runs as a service, but a change here can affect **every** repo.

| Folder | What it holds |
|---|---|
| `.github/workflows/` | Reusable workflows (`on: workflow_call`) that every repo calls in a few lines |
| `.github/actions/` | `update-branch`, the update bot's commit step, used by `contracts-bump.yml` and `lint-sync.yml` |
| `lint/` | Canonical `.editorconfig`, `Directory.Build.props` and `biome.json`, plus `sync.sh` to copy them into a repo |
| `deploy/vm/` | The install script and config files for the course VM |
| `dev/` | The local dev Compose file: Postgres, RabbitMQ, an optional DinD sandbox profile |

The course VM (16 vCPU, 32 GB) runs everything and is reached only over Tailscale. Caddy serves our Cloudflare domain with a DNS-01 certificate. `envmgr` runs under systemd on the host. The deploy format for the stack, Docker Compose or a Helm chart on k3s, is OPEN.

- **Owner:** Filip.
- **Status:** `pr-title.yml`, `copilot-review.yml`, `pr-assign.yml`, `dotnet-ci.yml`, `node-ci.yml`, `proto-ci.yml`, `proto-release.yml`, `platform-check.yml`, the update bot (`contracts-bump.yml`, `lint-sync.yml`, `update-push.yml`, `lint-updated.yml`, `.github/actions/update-branch/`) and `lint/` exist. The CI workflows don't run tests yet. Everything else is planned in the setup issues.
- **Design:** `README.md` here, and ARCHITECTURE §8 and ADR 0003 in the `docs` repo. Where they disagree, the `docs` repo wins.

## Layout

```
platform/
├── .github/workflows/   # pr-title, copilot-review, pr-assign, dotnet-ci, node-ci, proto-ci, proto-release,
│                        # contracts-bump, lint-sync, update-push, lint-updated, container-publish,
│                        # release-binary, sandbox-template, platform-check
├── .github/actions/     # update-branch: action.yml, commit.sh
├── lint/                # .editorconfig, Directory.Build.props, biome.json, sync.sh
├── deploy/vm/           # install.sh, envmgr unit, libvirt network, nftables, Caddyfile, *.env.example
└── dev/                 # docker-compose.dev.yml
```

## Build and check

There is no build. Before saying a change is done:

- Run `actionlint` on changed workflows and `shellcheck` on changed scripts, when they are installed.
- For a reusable workflow, check every repo that calls it at `@main` and say which ones the change affects.

## Rules

- **Required check names.** The job names in `dotnet-ci.yml`, `node-ci.yml` and `proto-ci.yml` (`.NET checks`, `Node checks`, `Protobuf checks`) are part of the required check names in the callers' rulesets, as in `ci / .NET checks`. Renaming one blocks every merge in the repos that require it until their rulesets are updated. The update bot also calls the three through `update-push.yml` with their `ref` input, so keep `ref` working.
- **Blast radius.** A change to a reusable workflow's inputs, outputs or behaviour breaks every caller at `@main`. Keep it backward compatible or update the callers in the same piece of work.
- **Workflow security.** Reusable workflows are `on: workflow_call`. `permissions` defaults to `{}`, and each job grants only what it needs. Never put `${{ github.event.* }}` or other untrusted input directly into `run:`; pass it through `env:`. Third-party actions are pinned to a full commit SHA. Every job has `timeout-minutes`.
- **Secrets.** Only `*.env.example` files are committed. Never real env files, tokens, Tailscale auth keys, the Cloudflare token or GitHub App keys.
- **Scripts** start with `set -euo pipefail` and quote their variables.
- **Deploy files.** Image tags are pinned, never `latest`. Caddy routes `/` to `web` and `/api` and `/ws` to `api`, and listens only on the VM's Tailscale address. `envmgr` stays a systemd unit on the host. Don't commit to Compose or Helm for the stack until an ADR decides it.
- **Network isolation.** Sandboxes reach only `envmgr`'s harness endpoint (`10.67.0.1:7071`). `envmgr`'s gRPC port accepts only the stack. Sandboxes can't reach RabbitMQ. The tailnet ACL allows only SSH and the app's HTTPS port. Never widen any of these without the user's say-so.
- **No infrastructure code.** The course VM is set up by `deploy/vm/install.sh`. Sandboxes are created by `envmgr`, not here.
- **Self-hosted runner.** Only the deploy workflow and `sandbox-template.yml` run on it, both started from the private deploy repo. The org's runner group blocks public repos, and that stays so.
- **Update bot (platform#31).** `contracts-bump.yml` (on `contracts-published`) and `lint-sync.yml` (on `lint-updated`) commit their change through the API with `.github/actions/update-branch/`, so GitHub signs it, then `update-push.yml` runs the repo's reusable CI on it and fast-forwards `main`, or opens a PR assigned to the `*` code owners if the CI fails. Never push to `main` without that CI, and never force-push it. The App's client ID is the org variable `UPDATE_BOT_APP_ID` and its key the org secret `UPDATE_BOT_PRIVATE_KEY`; tokens are minted per repo with only the permissions the step needs. The App is on the `main` ruleset bypass list in `contracts`, `sandbox`, `api` and `web`, and nothing else gets a bypass except repo admins. `lint-updated.yml` sends `lint-updated` only from pushes to `platform/main`, and the callers run only on `repository_dispatch`, never on a PR, because the App's key must not reach PR code. How the bump finds the version is in the README's Update bot section.
- **PR assignment.** `pr-assign.yml` runs on `pull_request`, skips forks and bots, and never checks out PR code. Don't switch it to `pull_request_target`.
- **Copilot reviews cost credits.** `copilot-review.yml` requests one review per PR. Don't make it run more often.
- **Lint configs.** A change in `lint/` changes the rules for every repo. Say which repos it affects. `lint/sync.sh` copies `.editorconfig` always, `Directory.Build.props` with `--dotnet` and `biome.json` with `--node`, and records the `platform` commit and the flags in the repo's `.lint-sync`; `--check` only reports drift. It rewrites `.lint-sync` when a copy or the flags change, or when the recorded commit isn't in the checkout's history or holds other copies (a squash-merged PR branch), and otherwise leaves it alone, so a `lint/` change that doesn't touch a repo's copies makes the bot push nothing. Test a `sync.sh` change against a throwaway repo before saying it works. After a merge, the update bot syncs the other repos, so a rule that breaks a repo's build ends up as a PR for its owner. Platform's own root `.editorconfig` stays identical to `lint/.editorconfig`: run `lint/sync.sh .` after changing it. The `$schema` version in `biome.json` is the Biome version every repo pins. Biome's Markdown formatter and linter are off, so docs keep the same hand-written style in every repo.

## Commits, branches and PRs

- **Always ask the user before creating a branch, committing or pushing.** Show the commit message when you ask.
- **Commits:** Conventional Commits only, one line: `type: short description`, lowercase, no trailing period. No body. No `Co-Authored-By` or any other attribution.
- **Types:** `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`, `style`. Add `!` for a breaking change.
- **Branches:** use the name in the `Branch:` line of the issue being worked on. Don't make one up. `gh issue develop <number> --name <branch> --checkout` creates it linked to the issue.
- **Where changes land:** every change goes through a PR from the issue's branch. README, `AGENTS.md` and other doc updates go in the PR of the feature they describe, not in separate commits. When a change in another repo makes this repo's docs wrong, fix them in a small `docs:` PR here. Only the `docs` repo commits straight to `main`.
- **PRs:** the title follows the commit format, at most 72 characters; it becomes the squash commit on `main`. The description is one or two plain sentences, plus `Closes #<number>`. Merging needs one approval from someone other than the author, and the branch must be up to date with `main`. Filip is requested as reviewer on every PR (`.github/CODEOWNERS`), and the author is assigned automatically. Only Filip merges.
- **Public repo:** everything committed is public at once. Never commit secrets, real `.env` files or personal data; push protection only catches known token formats.

## Keep docs in sync

When a change touches this repo's design, layout, commands or conventions, update `AGENTS.md`, `README.md` and `.github/copilot-instructions.md` in the same change. If it changes a design fact, update ARCHITECTURE §8 or ADR 0003 in the `docs` repo too, and mention it to the user.

The commit, branch and PR rules above are the same in every repo's `AGENTS.md`. If they change, change them everywhere.

## Writing style

Plain, professional wording in docs and comments. No emoji, no marketing tone. Files are UTF-8 with LF line endings, following `.editorconfig`.
