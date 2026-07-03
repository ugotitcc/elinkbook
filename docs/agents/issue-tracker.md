# Issue tracker: Local Markdown (SDD Epic Sandbox)

Issues and specs for this repo live as markdown files under `docs/epics/<epic-name>/`, following the project's Spec-Driven Development (SDD) workflow. Gitea (`git.jigong.org/huthief/elinkBook`) remains the git remote for code, but is not used as the issue tracker.

## Conventions

- `docs/epics.md` is the **global status board**: every epic gets one row (code/name, status ⚪Backlog/🟡Active/🟢Archived, current storage path, linked PRD section, notes). Register a new epic here (status `Active`, path filled in) before starting its Discovery phase; update status/path to `Archived` when it's archived. This is the single place to check "what epic am I looking for and where does it currently live."
- One epic per directory: `docs/epics/<epic-name>/`
- Discovery output: `docs/epics/<epic-name>/design.md`
- Architecting output (core interfaces/types, single source of truth for the epic): `docs/epics/<epic-name>/spec.md`
- Implementation issues (thin vertical slices), each including its required unit-test coverage: `docs/epics/<epic-name>/issues.md`
- Per-issue implementation plans: `docs/epics/<epic-name>/plans/plan-issue-<N>.md`
- Per-issue review records: `docs/epics/<epic-name>/reviews/review-issue-<N>.md`
- Bugfix repro reports (bypasses design/spec phases): `docs/epics/<epic-name>/reviews/bugfix-repro.md`
- Triage state is recorded as a `Status:` line near the top of each issue entry — see `docs/agents/triage-labels.md` for the role strings
- Once an epic's code has fully merged and stabilized, move the whole `docs/epics/<epic-name>/` directory to `docs/archive/<YYYY-MM-DD>-<short-name>/`

## When a skill says "publish to the issue tracker"

Add an entry to `docs/epics/<epic-name>/issues.md`, creating the epic's directory/file if it doesn't exist yet.

## When a skill says "fetch the relevant ticket"

Read the relevant entry in `docs/epics/<epic-name>/issues.md`, plus its `plans/plan-issue-<N>.md` and `reviews/review-issue-<N>.md` if they exist.
