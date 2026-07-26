# github-skill-manager

An Agent Skill that installs, updates, removes, lists, and diagnoses other Agent Skills hosted on GitHub, mounted as git submodules under `workspace/skills/`.

Use it when the user says any of:

- Install / add / set up the `<name>` skill.
- Update / bump / pull the latest for `<name>`.
- Remove / uninstall `<name>`.
- List installed skills.
- Doctor / diagnose the skill setup.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/install.sh <repo> [name]` | Add a new skill as a submodule and pin it. |
| `scripts/update.sh <name\|--all>` | Fast-forward a skill and bump the outer pointer. |
| `scripts/remove.sh <name>` | Deinit and remove the submodule cleanly. |
| `scripts/list.sh` | Print installed submodules with pinned SHA and remote. |
| `scripts/doctor.sh` | Diagnose common problems, print concrete fix commands. |

All scripts are idempotent, non-interactive, and refuse to touch a submodule with uncommitted work unless the caller has cleared it first.

## Read next

- `SKILL.md` for the full agent-facing contract.
- `references/submodule-guide.md` for the underlying model.
- `references/troubleshooting.md` for the common failure modes.
- `examples/install-translation.md` for a worked example.

## Install this skill itself

Because this skill manages skills, it is convenient to install it first, by hand, so it can then manage everything else:

```bash
git submodule add https://github.com/redasadki/github-skill-manager.git workspace/skills/github-skill-manager
git commit -m "Add github-skill-manager skill as submodule"
git push
```

After this one-time setup, use `scripts/install.sh` for every subsequent skill.
