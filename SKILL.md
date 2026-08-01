---
name: github-skill-manager
description: "Install, update, sync, remove, list, and diagnose Agent Skills hosted on GitHub, mounted as git submodules under workspace/skills/. Use this skill when the user says install / add / set up a GitHub skill, update / bump / pull the latest for a skill, sync a skill two ways with GitHub, push local changes to the skill repo, remove / uninstall a skill, list installed skills, or diagnose / doctor a skill that is broken or drifted. Handles the two-level commit workflow and the two-way sync split between an upstream pull branch and a host-specific push branch (for example openclaw/2026.7.x) so local improvements are not clobbered by upstream fast-forwards. Triggers: use the github-skill-manager to set up the new X skill, install the epub2md skill from GitHub, update the translation skill, sync the translation skill both ways with GitHub, configure two-way sync for a skill, remove skill Y, list installed GitHub skills, doctor the skill setup, why is the skill directory empty after clone."
license: MIT
metadata:
  version: '0.3.2'
  author: Reda Sadki
  canonical_home: workspace/skills/github-skill-manager
---

# github-skill-manager

Install and maintain GitHub-hosted Agent Skills as git submodules under `workspace/skills/`. The outer workspace repo pins each skill at a specific commit. The inner skill repo remains the canonical source of the skill.

## When to use this skill

Use this skill whenever the user says any of:

- Install / add / set up the `<name>` skill (from a GitHub repo).
- Update / bump / pull the latest for the `<name>` skill.
- Remove / uninstall the `<name>` skill.
- List installed skills / what skills are installed from GitHub.
- Diagnose / doctor / check / fix the skill setup.
- Reports of empty skill directories after cloning the workspace, uncommitted submodule content, or "modified content" showing in `git status`.

Do not use this skill for:

- Building or authoring a new skill from scratch. Use `create-skill` for that, then hand off to this skill to install the resulting repo.
- Skills that ship as tarballs, PyPI packages, or copies of files. This skill only manages skills whose canonical source is a GitHub repository.

## Preconditions

- The outer workspace directory is itself a git working tree. Confirm with `git rev-parse --show-toplevel` before doing anything else.
- The `gh` CLI is available and authenticated, or the user is prepared to use HTTPS with a personal access token. `gh` is preferred because it removes the need to think about auth per command.
- The user has push access to any skill repo they intend to update from this workspace.

If any precondition fails, stop and report to the user rather than trying to work around it.

## Layout

Each skill is mounted at `workspace/skills/<skill-name>/`. The directory name must match the skill's `name` field in its `SKILL.md`. The outer workspace repo records the submodule in `.gitmodules` at the workspace root.

Example, after installing three skills:

```
workspace/
├── .gitmodules
└── skills/
    ├── epub2md/           <-- submodule -> github.com/redasadki/epub2md
    ├── translation/       <-- submodule -> github.com/redasadki/translation
    └── github-skill-manager/  <-- this skill
```

## Subcommands

This skill exposes six subcommands via `scripts/`. All scripts are idempotent, non-interactive, and return non-zero with a clear message on failure.

| Command | Purpose |
|---|---|
| `scripts/install.sh [flags] <repo> [name]` | Add a new skill as a submodule and pin it. Flags: `--pull-branch`, `--push-branch`, `--reconfigure`. |
| `scripts/update.sh <name\|--all>` | Fast-forward a skill from its pull branch and bump the outer pointer. Refuses to touch a skill with local commits (clobber guard). |
| `scripts/sync.sh <name\|--all>` | Two-way sync between local and origin. Pushes local commits to the configured push branch and pulls upstream improvements from the pull branch. |
| `scripts/remove.sh <name>` | Deinit, remove, and delete the submodule cleanly. |
| `scripts/list.sh` | Print installed GitHub-backed skills, pinned commits, and sync mode. |
| `scripts/doctor.sh` | Diagnose common problems and print concrete fixes. |

All scripts run from the workspace root. They discover the workspace root automatically via `git rev-parse --show-toplevel`, so you can invoke them from anywhere inside the workspace.

## Installing a new skill

Trigger: "use the github-skill-manager to set up the new `<name>` skill" or "install `<repo>` as a skill".

Steps the agent should perform:

1. Resolve the GitHub repo. Accept any of these input forms:
   - `owner/name` (for example `redasadki/translation`).
   - Full HTTPS URL (`https://github.com/redasadki/translation.git`).
   - Full SSH URL (`git@github.com:redasadki/translation.git`).
   The user's default account for `owner` is the value returned by `gh api user --jq .login`. When the user says only "install the translation skill", assume `<default-owner>/translation` and confirm with the user before proceeding if the repo does not exist.
2. Confirm the outer workspace repo has a clean working tree, or is at least free of unrelated staged changes. If not, stop and ask before proceeding.
3. Run:
   ```bash
   bash workspace/skills/github-skill-manager/scripts/install.sh <owner>/<repo> [<name>]
   ```
   `<name>` defaults to the repo name. Pass it explicitly only when the desired mount name differs from the repo name.
4. On success, the script has already:
   - Added the submodule at `workspace/skills/<name>/`.
   - Recorded it in `.gitmodules`.
   - Committed the submodule pointer in the outer workspace repo.
   - Validated the skill with `agentskills validate` when that tool is available.
5. Push the outer workspace repo:
   ```bash
   git push
   ```

The install script refuses to overwrite an existing directory at that path and refuses to add a submodule whose repo is not reachable via `git ls-remote`.

## Updating a skill (one-way)

Trigger: "update the `<name>` skill", "pull the latest for `<name>`", "bump `<name>`".

```bash
bash workspace/skills/github-skill-manager/scripts/update.sh <name>
```

Or for every installed skill:

```bash
bash workspace/skills/github-skill-manager/scripts/update.sh --all
```

The script:

- Enters the submodule, fetches origin, and fast-forwards to the pull branch (`submodule.<path>.ghsmPullBranch`, then `submodule.<path>.branch`, then `origin/HEAD`).
- Refuses to touch a submodule with uncommitted changes.
- Refuses to touch a submodule with local commits that are not on the pull branch. This is the v0.2.1 clobber guard. When the message names local commits, use `sync.sh` instead (if a push branch is configured) or push by hand.
- Returns to the workspace root, stages the new submodule pointer, and commits it as `Bump <name> skill to <short-sha>` when the SHA actually changed.
- Prints "already up to date" and exits 0 when the pointer did not move.

The agent should then push:

```bash
git push
```

## Two-way sync

Trigger: "sync `<name>` with GitHub", "push my local changes to the `<name>` skill", "the skill has local edits that need to go back to GitHub".

Two-way sync keeps a skill useful both as a shared upstream and as a locally-improved copy. It splits the branches:

- **Pull branch** (`ghsmPullBranch`) is where upstream improvements land. Usually `main`.
- **Push branch** (`ghsmPushBranch`) is where this host's local commits go. The convention is `openclaw/<version>`, for example `openclaw/2026.7.x`. This ties host-specific work (venv setup, environment variables, adjusted triggers) to a specific OpenClaw release so a future release can maintain its own branch in the same repo.

Enable two-way sync at install time:

```bash
bash workspace/skills/github-skill-manager/scripts/install.sh \
  --pull-branch main \
  --push-branch openclaw/2026.7.x \
  redasadki/translation
```

Or on an already-installed skill:

```bash
bash workspace/skills/github-skill-manager/scripts/install.sh \
  --reconfigure \
  --push-branch openclaw/2026.7.x \
  translation
```

Then sync:

```bash
bash workspace/skills/github-skill-manager/scripts/sync.sh <name>
```

Or for every configured skill:

```bash
bash workspace/skills/github-skill-manager/scripts/sync.sh --all
```

The script counts local-only and remote-only commits against the pull branch and picks one of four actions:

| State | Condition | Action |
|---|---|---|
| In sync | local-only == 0 and remote-only == 0 | No-op. |
| Push only | local-only > 0 and remote-only == 0 | Push HEAD to the push branch, bump the outer pointer. |
| Pull only | local-only == 0 and remote-only > 0 | Fast-forward from the pull branch, bump the outer pointer. |
| Diverged | Both > 0 | Print counts and three options (merge, rebase, defer), exit 1. |

Skills without a push branch configured behave like `update.sh`: pull only, and any local commit is a hard error. See `references/two-way-sync.md` for the full model and worked examples.

## Editing a skill from inside the workspace

When the user asks the agent to edit `workspace/skills/<name>/` directly, follow the two-level commit rule:

1. Before editing, sync the skill so local and origin agree:
   ```bash
   bash workspace/skills/github-skill-manager/scripts/sync.sh <name>
   ```
   For a one-way skill (no push branch), use `update.sh` instead.
2. Make the edits.
3. Commit inside the submodule:
   ```bash
   cd workspace/skills/<name>
   git add -A
   git commit -m "<what changed and why>"
   ```
4. Sync the local commit back to origin and bump the outer pointer in one step:
   ```bash
   cd -                                # back to workspace root
   bash workspace/skills/github-skill-manager/scripts/sync.sh <name>
   git push                            # push the outer repo
   ```

For a one-way skill, `sync.sh` refuses to push, and the correct sequence is:

```bash
cd workspace/skills/<name>
git push origin main                # or the skill's default branch
cd -
git add workspace/skills/<name>
git commit -m "Bump <name> skill to $(cd workspace/skills/<name> && git rev-parse --short HEAD)"
git push
```

Never commit the pointer bump without pushing the inner commit first. If the inner push fails, roll back the outer stage with `git restore --staged workspace/skills/<name>` before doing anything else.

## Removing a skill

Trigger: "remove the `<name>` skill", "uninstall `<name>`".

```bash
bash workspace/skills/github-skill-manager/scripts/remove.sh <name>
```

The script:

- Deinitializes the submodule (`git submodule deinit -f`).
- Removes the submodule entry (`git rm -f`).
- Deletes the leftover `.git/modules/workspace/skills/<name>/` directory.
- Stages the resulting changes to `.gitmodules` and the tree.
- Commits `Remove <name> skill`.

The user still needs to `git push`.

## Listing installed skills

```bash
bash workspace/skills/github-skill-manager/scripts/list.sh
```

Prints a table:

```
NAME                     PINNED       SYNC                     REMOTE
epub2md                  a9591ab      pull:main                github.com:redasadki/epub2md
translation              3fa1c8d      pull:main/push:openclaw/2026.7.x  github.com:redasadki/translation
github-skill-manager     b2e04af      pull:main                github.com:redasadki/github-skill-manager
```

## Diagnosing problems

Trigger: "doctor the skill setup", "why is `workspace/skills/<name>` empty", "git status shows modified content on a submodule".

```bash
bash workspace/skills/github-skill-manager/scripts/doctor.sh
```

For each installed submodule the script checks and reports:

- Is the checkout initialized (`.git` present, not just an empty directory)?
- Is the pinned SHA the same as `git rev-parse HEAD` inside the submodule?
- Does the submodule have uncommitted or unpushed changes?
- Does `SKILL.md` exist and validate?
- Is the remote reachable via `git ls-remote`?
- Are `.gitmodules` and the tree gitlink consistent?

For each failure it prints a one-line diagnosis and the exact command that fixes it. It never runs a fix on its own.

## First-time clone of a workspace that already has submodules

When someone (or the same user on a new machine) clones the workspace repo for the first time and the `workspace/skills/<name>/` directories look empty, they missed the recursive init. Fix:

```bash
git submodule update --init --recursive
```

Set this globally once so it happens automatically on future `git pull`, `git checkout`, and `git clone`:

```bash
git config --global submodule.recurse true
```

## Non-negotiable rules

- Never run `git reset --hard`, `git push --force`, or `git clean -fdx` inside a submodule without explicit user approval.
- Never commit a pointer bump in the outer repo without first pushing the inner commit.
- Never edit files in `workspace/skills/<name>/` without first running `git pull --rebase` inside that directory in the same session.
- Never `rm -rf` a submodule directory as a shortcut for removal. Use `scripts/remove.sh`.
- Never nest a plain (non-submodule) clone inside the workspace repo. Either it is a submodule or it lives outside the workspace.

## Configuration

Set `GHSM_SKILLS_DIR` to override the auto-detected skills directory. Absolute path or a path relative to the workspace root. Defaults to `workspace/skills/`, or `skills/` when that already exists at the workspace root.

## Skill name rules

The `<name>` argument (implicit or explicit) must match the agentskills specification: 1 to 64 characters, lowercase letters and digits, single hyphens only, no leading, trailing, or consecutive hyphens. The scripts enforce this before calling git so an invalid name fails fast instead of at `agentskills validate`.

## References

- `MANUAL.md` — human operator manual (setup, common tasks, troubleshooting, safety rules). Point the user at this when they hit an error at the terminal.
- `references/submodule-guide.md` — the full submodule model, day-to-day workflow, and rationale.
- `references/design.md` — the security model and non-obvious design decisions.
- `references/two-way-sync.md` — the branch model, state machine, and retroactive migration.
- `references/troubleshooting.md` — recipes for the common failure modes.
- `examples/install-translation.md` — worked example, end to end (one-way).
- `examples/openclaw-branch.md` — worked example, end to end (two-way sync with an openclaw branch).
