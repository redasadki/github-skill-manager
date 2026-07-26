# Design notes

This document records the design decisions behind the scripts. It exists because several of the choices look like belt-and-suspenders paranoia, and future maintainers should not undo them without understanding what they defend against.

## The two-level commit rule

An outer workspace repo pins a specific commit of each skill repo via a submodule gitlink. Every change to a skill therefore requires two commits, and they must land in this order:

1. Commit and push inside the skill (inner) repo.
2. Commit and push the pointer bump in the outer workspace repo.

If the outer commit lands first, any teammate who clones the outer repo checks out a submodule SHA that does not exist on the inner remote. Every script that mutates the outer pointer ensures the inner state is committed first. `remove.sh` additionally requires the inner state to be pushed to origin.

## Trust boundary at `.gitmodules`

`.gitmodules` is a version-controlled file. Anyone with commit rights to the outer workspace repo can write arbitrary path entries into it. The scripts iterate those entries in `list.sh`, `update.sh --all`, and `doctor.sh`. If we let the raw path flow into shell commands, a crafted entry could pass an unexpected value to `git submodule`, `rm`, or a commit message.

`validate_gitmodules_path` in `_lib.sh` enforces three checks on every path read from `.gitmodules`:

1. Not absolute; no `..` segments.
2. Lives under the configured skills directory.
3. Final component matches the agentskills skill-name shape.

Any entry that fails these checks produces a clear diagnostic and is skipped. The scripts never `bash -c` or `eval` any user-controlled string.

## Fail closed on `remove.sh`

`remove.sh` deletes local commits along with the submodule directory. The safety check that guards against this is "does origin already have every commit local has?" — an ancestry check.

The original implementation checked ancestry only when both local and remote HEADs were available. If `ls-remote` returned nothing for any reason (empty result, network hiccup, expired credential), the check was silently skipped and the removal proceeded. That is the single most dangerous failure mode this codebase can have.

The fix is threefold:

1. Fetch from origin explicitly before the check; refuse to proceed if the fetch fails.
2. Resolve the upstream ref against a specific branch, in this order of preference: the local branch's `@{u}` upstream, the branch recorded in `.gitmodules`, then `origin/HEAD`. Bare mirrors do not always have `HEAD` set, so relying on it alone breaks self-hosted setups.
3. Refuse to proceed if the upstream ref cannot be resolved. No silent skip is ever acceptable in this path.

## The `file://` transport

`normalize_repo_url` accepts `file:///absolute/path/to/repo.git` even though production users clone from `https://github.com`. This is not a security relaxation. It exists for two legitimate uses:

1. The test suite uses local bare repos as fake "GitHub" remotes so tests run offline.
2. Users mirroring GitHub to a self-hosted bare clone for air-gapped machines can point installs at the mirror.

Modern git (>= 2.38) blocks the `file://` transport for submodules by default as a mitigation for CVE-2022-39253. The scripts do not weaken this default. The test suite opts back in via `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_0=protocol.file.allow` / `GIT_CONFIG_VALUE_0=always`, scoped to the test process only. Users who need this in production must set it themselves and understand the risk.

## Idempotency vs. self-healing

`install.sh` runs the same happy-path steps twice with equivalent outcomes:

- The first run adds the submodule, initializes the working tree, validates, and commits the pointer.
- The second run notices the submodule is already registered pointing at the same URL. If the working tree is populated, it exits 0 quietly. If the working tree is empty (partial checkout, aborted init), it re-initializes before exiting 0.

This means an interrupted install can be recovered simply by rerunning `install.sh` with the same arguments. No manual `git submodule update --init` required.

## Rollback in `install.sh`

`git submodule add` writes to `.gitmodules` and `.git/config` before it clones. If the clone fails (auth loss, disk full, submodule init lock), the outer repo is left with a half-registered submodule that the next `install.sh` invocation cannot deal with cleanly.

The `rollback` trap in `install.sh` undoes every side effect between `submodule add` and the final commit: unstages `.gitmodules`, removes the section from `.gitmodules` and `.git/config`, deletes the working tree, and deletes `.git/modules/<path>`. If `.gitmodules` becomes empty as a result, it is deleted and un-staged. A retry starts from a clean state.

## Non-negotiable rules the scripts enforce

- Never edit a submodule directory without `git pull --rebase` first inside it.
- Never commit a pointer bump in the outer repo without pushing the inner commit first.
- Never `rm -rf` a submodule as a shortcut. Use `remove.sh`.
- Never nest a plain (non-submodule) clone inside the workspace repo.

These rules are documented in `SKILL.md` so the agent reads them into context whenever the skill is invoked. They are also enforced structurally in the scripts wherever possible (for example, `remove.sh` refuses to proceed with unpushed inner commits).
