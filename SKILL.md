---
name: github-skill-manager
description: "Install, update, sync, remove, list, and diagnose THIRD-PARTY Agent Skills hosted on GitHub, mounted as git submodules under workspace/skills/. IMPORTANT: before doing anything, determine which mode a skill is in. Skills the operator owns may live as plain tracked folders in the workspace monorepo, synced to their own repos with git subtree (scripts/skill-pull.sh and scripts/skill-push.sh in the workspace, if present); NEVER install, convert, or re-add those as submodules. Use this skill's scripts only for skills that are (or should be) submodules pointing at repos the operator does not own. Triggers: install a third-party skill from GitHub, update the dembrandt or postiz skills, update all third-party skills, remove a third-party skill, list installed skill submodules, doctor the skill submodule setup, why is the skill directory empty after clone."
license: MIT
metadata:
  version: '0.3.3'
  author: Reda Sadki
  canonical_home: workspace/skills/github-skill-manager
---

# github-skill-manager

Install and maintain third-party GitHub-hosted Agent Skills as git submodules under `workspace/skills/`. The outer workspace repo pins each skill at a specific commit. The inner skill repo remains the canonical source of the skill.

## Two modes: check before doing anything

A workspace can hold skills in two different modes. Determine the mode of a skill before running any command on it:

| Mode | How to recognize it | Who manages it |
|---|---|---|
| **Plain folder (monorepo mode)** | `skills/<name>/` has NO `.git` entry and its files ARE tracked by the outer repo (`git ls-files skills/<name>` prints files). | Ordinary git. Edit, `git add`, `git commit`, `git push` in the workspace. If the workspace has `scripts/skill-pull.sh` and `scripts/skill-push.sh`, those sync the folder with the skill's own repo via `git subtree`. |
| **Submodule** | `skills/<name>/.git` exists (file or directory) and `.gitmodules` has a `[submodule "skills/<name>"]` block. | THIS skill's scripts. |

Rules that follow from the modes:

- **Never install, convert, or re-add a plain-folder skill as a submodule.** If the operator owns the skill and it lives as a plain folder, it is in monorepo mode on purpose. Adding it as a submodule again would recreate the two-level-commit problem the monorepo removed.
- **Skills the operator owns** (same GitHub account as the workspace remote) are normally in monorepo mode. **Skills from other people's repos** are normally submodules and are this skill's job.
- When asked to "update all skills", update the submodules with `update.sh --all` and leave plain folders alone (they update through normal git pulls of the workspace).

## When to use this skill

Use this skill whenever the user says any of the following about a THIRD-PARTY skill (a repo the operator does not own):

- Install / add / set up the `<name>` skill (from a GitHub repo).
- Update / bump / pull the latest for the `<name>` skill.
- Remove / uninstall the `<name>` skill.
- List installed skill submodules.
- Diagnose / doctor / check / fix the skill submodule setup.
- Reports of empty skill directories after cloning the workspace, uncommitted submodule content, or "modified content" showing in `git status`.

Do not use this skill for:

- Skills in plain-folder (monorepo) mode. Use ordinary git, and the workspace's `scripts/skill-pull.sh` / `scripts/skill-push.sh` helpers for syncing with their own repos.
- Building or authoring a new skill from scratch. Use `create-skill` for that. If the resulting skill belongs to the operator, import it as a plain folder (`git subtree add --prefix=skills/<name> <url> main`); only hand off to this skill if it is third-party.
- Skills that ship as tarballs, PyPI packages, or copies of files. This skill only manages skills whose canonical source is a GitHub repository.

## Preconditions

- The outer workspace directory is itself a git working tree. Confirm with `git rev-parse --show-toplevel` before doing anything else.
- The `gh` CLI is available and authenticated, or the user is prepared to use HTTPS with a personal access token. `gh` is preferred because it removes the need to think about auth per command.
- The user has push access to any skill repo they intend to update from this workspace.

If any precondition fails, stop and report to the user rather than trying to work around it.

## Layout

Each skill is mounted at `workspace/skills/<skill-name>/`. The directory name must match the skill's `name` field in its `SKILL.md`. The outer workspace repo records the submodule in `.gitmodules` at the workspace root.

Example of a mixed-mode workspace:

```
workspace/
├── .gitmodules              <-- lists ONLY the submodules
├── scripts/
│   ├── skill-mirrors.txt    <-- monorepo mode: name -> repo URL map
│   ├── skill-pull.sh        <-- monorepo mode: repo -> workspace sync
│   └── skill-push.sh        <-- monorepo mode: workspace -> repo sync
└── skills/
    ├── epub2md/             <-- plain folder (operator-owned, monorepo mode)
    ├── translation/         <-- plain folder (operator-owned, monorepo mode)
    ├── postiz/              <-- submodule -> github.com/gitroomhq/postiz-agent
    └── github-skill-manager/  <-- this skill (may be either mode)
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
