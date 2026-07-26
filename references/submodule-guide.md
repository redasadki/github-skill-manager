# Skills as submodules: the model

This is the full guide to using GitHub-hosted Agent Skills inside a workspace repo that is itself under version control.

## The problem

You have an outer repo (the workspace) that tracks everything you work in. You want an inner directory (`workspace/skills/<name>/`) whose canonical source is a different repo (`github.com/<owner>/<name>`). Git does not let a repo contain another repo as a plain directory. It gives you exactly three ways to handle this, and only one of them gives true two-way sync.

## The three options

| Approach | Two-way sync | Outer repo tracks skill history | Failure mode |
|---|---|---|---|
| **Submodule** (recommended) | Yes. `cd` in, `git pull` / `git push` as normal. | Outer repo pins a specific commit of the skill repo. Bumping the pointer is one commit in the outer repo. | You must remember to bump the pointer when the inner repo advances. Well tooled. |
| Nested clone with `.gitignore` | Yes for the inner repo, but the outer repo cannot see the skill at all. | No. The skill is invisible to the workspace repo. | If you ever remove the `.gitignore` line, git swallows the nested `.git/` and you get a mess. Backups of the workspace repo do not include the skill. |
| Plain clone, no `.gitignore` | Broken. Git adds a gitlink entry with no submodule config, so nobody who clones the workspace can get the skill. | Half-tracked, unusable. | Silent breakage. Everyone else's checkout has an empty `<name>/` directory. |

`git subtree` is a fourth theoretical option, but it merges the inner repo's history into the outer repo. That is exactly what you do not want when the inner repo has its own release cycle, tags, and CI. Do not use subtree for this.

## What a submodule actually is

Adding a submodule creates two things in the outer repo:

1. `.gitmodules` at the outer repo root, recording the path and URL:
   ```
   [submodule "workspace/skills/epub2md"]
       path = workspace/skills/epub2md
       url = https://github.com/redasadki/epub2md.git
       branch = main
   ```
2. A **gitlink** at that path in the outer repo's tree. The gitlink stores the exact SHA of the inner repo the outer commit points at. `git log` and `git show` display it as a special "commit" line.

The submodule itself is a regular clone of the inner repo, living at `workspace/skills/<name>/`. Its `.git` is a small file that references `<outer-repo>/.git/modules/workspace/skills/<name>/`, which is where the real git directory lives. This lets you delete and re-init the submodule without losing history.

## Setup on the workspace repo

Once per workspace, inside the outer repo:

```bash
git config --global submodule.recurse true
```

This makes every future `git pull`, `git checkout`, and `git clone` also update submodules. It is a one-time global setting per machine.

## Day-to-day workflow

### Install a new skill

Use `install.sh`. It:

- validates the repo name shape,
- fetches the remote HEAD ref to discover the default branch,
- runs `git submodule add -b <branch> <url> <path>`,
- initializes the working tree,
- validates the skill with `agentskills validate` if available,
- commits the pointer as `Install <name> skill from <url> at <sha>`.

Then push the outer repo yourself.

### Edit a skill from inside the workspace

Two-level commit rule:

```bash
cd workspace/skills/<name>
git pull --rebase                        # sync inner first
# ... edit ...
git add -A
git commit -m "<what changed and why>"
git push origin main                     # inner push FIRST

cd -                                     # back to outer root
git add workspace/skills/<name>
git commit -m "Bump <name> skill to $(cd workspace/skills/<name> && git rev-parse --short HEAD)"
git push                                 # outer push
```

The order matters. If the outer pointer bump lands on GitHub before the inner commit, any teammate who clones the outer repo will try to check out a SHA that does not exist on the inner remote.

### Update a skill to latest

Use `update.sh <name>` or `update.sh --all`. It fast-forwards to `origin/main` and only bumps the pointer when the SHA actually changed.

### Remove a skill

Use `remove.sh <name>`. It deinits the submodule, removes the entry from `.gitmodules`, deletes the leftover git dir under `.git/modules/`, and commits the removal. Never `rm -rf` the directory.

## First-time clone recovery

If you clone the outer workspace repo on a new machine and the skill directories look empty, you missed the recursive init.

```bash
git submodule update --init --recursive
```

If you use the global `submodule.recurse = true` setting above, you can avoid this by cloning with:

```bash
git clone --recurse-submodules <workspace-url>
```

## Why not a symlink or an env var

Symlinks work on macOS and Linux but not reliably on Windows or inside some sandboxes. They also confuse `git status` in the outer repo, because git either follows the symlink and treats it as a plain directory (bad, defeats the point) or stores the symlink and you now have a broken link on any machine that does not have the target. Environment variables that point OpenClaw at an out-of-tree skill work but break reproducibility: the workspace snapshot at any point in time no longer describes which skill version it used.

Submodules are the correct answer because they give:

- reproducibility: outer commit + submodule pointer uniquely identifies the skill code,
- independence: the skill has its own tags, CI, and release cadence,
- discoverability: `git submodule status` lists every skill and its pinned SHA,
- portability: cloning the outer repo with `--recurse-submodules` restores every skill.

## Common pitfalls

- **"Modified content" in `git status`.** The submodule has uncommitted local changes. Enter it, commit and push, then bump the outer pointer.
- **"New commits" in `git status`.** The submodule advanced but the outer pointer did not. Either bump the pointer (`git add <path> && git commit`) or reset the submodule (`git submodule update -- <path>`).
- **Empty skill directory after clone.** Recursive init was missed. Run `git submodule update --init --recursive`.
- **Detached HEAD inside a submodule after `git submodule update`.** This is expected. `git submodule update` checks out the pinned SHA. Before editing, `cd` in and `git checkout <branch>` (usually `main`) to reattach.
