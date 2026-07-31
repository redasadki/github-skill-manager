# Changelog

All notable changes are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] — 2026-07-31

### Fixed

- **Manager scripts died on out-of-scope submodules.** A workspace repo can legitimately host submodules that are not skills, for example a framework mount at `.superpowers/` used by [obra/superpowers](https://github.com/obra/superpowers). Before v0.3.1, `list.sh`, `update.sh --all`, `doctor.sh`, and `sync.sh --all` iterated every entry in `.gitmodules` and called `validate_gitmodules_path`, which killed the script with `error: refusing .gitmodules path outside skills dir 'skills': '.superpowers'.` The path guard exists to reject malformed and traversal paths from `.gitmodules`, not to police what other submodules a workspace may have.

  Split into two functions in `scripts/_lib.sh`:

  - `is_in_scope_submodule` returns 0 or 1 (silent). Callers that iterate every entry in `.gitmodules` skip out-of-scope entries with it. Same shape checks as before (no absolute paths, no `..`, must live under the configured skills directory, final component must be a valid skill name), just non-fatal.
  - `validate_gitmodules_path` is unchanged and still dies on malformed paths, used when the caller has decided an entry is in-scope, or when the user handed a specific path expecting it to be a skill (`install.sh --reconfigure <name>`).

  `list.sh`, `update.sh --all`, `doctor.sh`, and `sync.sh --all` now filter with `is_in_scope_submodule` before doing any work. Non-skill submodules do not appear in the table, do not run the doctor, and do not participate in `--all` operations. They are none of the manager's business.

### Changed

- **`doctor.sh` and `list.sh` message wording.** The final line of a healthy `doctor.sh` run now reads `all skill submodules healthy (N checked)` instead of `all submodules healthy`, and `list.sh` prints `No skill submodules installed under the configured skills directory.` when only non-skill submodules exist. The wording change makes it clear that the manager operates on a subset of `.gitmodules`, not the whole file.

### Added

- **Regression tests for out-of-scope entries.** `tests/list.bats` and `tests/doctor.bats` now install a `.superpowers/` submodule alongside a real skill and assert the manager reports the skill correctly and never touches the framework mount. `tests/test_helper.bash` gains `add_out_of_scope_submodule` for reuse. Total: 44 bats cases (up from 41).

## [0.3.0] — 2026-07-31

### Added

- **Two-way sync (`scripts/sync.sh`).** New subcommand that syncs one skill or every installed skill in both directions between local and origin. For each skill, it counts local-only and remote-only commits against the configured pull branch and picks one of four actions: in sync (no-op), push only (push HEAD to the push branch, bump the outer pointer), pull only (fast-forward, bump the outer pointer), or diverged (print counts and three options, exit 1). Skills without a push branch configured downgrade cleanly to `update.sh` semantics.
- **Per-skill branch configuration in `.gitmodules`.** Two extension fields, `submodule.<path>.ghsmPullBranch` and `submodule.<path>.ghsmPushBranch`, record where to pull upstream improvements from and where to push local commits. The convention for the push branch is `openclaw/<version>` so a host can maintain its host-specific changes on a version-tagged branch in the same repo. Git ignores unknown submodule fields, so a workspace that does not use two-way sync sees them as inert.
- **`install.sh --pull-branch`, `--push-branch`, and `--reconfigure` flags.** Enable two-way sync at install time, or upgrade an already-installed skill to two-way sync without cloning again. `--reconfigure` writes only to `.gitmodules` and best-effort creates the push branch on origin if it does not exist.
- **`references/two-way-sync.md`.** Full conceptual model: branch model, state machine, retroactive migration procedure, and when the tool deliberately refuses to automate a decision.
- **`examples/openclaw-branch.md`.** End-to-end worked example that installs a skill with a `main` pull branch and an `openclaw/2026.7.x` push branch, makes a host-specific edit, syncs, later pulls an upstream change into a diverged state, resolves it with a merge, and syncs again.
- **bats coverage for the new paths.** New `tests/sync.bats` covers all four sync states. `tests/update.bats` gets a clobber-guard regression. `tests/install.bats` and `tests/doctor.bats` cover the flag parsing and configuration checks.

### Changed

- **`update.sh` now reads `ghsmPullBranch` before falling back to `branch` or `origin/HEAD`.** Skills that publish from a non-`main` branch (`master`, `trunk`, a release branch) no longer need special-casing.
- **`list.sh` shows a `SYNC` column instead of a plain `BRANCH` column.** One-way skills read as `pull:<branch>`; two-way skills read as `pull:<a>/push:<b>`.
- **`doctor.sh` now reports two-way sync misconfiguration.** Detects a push branch with no pull branch, and a push branch equal to the pull branch (which defeats the split). Unpushed-commit warnings now distinguish between skills that have a push branch configured (suggest `sync.sh`) and skills that do not (suggest `install.sh --reconfigure` or a manual push).

### Editorial

- **`SKILL.md` reorganized.** The description and triggers now name sync, push, and two-way sync explicitly. A dedicated Two-way sync section documents the branch model and links to `references/two-way-sync.md` for the full conceptual model.
- **`README.md` updated.** New sync column in the scripts table, new links to the two-way sync docs and openclaw example.

## [0.2.1] — 2026-07-31

### Fixed

- **Clobber-prevention gap in `update.sh`.** The previous guard only refused to touch a submodule with a dirty working tree. Local commits that existed only inside the submodule (never pushed) passed the guard and were silently at risk: the next upstream advance produced a fatal fast-forward error, and until then the local commits appeared safe. `update.sh` now fetches origin, resolves the upstream branch from `submodule.<path>.ghsmPullBranch`, then `submodule.<path>.branch`, then `origin/HEAD`, and refuses to proceed when `git rev-list --count origin/<branch>..HEAD` is greater than zero. The error message names the number of local commits and points at the two ways forward: push them by hand, or configure two-way sync (v0.3.0). The old shell pattern `git pull --ff-only` inside the submodule was replaced with `git fetch` plus an explicit `git merge --ff-only` against the resolved upstream ref so the branch used is auditable in the error output.
- **Update against a non-main default branch.** `update.sh` used to assume `origin/main` implicitly through `git pull --ff-only`. It now reads the upstream from `.gitmodules` and falls back to `origin/HEAD`, so skills that publish from `master`, `trunk`, or a release branch work without special-casing.

### Added

- Helpers in `scripts/_lib.sh`: `count_local_only`, `count_remote_only`, `skill_push_branch`, `skill_pull_branch`, `validate_branch_name`. These are the building blocks for the v0.3.0 two-way sync work; v0.2.1 uses them only for the clobber guard in `update.sh`.

## [0.2.0] — 2026-07-26

### Fixed

- **Empty workspace crash.** `list.sh`, `update.sh --all`, and `doctor.sh` now handle a workspace with no `.gitmodules` cleanly instead of failing under `set -eo pipefail` when the file is absent.
- **Silent data-loss risk in `remove.sh`.** The check for unpushed commits now fetches from origin first and refuses to proceed if the fetch fails, the upstream ref cannot be resolved, or origin has diverged from local. Previously a transient network error caused the safety check to be skipped silently. The check now resolves the upstream via `@{u}`, then the `branch` recorded in `.gitmodules`, and only falls back to `origin/HEAD`, which is more robust across self-hosted mirrors where the bare repo has no symbolic `HEAD`.
- **Loose repo URL parser.** `normalize_repo_url` now:
  - escapes the dot in `github.com` (previously `githubXcom` matched),
  - anchors both segments so the URL must be exactly `owner/name`,
  - rejects `owner` or `name` equal to `.` or `..`,
  - accepts `file://` URLs for tests and self-hosted mirrors.
- **Skill name validation.** The name regex now matches the agentskills specification exactly: 1..64 chars, lowercase alnum, single hyphens only, no leading, trailing, or consecutive hyphens. Previously double hyphens slipped past the argument check and failed at `agentskills validate`, giving a confusing error.
- **Half-installed submodules.** `install.sh` now rolls back on any failure between `git submodule add` and the final pointer commit, cleaning up `.gitmodules`, `.git/config`, the working tree, and `.git/modules/`. A retry starts from a clean state.
- **Idempotent install now self-heals.** Rerunning `install.sh` against an already-registered submodule with an empty working tree re-initializes the checkout instead of returning "already installed" and leaving the directory empty.
- **`update.sh --all` no longer aborts on the first failure.** Per-skill failures are reported, the batch continues, and the script exits non-zero at the end if any skill failed.
- **Path safety when iterating `.gitmodules`.** `list.sh`, `update.sh --all`, and `doctor.sh` validate every path read from `.gitmodules` against the skill-name shape and confirm it lives under the configured skills directory. Malformed entries produce a clear diagnostic instead of flowing into shell commands.

### Added

- **`GHSM_SKILLS_DIR` environment variable** to override the auto-detected skills directory. Useful when a workspace has both `workspace/skills/` and `skills/` present.
- **bats test suite** under `tests/`. 24 tests cover install, update, remove, list, and doctor, including the exact failure modes above. Runs from a clean `bats tests/` invocation with no network access.
- **GitHub Actions CI** that installs bats and runs the suite on every push and PR.
- **`references/design.md`** documenting the two-level commit rule, the trust boundary around `.gitmodules`, and the security model.

### Changed

- `SKILL.md` note added about how skill names are validated and how the `file://` transport enables offline testing.
- Error messages throughout now name the offending value and the exact fix command.

## [0.1.0] — 2026-07-26

### Added

- Initial release.
- `SKILL.md` with the full agent contract, triggers, subcommands, and non-negotiable rules.
- `scripts/install.sh` — add a GitHub-hosted skill as a submodule, verify remote reachability, initialize, validate with `agentskills`, commit the pointer.
- `scripts/update.sh` — fast-forward one or all skills, bump the outer pointer only when the SHA changed.
- `scripts/remove.sh` — deinit, remove, delete the leftover git dir, commit the removal.
- `scripts/list.sh` — print installed submodules with pinned SHA, branch, and remote.
- `scripts/doctor.sh` — non-mutating diagnostics that print exact fix commands.
- `references/submodule-guide.md` — the full submodule model, day-to-day workflow, and rationale.
- `references/troubleshooting.md` — recipes for the common failure modes.
- `examples/install-translation.md` — end-to-end worked example.
