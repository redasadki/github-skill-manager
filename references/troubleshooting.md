# Troubleshooting

> **Scope: submodule mode only.** This document applies to skills mounted as git submodules (normally third-party skills). Skills the operator owns may instead live as plain tracked folders in the workspace monorepo, synced with `git subtree` via the workspace's `scripts/skill-pull.sh` and `scripts/skill-push.sh`. For those, none of this document applies: use ordinary git. See the "Two modes" section of `SKILL.md`.

Recipes for the failure modes you will see most often. All commands assume you are at the workspace repo root, and that `<path>` is `workspace/skills/<name>`.

## Empty skill directory after cloning the workspace

Symptom: `ls workspace/skills/<name>` shows nothing, or only shows itself.

Fix:

```bash
git submodule update --init --recursive
```

To prevent it next time, set once:

```bash
git config --global submodule.recurse true
```

## `git status` shows "modified content" for a submodule

Symptom:

```
modified:   workspace/skills/<name> (modified content)
```

Meaning: the submodule has uncommitted local changes.

Fix:

```bash
cd workspace/skills/<name>
git status
# commit, then:
git push origin main
cd -
git add workspace/skills/<name>
git commit -m "Bump <name> skill to $(cd workspace/skills/<name> && git rev-parse --short HEAD)"
git push
```

## `git status` shows "new commits" for a submodule

Symptom:

```
modified:   workspace/skills/<name> (new commits)
```

Meaning: the submodule advanced past the outer pointer.

If you meant it:

```bash
git add workspace/skills/<name>
git commit -m "Bump <name> skill to $(cd workspace/skills/<name> && git rev-parse --short HEAD)"
git push
```

If you did not:

```bash
git submodule update -- workspace/skills/<name>
```

That reverts the submodule to the pinned SHA.

## Detached HEAD inside the submodule

Symptom, from inside the submodule:

```
HEAD detached at <sha>
```

Meaning: `git submodule update` checked out the pinned SHA rather than the branch. Expected right after update. Fix before editing:

```bash
cd workspace/skills/<name>
git checkout main
git pull --rebase
```

## Submodule remote unreachable

Symptom: `git ls-remote` fails or `install.sh` refuses with "cannot reach".

Fix path 1, auth:

```bash
gh auth status
gh auth login   # if not authenticated
```

Fix path 2, the repo moved. Edit `.gitmodules` to the new URL, then:

```bash
git submodule sync -- workspace/skills/<name>
git submodule update --init -- workspace/skills/<name>
```

## Wanted to change a skill's name

The submodule path is the skill's mount name. To rename:

```bash
bash workspace/skills/github-skill-manager/scripts/remove.sh <old-name>
bash workspace/skills/github-skill-manager/scripts/install.sh <owner>/<repo> <new-name>
```

The inner repo's name is untouched. Only its mount name in this workspace changes.

## Local commits inside a submodule that will not push

Symptom: `git push` inside the submodule is rejected as non-fast-forward.

Meaning: someone pushed to `main` since you last pulled.

Fix:

```bash
cd workspace/skills/<name>
git fetch origin
git pull --rebase origin main
# resolve any conflicts
git push origin main
```

Then bump the outer pointer.

## Accidentally deleted a submodule with `rm -rf`

`rm -rf` leaves stale state in three places: the outer tree gitlink, `.gitmodules`, and `.git/modules/workspace/skills/<name>/`. Recover:

```bash
git checkout HEAD -- workspace/skills/<name>
git submodule update --init -- workspace/skills/<name>
```

If the outer tree already committed the deletion, use `remove.sh` to finish cleaning up, then re-install.

## Doctor reports pointer drift but the drift is intentional

The outer pointer is behind the inner HEAD (the submodule advanced but you have not bumped yet). Two valid fixes:

Accept the new inner HEAD:

```bash
name=<name>
git add workspace/skills/${name}
git commit -m "Bump ${name} skill to $(cd workspace/skills/${name} && git rev-parse --short HEAD)"
git push
```

Reject the inner advance and go back to the pinned SHA:

```bash
git submodule update -- workspace/skills/<name>
```
