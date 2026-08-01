# Operator manual

This is the field manual for a human at a terminal. `SKILL.md` is the machine-facing contract; the `references/` files are deep-dives; this file is the one you read when something is not working and you need to fix it fast.

If you are a fresh operator: read [Setup](#setup) once, then jump to [Common tasks](#common-tasks). Come back to [Troubleshooting](#troubleshooting) when a command errors.

## Table of contents

- [Setup](#setup)
- [Two modes: plain folders and submodules](#two-modes-plain-folders-and-submodules)
- [Common tasks](#common-tasks)
  - [Install a new skill](#install-a-new-skill)
  - [Update a skill](#update-a-skill)
  - [Sync a skill both ways](#sync-a-skill-both-ways)
  - [Configure two-way sync on an existing skill](#configure-two-way-sync-on-an-existing-skill)
  - [Remove a skill](#remove-a-skill)
  - [List what is installed](#list-what-is-installed)
  - [Diagnose problems](#diagnose-problems)
  - [Edit a skill locally and push the change](#edit-a-skill-locally-and-push-the-change)
- [Terminology](#terminology)
- [Where things live](#where-things-live)
- [Troubleshooting](#troubleshooting)
- [Safety rules](#safety-rules)
- [How the scripts talk to each other](#how-the-scripts-talk-to-each-other)

## Setup

Two things must be true before any script runs cleanly.

1. **You are inside a git workspace that mounts skills as submodules.** All scripts discover the workspace root via `git rev-parse --show-toplevel` and expect skills to live under `skills/` (or whatever `GHSM_SKILLS_DIR` is set to). If you are not inside a git working tree, every script will die with `fatal: not a git repository`.

2. **`git` can push to GitHub over HTTPS without a password prompt.** GitHub does not accept passwords for git operations. Set up the [GitHub CLI](https://cli.github.com/) as your credential helper once per host:

   ```bash
   gh auth login --hostname github.com --git-protocol https --web
   gh auth setup-git
   ```

   Verify:

   ```bash
   git config --global --get-all credential.https://github.com.helper
   ```

   Expected: an empty line followed by a line ending in `gh auth git-credential`. Both lines are load-bearing — the empty one clears any previously-registered helper so `gh`'s helper is the only one asked.

If pushes are still prompting for a username, see [Troubleshooting → Push prompts for a username](#push-prompts-for-a-username).

## Two modes: plain folders and submodules

Since August 2026, a workspace can hold skills in two modes. Check the mode before running any command on a skill:

```bash
# Is it a submodule? (prints a .git path if yes)
ls skills/<name>/.git 2>/dev/null

# Is it a plain folder tracked by the workspace? (prints files if yes)
git ls-files skills/<name> | head -3
```

**Plain folder (monorepo mode).** The skill's files are ordinary tracked content of the workspace repo. This is the normal mode for skills the operator owns. Daily work is plain git: edit, `git add`, `git commit`, `git push`. If the skill also has its own GitHub repo (for development sessions in other tools, or public sharing), the workspace-level helpers sync the two:

```bash
bash scripts/skill-pull.sh <name>    # skill repo -> workspace folder
bash scripts/skill-push.sh <name>    # workspace folder -> skill repo
```

The name-to-URL map lives in `scripts/skill-mirrors.txt`. These helpers wrap `git subtree` and are part of the workspace, not of this skill.

**Submodule mode.** The skill is pinned in `.gitmodules` and has its own `.git`. This is the normal mode for third-party skills. Everything in the rest of this manual applies to this mode only.

**The one hard rule:** never convert a plain-folder skill into a submodule, and never run this skill's `install.sh` for a skill that already exists as a plain folder. The monorepo mode was chosen deliberately to remove the two-level commit workflow; reinstalling as a submodule brings the problem back.

## Common tasks

Every task in this section applies to SUBMODULE-mode skills and assumes you are at the workspace root. When in doubt, run `pwd`; you should be at the folder that contains `.gitmodules` and `skills/`. For plain-folder skills, use ordinary git as described in [Two modes](#two-modes-plain-folders-and-submodules).

### Install a new skill

**Simple case, one-way (pull only):**

```bash
bash skills/github-skill-manager/scripts/install.sh redasadki/epub2md
git push origin main
```

**Two-way (pull and push) from the start:**

```bash
bash skills/github-skill-manager/scripts/install.sh \
  --pull-branch main \
  --push-branch openclaw/2026.7.x \
  redasadki/epub2md
git push origin main
```

The `<repo>` argument accepts three forms: `owner/name`, a full HTTPS URL, or `file:///path/to/local/repo` for tests.

### Update a skill

**One skill:**

```bash
bash skills/github-skill-manager/scripts/update.sh <name>
git push origin main
```

**All installed skills:**

```bash
bash skills/github-skill-manager/scripts/update.sh --all
git push origin main
```

`update.sh` fast-forwards from the configured pull branch, refuses to touch a skill with uncommitted or unpushed local commits, and creates one `Bump <name> skill to <sha>` commit per skill that moved.

### Sync a skill both ways

Use `sync.sh` instead of `update.sh` when the skill has a push branch configured.

```bash
bash skills/github-skill-manager/scripts/sync.sh <name>
git push origin main
```

`sync.sh` picks one of four actions:

| State | What it does |
|---|---|
| In sync | Prints the pinned SHA, no changes. |
| Push only | Pushes local commits to the push branch, bumps the outer pointer. |
| Pull only | Fast-forwards from the pull branch, bumps the outer pointer. |
| Diverged | Prints commit counts and three options (merge, rebase, defer), exits 1. |

For the diverged case, resolve inside the submodule and rerun.

### Configure two-way sync on an existing skill

If you already installed a skill without two-way sync and now want to push local edits back to GitHub:

```bash
bash skills/github-skill-manager/scripts/install.sh \
  --reconfigure \
  --push-branch openclaw/2026.7.x \
  <name>
git push origin main
```

`--reconfigure` only edits `.gitmodules` and best-effort creates the push branch on origin. It does not clone, delete, or force-push.

Alternatively, add just a pull branch (useful if the skill was installed without any `branch = ...` line and `sync.sh` cannot resolve one):

```bash
bash skills/github-skill-manager/scripts/install.sh \
  --reconfigure \
  --pull-branch main \
  <name>
git push origin main
```

### Remove a skill

```bash
bash skills/github-skill-manager/scripts/remove.sh <name>
git push origin main
```

Deinits the submodule, removes it from `.gitmodules`, and deletes the working tree. Reversible only by reinstalling.

### List what is installed

```bash
bash skills/github-skill-manager/scripts/list.sh
```

Prints one row per skill with pinned SHA, sync mode (`pull:<branch>` or `pull:<a>/push:<b>` or `-` for unconfigured), and remote. Third-party submodules that are not skills (for example, `.superpowers/`) are silently skipped since v0.3.1.

### Diagnose problems

```bash
bash skills/github-skill-manager/scripts/doctor.sh
```

Exits 0 with `all skill submodules healthy (N checked)` when everything is fine. Otherwise prints one `PROBLEM: ...` line per issue, each followed by a concrete `fix:` line. Read every fix before deciding what to do; the doctor does not change any state on its own.

### Edit a skill locally and push the change

This is the most common workflow that trips up new operators, because it involves two commit levels. Do them in this order:

1. Make sure the skill is set up for two-way sync. If `list.sh` shows only `pull:main`, first run:

   ```bash
   bash skills/github-skill-manager/scripts/install.sh \
     --reconfigure \
     --push-branch openclaw/2026.7.x \
     <name>
   git push origin main
   ```

2. Sync down before editing, so you do not start on a stale base:

   ```bash
   bash skills/github-skill-manager/scripts/sync.sh <name>
   ```

3. Edit files under `skills/<name>/`. When done, commit **inside the submodule**:

   ```bash
   cd skills/<name>
   git add -A
   git commit -m "<short imperative sentence about what changed and why>"
   cd -
   ```

4. Sync back and push the outer pointer:

   ```bash
   bash skills/github-skill-manager/scripts/sync.sh <name>
   git push origin main
   ```

Never push the outer pointer without pushing the inner commit first. `sync.sh` enforces this order for you: it pushes to the push branch, then bumps the pointer. If step 3 fails to commit, do not proceed to step 4.

## Terminology

| Term | Meaning |
|---|---|
| Outer repo | The workspace repo. Holds `.gitmodules` and the pinned SHAs. |
| Submodule | One skill mounted at `skills/<name>/`. Has its own `.git`, its own remote, its own history. |
| Pinned SHA | The specific commit of the submodule that the outer repo points at. Advancing a submodule without bumping the pointer is called **pointer drift**. |
| Pull branch | The branch on origin from which the manager pulls upstream improvements. Recorded as `submodule.<path>.ghsmPullBranch` in `.gitmodules`. |
| Push branch | The branch on origin to which the manager pushes host-specific local commits. Recorded as `submodule.<path>.ghsmPushBranch`. |
| Two-way sync | The mode enabled when a push branch is configured. `sync.sh` handles both directions. |
| Out-of-scope submodule | Any submodule at a path outside the configured skills directory (for example, `.superpowers/` at the workspace root). The manager silently ignores these since v0.3.1. |

## Where things live

Inside the manager's own repo:

    github-skill-manager/
    ├── SKILL.md              # Machine-facing contract for the agent.
    ├── MANUAL.md             # This file. Human-facing operator manual.
    ├── README.md             # Landing page.
    ├── CHANGELOG.md          # Every release, one section per version.
    ├── LICENSE               # MIT.
    ├── ACTIONS.yaml          # GitHub Actions workflow for CI.
    ├── scripts/              # All the shell scripts.
    │   ├── _lib.sh           # Shared helpers. Sourced by every other script.
    │   ├── install.sh        # Add a new submodule.
    │   ├── update.sh         # Fast-forward one or all skills.
    │   ├── sync.sh           # Two-way sync one or all skills.
    │   ├── remove.sh         # Deinit and delete.
    │   ├── list.sh           # Print installed skills.
    │   └── doctor.sh         # Diagnose problems.
    ├── references/           # Deep-dive documents, loaded on demand.
    │   ├── design.md         # Security model and non-obvious design decisions.
    │   ├── submodule-guide.md
    │   ├── troubleshooting.md
    │   └── two-way-sync.md
    ├── examples/             # Worked examples with full paste-ready commands.
    │   ├── install-translation.md
    │   └── openclaw-branch.md
    └── tests/                # bats-core test suite.

Inside a workspace that uses the manager:

    workspace/
    ├── .git/
    ├── .gitmodules           # One [submodule "..."] block per installed skill.
    ├── skills/
    │   ├── github-skill-manager/     # The manager itself.
    │   ├── <skill-a>/                # Another skill.
    │   └── <skill-b>/                # And so on.
    └── ...                   # Whatever else the workspace contains.

## Troubleshooting

Recipes for the failures that actually happen at the keyboard.

### Push prompts for a username

You are missing a git credential helper, or the wrong one is registered.

```bash
gh auth status
git config --global --get-all credential.https://github.com.helper
```

- If `gh auth status` says you are not logged in, run `gh auth login --hostname github.com --git-protocol https --web` and pick "Login with a web browser".
- If `gh auth status` says you are logged in as the wrong account, run `gh auth logout --hostname github.com` first, then log in as the right account.
- If the credential helper output is empty or garbled, run:

  ```bash
  git config --global --unset-all credential.https://github.com.helper
  git config --global --remove-section credential.https://github.com 2>/dev/null
  gh auth setup-git
  ```

Retry the push.

### `update.sh` refuses because of local commits

```
error: submodule 'skills/<name>' has N local commit(s) not on origin/main.
       update.sh refuses to fast-forward when local work exists (clobber risk).
```

Two options:

- Push the local work by hand:

  ```bash
  cd skills/<name>
  git push origin HEAD:main
  cd -
  bash skills/github-skill-manager/scripts/update.sh <name>
  ```

- Or, if the local commits are host-specific and should not go on `main`, configure two-way sync:

  ```bash
  bash skills/github-skill-manager/scripts/install.sh \
    --reconfigure \
    --push-branch openclaw/2026.7.x \
    <name>
  bash skills/github-skill-manager/scripts/sync.sh <name>
  ```

### `sync.sh` says the skill is diverged

```
error: 'skills/<name>' has diverged from origin/main.
       local-only commits:  X
       remote-only commits: Y
       options (run inside skills/<name>):
         1. merge upstream:  git merge origin/main
         2. rebase onto it:  git rebase origin/main
         3. defer:           do nothing now, resolve later
```

The manager will not choose for you. Read both sides:

```bash
git -C skills/<name> log --oneline origin/main..HEAD    # your commits
git -C skills/<name> log --oneline HEAD..origin/main    # upstream commits
```

Pick merge or rebase based on what you see, run it inside `skills/<name>`, then rerun `sync.sh`.

### `doctor.sh` reports "no SKILL.md at the root"

Some third-party skill repositories are bundles that nest each skill under a subdirectory. Bundled repos will not have a `SKILL.md` at the root. This is a false alarm for bundle-style repos and a real problem for single-skill repos.

- If it is a bundle you use as a library (for example, `dembrandt/dembrandt-skills`): ignore the warning.
- If it is supposed to be a single-skill repo: check the repo layout on GitHub. Either the file is misnamed (must be exactly `SKILL.md`), or the manager cloned the wrong branch.

### `doctor.sh` reports "pointer drift"

The submodule has advanced but the outer pointer was not bumped.

```bash
bash skills/github-skill-manager/scripts/update.sh <name>
git push origin main
```

If `update.sh` refuses because the working tree is dirty, commit or stash inside the submodule first.

### `submodule add` says "already exists in the index"

You are trying to install a skill whose files are already tracked as plain files in the outer repo. Remove them from git first:

```bash
git rm -r skills/<name>
git commit -m "Remove plain <name> files before submodule install"
bash skills/github-skill-manager/scripts/install.sh <repo>
```

### `list.sh` or `doctor.sh` dies with "refusing .gitmodules path outside skills dir"

You are on manager v0.2.0, v0.3.0, or earlier, and your workspace has a non-skill submodule at the workspace root (for example, `.superpowers/`). Update to v0.3.1 or later:

```bash
bash skills/github-skill-manager/scripts/update.sh github-skill-manager
git push origin main
```

If `update.sh` itself fails for the same reason, work around it once:

```bash
git -C skills/github-skill-manager fetch origin
git -C skills/github-skill-manager merge --ff-only origin/main
git add skills/github-skill-manager
git commit -m "Bump github-skill-manager to $(git -C skills/github-skill-manager rev-parse --short HEAD)"
git push origin main
```

### Terminal keeps mangling multi-line paste

Symptoms: the second command of a pasted block appears as an argument of the first, and commands like `git config` end up with `skills/github-skill-manager/scripts/list.sh` inside them.

Fixes, in order of reliability:

- Paste one command per line, hitting Return between each.
- Use the terminal's "Edit → Paste and Match Style" (or equivalent) to strip formatting.
- In iTerm2 and VS Code, enable Bracketed Paste (usually the default) so pastes do not trigger shell autocomplete.

## Safety rules

The manager is deliberately non-destructive-by-default. Four rules keep it that way.

1. **`update.sh` never touches a skill with unpushed local commits.** It errors out and points at `sync.sh` or a manual push. This is the clobber guard added in v0.2.1.
2. **`sync.sh` never picks a merge strategy on a diverged skill.** It prints the counts and three options and exits. You choose.
3. **`install.sh --reconfigure` never clones, deletes, or force-pushes.** It only writes to `.gitmodules` and best-effort creates the push branch on origin if it does not exist.
4. **`remove.sh` deletes the working tree of the submodule but not the outer commit history.** You can re-add the same submodule any time; you cannot recover uncommitted work inside it.

If a script's output looks destructive and does not match a rule above, stop and read the error before doing anything.

## How the scripts talk to each other

All scripts source `scripts/_lib.sh`, which owns:

- Workspace-root discovery (`workspace_root`).
- Skill-name validation (`validate_skill_name`).
- Path validation (`validate_gitmodules_path`, `is_in_scope_submodule`).
- Submodule enumeration (`submodule_names`).
- Branch introspection (`skill_pull_branch`, `skill_push_branch`, `count_local_only`, `count_remote_only`).
- Repo URL parsing (`normalize_repo_url`).

Everything else lives in the individual scripts. When something breaks in an unusual way, `_lib.sh` is usually the fastest place to look, because most guards live there.

For the security model (why the guards exist, what they defend against), read [`references/design.md`](references/design.md). For the two-way sync branch model in more depth than the [Sync a skill both ways](#sync-a-skill-both-ways) section, read [`references/two-way-sync.md`](references/two-way-sync.md).
