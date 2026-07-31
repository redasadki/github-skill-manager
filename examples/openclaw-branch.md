# Worked example: two-way sync with an OpenClaw branch

Scenario: I run OpenClaw 2026.7.x on Doha, and I want to install `redasadki/translation` so:

- upstream improvements to the translation skill land on `main` and I can pull them into my workspace,
- my host-specific changes (a venv path, an added trigger phrase) live on `openclaw/2026.7.x` on the same repo, and never touch `main`,
- I never clobber my local work with an update, and I never leak host-specific noise into `main`.

Assume the outer workspace repo is clean and I am at its root.

## 1. Install with two-way sync from the start

```bash
bash workspace/skills/github-skill-manager/scripts/install.sh \
  --pull-branch main \
  --push-branch openclaw/2026.7.x \
  redasadki/translation
```

What happens, in order:

1. Clone `https://github.com/redasadki/translation.git` at `workspace/skills/translation`, tracking `main`.
2. Write two extension fields to `.gitmodules`:
   ```
   submodule.workspace/skills/translation.ghsmPullBranch = main
   submodule.workspace/skills/translation.ghsmPushBranch = openclaw/2026.7.x
   ```
3. Create `origin/openclaw/2026.7.x` on GitHub from the current `main` tip. This is the first push and gets the branch to exist so the first `sync.sh` does not fail on a missing ref.
4. Validate with `agentskills validate` (if the CLI is on PATH).
5. Commit the outer pointer plus `.gitmodules` in the workspace repo.

Confirm:

```bash
bash workspace/skills/github-skill-manager/scripts/list.sh
```

```
NAME                     PINNED       SYNC                              REMOTE
translation              3fa1c8d      pull:main/push:openclaw/2026.7.x  github.com:redasadki/translation
```

## 2. Make a host-specific edit

```bash
cd workspace/skills/translation
# edit SKILL.md or scripts as needed for the openclaw host
git add -A
git commit -m "Adjust translation skill for openclaw 2026.7.x venv"
cd -
```

At this point the submodule has one commit that origin does not know about.

## 3. Sync back

```bash
bash workspace/skills/github-skill-manager/scripts/sync.sh translation
```

What happens:

1. Fetch origin.
2. Count local-only and remote-only commits against `origin/main`.
3. See `local-only = 1, remote-only = 0`. State: Push only.
4. Push `HEAD` to `openclaw/2026.7.x`.
5. Bump the outer pointer in the workspace repo.

```bash
git push
```

Now the openclaw branch on GitHub has my commit. `main` is untouched.

## 4. Later, pull an upstream improvement

Someone lands a fix on `main` upstream. From the workspace root:

```bash
bash workspace/skills/github-skill-manager/scripts/sync.sh translation
```

State this time: `local-only = 1, remote-only = 1`. That is Diverged. `sync.sh` prints:

```
error: 'workspace/skills/translation' has diverged from origin/main.
       local-only commits:  1
       remote-only commits: 1
       options (run inside workspace/skills/translation):
         1. merge upstream:  git merge origin/main
         2. rebase onto it:  git rebase origin/main
         3. defer:           do nothing now, resolve later
       after resolving, rerun sync.sh translation.
```

I choose merge because I want a clear record of when `openclaw/2026.7.x` absorbed the upstream fix:

```bash
cd workspace/skills/translation
git merge origin/main
cd -
bash workspace/skills/github-skill-manager/scripts/sync.sh translation
git push
```

State after the merge: `local-only = 2 (my host commit + the merge commit), remote-only = 0`. That is Push only. `sync.sh` pushes the two commits to `openclaw/2026.7.x` and bumps the pointer.

## 5. Migrate an already-improved skill

Say the `translation` skill was already installed under v0.2.0, and it already has one host-specific commit that never got pushed. The commit is at risk (v0.2.0 clobber gap). To migrate without losing anything:

```bash
# Push the local work to a new openclaw branch on origin.
git -C workspace/skills/translation push origin HEAD:openclaw/2026.7.x

# Record the branch metadata and commit .gitmodules.
bash workspace/skills/github-skill-manager/scripts/install.sh \
  --reconfigure \
  --pull-branch main \
  --push-branch openclaw/2026.7.x \
  translation

# Confirm.
bash workspace/skills/github-skill-manager/scripts/sync.sh translation
# Expected output: "in sync (<sha>)"
```

`install.sh --reconfigure` never clones, deletes, or force-pushes. Safe to run on any installed skill.

## 6. Undo, if you change your mind

To go back to one-way (pull only), remove the push branch metadata:

```bash
git config -f .gitmodules --unset submodule.workspace/skills/translation.ghsmPushBranch
git add .gitmodules
git commit -m "Disable two-way sync for translation"
```

The `openclaw/2026.7.x` branch on origin is untouched. You can prune it later with `git push origin :openclaw/2026.7.x` if you no longer need it.
