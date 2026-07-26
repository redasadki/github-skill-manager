---
name: github-skill-manager
description: "Install, update, remove, list, and diagnose Agent Skills hosted on GitHub, mounted as git submodules under workspace/skills/. Use this skill when the user says install / add / set up a GitHub skill, update / bump / pull the latest for a skill, remove / uninstall a skill, list installed skills, or diagnose / doctor a skill that is broken or drifted. Handles the two-level commit workflow (commit inside the submodule, then bump the pointer in the outer workspace repo) so both repos stay canonical. Triggers: use the github-skill-manager to set up the new X skill, install the epub2md skill from GitHub, update the translation skill, remove skill Y, list installed GitHub skills, doctor the skill setup, why is the skill directory empty after clone."
license: MIT
metadata:
  version: '0.1.0'
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

This skill exposes five subcommands via `scripts/`. All scripts are idempotent, non-interactive, and return non-zero with a clear message on failure.

| Command | Purpose |
|---|---|
| `scripts/install.sh <repo> [name]` | Add a new skill as a submodule and pin it. |
| `scripts/update.sh <name\|--all>` | Fast-forward a skill to `origin/main` and bump the outer pointer. |
| `scripts/remove.sh <name>` | Deinit, remove, and delete the submodule cleanly. |
| `scripts/list.sh` | Print installed GitHub-backed skills and their pinned commits. |
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

## Updating a skill

Trigger: "update the `<name>` skill", "pull the latest for `<name>`", "bump `<name>`".

```bash
bash workspace/skills/github-skill-manager/scripts/update.sh <name>
```

Or for every installed skill:

```bash
bash workspace/skills/github-skill-manager/scripts/update.sh --all
```

The script:

- Enters the submodule, fast-forwards to `origin/main` via `git pull --ff-only`, and refuses to touch a submodule with uncommitted local changes.
- Returns to the workspace root, stages the new submodule pointer, and commits it as `Bump <name> skill to <short-sha>` when the SHA actually changed.
- Prints "already up to date" and exits 0 when the pointer did not move.

The agent should then push:

```bash
git push
```

## Editing a skill from inside the workspace

When the user asks the agent to edit `workspace/skills/<name>/` directly, follow the two-level commit rule:

1. Before editing, run `git pull --rebase` **inside** `workspace/skills/<name>`.
2. Make the edits.
3. Commit and push inside the submodule:
   ```bash
   cd workspace/skills/<name>
   git add -A
   git commit -m "<what changed and why>"
   git push origin main
   ```
4. Return to the workspace root and bump the pointer:
   ```bash
   cd -                                # back to workspace root
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
NAME                     PINNED       BRANCH   REMOTE
epub2md                  a9591ab      main     github.com:redasadki/epub2md
translation              3fa1c8d      main     github.com:redasadki/translation
github-skill-manager     b2e04af      main     github.com:redasadki/github-skill-manager
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

## References

- `references/submodule-guide.md` — the full submodule model, day-to-day workflow, and rationale.
- `references/troubleshooting.md` — recipes for the common failure modes.
- `examples/install-translation.md` — worked example, end to end.
