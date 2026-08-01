# github-skill-manager

An Agent Skill that installs, updates, two-way syncs, removes, lists, and diagnoses other Agent Skills hosted on GitHub, mounted as git submodules under `workspace/skills/`.

Use it when the user says any of:

- Install / add / set up the `<name>` skill.
- Update / bump / pull the latest for `<name>`.
- Sync `<name>` two ways with GitHub, push local changes to the skill repo.
- Remove / uninstall `<name>`.
- List installed skills.
- Doctor / diagnose the skill setup.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/install.sh [flags] <repo> [name]` | Add a new skill as a submodule and pin it. `--pull-branch`, `--push-branch`, and `--reconfigure` flags enable two-way sync. |
| `scripts/update.sh <name\|--all>` | Fast-forward a skill from its pull branch and bump the outer pointer. Refuses to clobber local commits. |
| `scripts/sync.sh <name\|--all>` | Two-way sync: push local commits to the configured push branch and pull upstream from the pull branch. |
| `scripts/remove.sh <name>` | Deinit and remove the submodule cleanly. |
| `scripts/list.sh` | Print installed submodules with pinned SHA, sync mode, and remote. |
| `scripts/doctor.sh` | Diagnose common problems, print concrete fix commands. |

All scripts are idempotent, non-interactive, and refuse to touch a submodule with uncommitted work unless the caller has cleared it first.

## Read next

- [`MANUAL.md`](MANUAL.md) for the human operator manual (setup, common tasks, troubleshooting, safety rules).
- `SKILL.md` for the full agent-facing contract.
- `references/submodule-guide.md` for the underlying model.
- `references/design.md` for the security model and non-obvious design decisions.
- `references/two-way-sync.md` for the branch model, the state machine, and the retroactive migration procedure.
- `references/troubleshooting.md` for the common failure modes.
- `examples/install-translation.md` for a one-way worked example.
- `examples/openclaw-branch.md` for a two-way sync worked example with an openclaw branch.

## Tests

A [bats-core](https://github.com/bats-core/bats-core) test suite lives under `tests/`. It covers install, update, sync, remove, list, and doctor, including the two-way sync state machine and the regression paths documented in `references/design.md`. Tests use local bare repos as fake remotes and require no network access.

```bash
# install bats: https://github.com/bats-core/bats-core#installation
bats tests/
```

CI runs the suite on every push and PR via `.github/workflows/ci.yml`.

## Configuration

| Environment variable | Purpose |
|---|---|
| `GHSM_SKILLS_DIR` | Override the auto-detected skills directory. Absolute or relative to the workspace root. Defaults to `workspace/skills/`, or `skills/` when that already exists at the workspace root. |

## Install this skill itself

Because this skill manages skills, it is convenient to install it first, by hand, so it can then manage everything else:

```bash
git submodule add https://github.com/redasadki/github-skill-manager.git workspace/skills/github-skill-manager
git commit -m "Add github-skill-manager skill as submodule"
git push
```

After this one-time setup, use `scripts/install.sh` for every subsequent skill.
