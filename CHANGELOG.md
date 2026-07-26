# Changelog

All notable changes are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
