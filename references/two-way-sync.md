# Two-way sync

This document describes the branch model, the state machine, the retroactive migration procedure for skills that already have local commits, and the failure modes that `sync.sh` deliberately refuses to automate.

Read this after `SKILL.md` when you need to reason about a case the SKILL.md tables do not cover.

## Why two branches

A skill installed as a submodule has two consumers:

- The **upstream project** on GitHub, which everyone else clones. Its default branch (usually `main`) is where new features and fixes for the skill land.
- The **local host** (an OpenClaw workspace, in Reda's case), which cares about host-specific adjustments: a venv path, an environment variable, an adjusted trigger phrase. These changes are useful for this host, but not necessarily for anyone else, and merging them straight into `main` would spread host-specific noise across every clone of the skill.

Two-way sync keeps both flows healthy by splitting them onto two branches in the same repository:

- **Pull branch** (`ghsmPullBranch` in `.gitmodules`). Where upstream improvements arrive. Default `main`.
- **Push branch** (`ghsmPushBranch` in `.gitmodules`). Where this host's local commits go. Convention: `openclaw/<version>`, for example `openclaw/2026.7.x`.

Tying the push branch to a specific OpenClaw version is deliberate. A future `openclaw/2026.8.x` release can have its own parallel branch in the same repository without conflict, and the skill author can look at both to see what each host is doing.

## Configuration in .gitmodules

`sync.sh` reads three fields per submodule:

    [submodule "workspace/skills/translation"]
        path = workspace/skills/translation
        url = https://github.com/redasadki/translation.git
        branch = main
        ghsmPullBranch = main
        ghsmPushBranch = openclaw/2026.7.x

Fields:

- `branch` (standard). Used by `git submodule add -b`. Kept for compatibility with plain `git` workflows.
- `ghsmPullBranch` (extension). Preferred by `sync.sh` and `update.sh` when both are set. Lets you change the pull branch without also changing the submodule branch, which some git operations use.
- `ghsmPushBranch` (extension). Presence enables two-way sync for this skill. Absence means one-way (pull only).

Both extension fields are namespaced with `ghsm` so they do not collide with any git built-in or with another submodule manager. Git ignores unknown submodule fields, so a workspace that never touches this skill sees them as inert comments.

## State machine

For each skill, `sync.sh` computes:

    LOCAL_ONLY  = git rev-list --count origin/<pull_branch>..HEAD
    REMOTE_ONLY = git rev-list --count HEAD..origin/<pull_branch>

and picks exactly one of four actions:

| State | Condition | Action |
|---|---|---|
| In sync | LOCAL_ONLY == 0 and REMOTE_ONLY == 0 | No-op. Print pinned SHA. |
| Push only | LOCAL_ONLY > 0 and REMOTE_ONLY == 0 | `git push origin HEAD:<push_branch>`, then bump outer pointer. |
| Pull only | LOCAL_ONLY == 0 and REMOTE_ONLY > 0 | `git merge --ff-only origin/<pull_branch>`, then bump outer pointer. |
| Diverged | Both > 0 | Print counts and three options (merge, rebase, defer). Exit 1. |

Skills without a push branch configured cannot enter the Push only state safely. They downgrade to `update.sh` semantics: pull only, and any local commit is a hard error with a message pointing at `install.sh --reconfigure`.

## Diverged state: why sync.sh does not choose

When both counts are positive, the safe choice depends on facts that the tool cannot see:

- If the local commit is a trivial adjustment (an env var name, a doc typo), rebase onto the upstream is usually right.
- If the local commit is a substantive host-specific change (venv setup, a new dependency), a merge into an `openclaw/<version>` branch is usually right, and the upstream should never see it.
- If the two commit sets touch the same file, someone has to read them.

`sync.sh` refuses to pick and prints the three options. This is the same discipline as `git pull --ff-only`: it says no when the answer is ambiguous, and it prints the exact commands to move forward. See `references/design.md` for why non-destructive-by-default matters here.

## Retroactive migration

For a skill that was installed before v0.3.0 and has local commits that need to move to a push branch:

    # Push local work to the openclaw branch. The submodule's current HEAD
    # becomes the tip of this new branch.
    git -C workspace/skills/<name> push origin HEAD:openclaw/2026.7.x

    # Record the push branch (and pull branch, if not already set).
    bash workspace/skills/github-skill-manager/scripts/install.sh \
      --reconfigure \
      --pull-branch main \
      --push-branch openclaw/2026.7.x \
      <name>

    # Verify: sync.sh should now report "in sync".
    bash workspace/skills/github-skill-manager/scripts/sync.sh <name>

`install.sh --reconfigure` writes to `.gitmodules` and commits the change in the outer repo. It does not clone, does not delete anything, and does not push to any branch that already exists. Safe to run on any installed skill.

The `--reconfigure` path also tries, on a best-effort basis, to create the push branch on origin if it does not exist. Failures (permissions, network) are printed as warnings, not errors, so the metadata still lands and you can push the branch manually.

## When sync.sh is not the right tool

Do not use `sync.sh` when:

- The local edit was made in the wrong file, or the working tree is dirty from an interrupted operation. Commit or discard the change first.
- You want to change the pull branch or push branch. Use `install.sh --reconfigure`.
- The skill has diverged and you want the tool to pick a strategy. `sync.sh` prints options and stops. Run the merge or rebase yourself inside the submodule, then rerun `sync.sh`.
- The skill is not managed as a submodule. `sync.sh` only knows about submodules registered in `.gitmodules`.

## Interaction with update.sh

After v0.3.0, `update.sh` and `sync.sh` share the clobber guard. Both refuse to fast-forward over local commits. The difference is what they offer next:

- `update.sh` says "push local work by hand, or configure two-way sync".
- `sync.sh` picks the right action based on state, but only if a push branch is configured.

You can keep using `update.sh --all` on a mixed workspace where some skills have push branches and some do not. Skills without a push branch and without local commits work exactly as before. Skills with local commits raise a clear error and point at the fix.
