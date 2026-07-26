# Changelog

All notable changes are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
