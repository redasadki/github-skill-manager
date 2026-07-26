# Example: install the translation skill

Assume the user says:

> Use the github-skill-manager to set up the new `translation` skill.

The agent should perform the following, end to end.

## 1. Resolve the repo

```bash
gh api user --jq .login
# -> redasadki
gh repo view redasadki/translation --json name,url,defaultBranchRef 2>/dev/null || true
```

If the repo exists, proceed. If it does not, ask the user for the correct owner or URL before doing anything else.

## 2. Sanity-check the workspace

```bash
git rev-parse --show-toplevel
git status --short
```

If the working tree has unrelated changes, ask the user whether to stash or commit them first. Do not proceed silently.

## 3. Install

```bash
bash workspace/skills/github-skill-manager/scripts/install.sh redasadki/translation
```

Expected output (illustrative):

```
checking remote: https://github.com/redasadki/translation.git
adding submodule at workspace/skills/translation tracking main
Cloning into '/.../workspace/skills/translation'...
validating skill layout
Valid skill: .
[main abc1234] Install translation skill from https://github.com/redasadki/translation.git at 3fa1c8d

installed: workspace/skills/translation -> https://github.com/redasadki/translation.git
pinned at: 3fa1c8d
next:      git push
```

## 4. Push

```bash
git push
```

## 5. Confirm

```bash
bash workspace/skills/github-skill-manager/scripts/list.sh
```

Expected:

```
NAME                     PINNED       BRANCH   REMOTE
epub2md                  a9591ab      main     github.com:redasadki/epub2md
github-skill-manager     b2e04af      main     github.com:redasadki/github-skill-manager
translation              3fa1c8d      main     github.com:redasadki/translation
```

## 6. Later, to pick up upstream changes

```bash
bash workspace/skills/github-skill-manager/scripts/update.sh translation
git push
```

Or for every installed skill in one shot:

```bash
bash workspace/skills/github-skill-manager/scripts/update.sh --all
git push
```
