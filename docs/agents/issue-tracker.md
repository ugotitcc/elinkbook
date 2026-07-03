# Issue tracker: Gitea

Issues and PRDs for this repo live as Gitea issues on `https://git.jigong.org/huthief/elinkBook`. Use the [`tea`](https://gitea.com/gitea/tea) CLI for all operations (logged in as `jigong`).

## Conventions

- **Create an issue**: `tea issues create --repo huthief/elinkBook --title "..." --description "..." --labels "..."`
- **Read an issue**: `tea issues <index> --repo huthief/elinkBook`
- **List issues**: `tea issues list --repo huthief/elinkBook`, filter with `--labels`/`--state` as needed
- **Comment on an issue**: `tea comment <index> --repo huthief/elinkBook "..."`
- **Apply / remove labels**: `tea issues create --labels "..."` at creation time, or edit the issue's labels via `tea issues edit <index> --repo huthief/elinkBook --labels "..."`
- **Close**: `tea issues close <index> --repo huthief/elinkBook`

Labels must exist on the repo before they can be applied — see `docs/agents/triage-labels.md`. The repo currently has no labels created yet.

## Pull requests as a triage surface

Not applicable — Gitea is used here purely as a private issue tracker for this solo project; external PRs are not a request surface.

## When a skill says "publish to the issue tracker"

Create a Gitea issue with `tea issues create`.

## When a skill says "fetch the relevant ticket"

Run `tea issues <index> --repo huthief/elinkBook`.
