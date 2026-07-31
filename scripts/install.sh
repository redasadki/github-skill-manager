#!/usr/bin/env bash
# Install a GitHub-hosted skill as a submodule under the skills directory,
# or reconfigure an already-installed skill for two-way sync.
#
# Usage:
#   install.sh [flags] <repo> [<name>]
#   install.sh --reconfigure [flags] <name>
#
# <repo> may be:
#   - owner/name              e.g. redasadki/translation
#   - https://github.com/...  full HTTPS URL
#   - git@github.com:...      full SSH URL
#   - file:///path/to/repo    for tests and self-hosted mirrors
#
# <name> defaults to the repo basename. Pass it explicitly only when the
# desired mount name differs from the repo name.
#
# Flags (all optional):
#   --pull-branch <branch>   Branch on origin to pull upstream improvements
#                            from. Written to .gitmodules as ghsmPullBranch.
#                            Also used as the initial submodule branch. If
#                            omitted, the remote's default branch is used.
#   --push-branch <branch>   Branch on origin where local commits should
#                            be pushed. Written to .gitmodules as
#                            ghsmPushBranch. If the branch does not yet
#                            exist on origin, it is created from the pull
#                            branch. Enables two-way sync via sync.sh.
#   --reconfigure            Do not clone. Just update .gitmodules for an
#                            already-installed skill. Requires <name> in
#                            the positional argument slot instead of <repo>.
#
# On a fresh install, this script:
#   - adds <skills-dir>/<name> as a submodule tracking the pull branch,
#   - writes ghsmPullBranch and ghsmPushBranch to .gitmodules when set,
#   - creates the push branch on origin from the pull branch when it does
#     not already exist,
#   - initializes the working tree,
#   - validates the skill with `agentskills validate` when available,
#   - commits the submodule pointer plus the .gitmodules changes.
#
# On --reconfigure, this script only writes .gitmodules and commits.
#
# You still need to `git push` the outer repo yourself.
#
# On partial failure of a fresh install, the script rolls back so a
# subsequent run can retry.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_cmd git

usage() {
  cat >&2 <<EOF
usage: install.sh [--pull-branch <b>] [--push-branch <b>] <repo> [<name>]
       install.sh --reconfigure [--pull-branch <b>] [--push-branch <b>] <name>
EOF
  exit 1
}

pull_branch_arg=""
push_branch_arg=""
reconfigure=0

# Parse flags. The remaining positional arguments become $1, $2 after the
# loop. bash's built-in flag parsing is deliberately explicit here so the
# error messages name the actual flag.
while [ $# -gt 0 ]; do
  case "$1" in
    --pull-branch)
      [ $# -ge 2 ] || die "--pull-branch requires a value."
      pull_branch_arg="$2"
      validate_branch_name "${pull_branch_arg}"
      shift 2
      ;;
    --push-branch)
      [ $# -ge 2 ] || die "--push-branch requires a value."
      push_branch_arg="$2"
      validate_branch_name "${push_branch_arg}"
      shift 2
      ;;
    --reconfigure)
      reconfigure=1
      shift
      ;;
    --help|-h)
      usage
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unknown flag: '$1'. see --help."
      ;;
    *)
      break
      ;;
  esac
done

[ $# -ge 1 ] || usage

root="$(workspace_root)"
cd "${root}"

# --- Reconfigure branch --------------------------------------------------
#
# In reconfigure mode, the positional argument is the skill name, not a
# repo reference. This lets already-installed skills opt into two-way
# sync without a fresh clone.
if [ "${reconfigure}" -eq 1 ]; then
  name="$1"
  validate_skill_name "${name}"
  rel_path="$(skill_rel_path "${root}" "${name}")"
  is_submodule_path "${rel_path}" || die "'${name}' is not an installed submodule at '${rel_path}'."

  changed=0
  if [ -n "${pull_branch_arg}" ]; then
    git config -f .gitmodules "submodule.${rel_path}.ghsmPullBranch" "${pull_branch_arg}"
    changed=1
    info "recorded ghsmPullBranch=${pull_branch_arg} for ${rel_path}"
  fi
  if [ -n "${push_branch_arg}" ]; then
    git config -f .gitmodules "submodule.${rel_path}.ghsmPushBranch" "${push_branch_arg}"
    changed=1
    info "recorded ghsmPushBranch=${push_branch_arg} for ${rel_path}"

    # Best-effort: create the push branch on origin if it does not exist,
    # so the very first sync.sh does not fail on a missing ref. We only
    # try when the submodule is initialized; when it is not, this can be
    # deferred until the user runs it.
    if [ -e "${root}/${rel_path}/.git" ]; then
      if ! ( cd "${root}/${rel_path}" && git fetch --quiet origin ); then
        info "warning: could not fetch origin for '${rel_path}'; skipping push-branch creation."
      elif ( cd "${root}/${rel_path}" && git rev-parse --verify --quiet "refs/remotes/origin/${push_branch_arg}" >/dev/null ); then
        info "push branch origin/${push_branch_arg} already exists"
      else
        # Seed the push branch from the current HEAD so it exists on origin.
        info "creating origin/${push_branch_arg} from local HEAD"
        if ! ( cd "${root}/${rel_path}" && git push --quiet origin "HEAD:refs/heads/${push_branch_arg}" ); then
          info "warning: could not create origin/${push_branch_arg}; create it by hand before the first sync."
        fi
      fi
    fi
  fi

  [ "${changed}" -eq 1 ] || die "reconfigure requires --pull-branch and/or --push-branch."

  git add .gitmodules
  if git diff --cached --quiet; then
    info "no .gitmodules changes to commit."
  else
    git commit -m "Configure ${name} skill for two-way sync"
  fi
  info ""
  info "reconfigured: ${rel_path}"
  info "next:         git push"
  exit 0
fi

# --- Fresh install -------------------------------------------------------

repo_input="$1"
name_override="${2:-}"

# Parse the repo reference. If normalize_repo_url fails inside the process
# substitution, mapfile still returns 0 but the array is empty; guard the
# array access so the real error message surfaces cleanly.
parsed_output="$(normalize_repo_url "${repo_input}")" || exit 1
mapfile -t parsed <<< "${parsed_output}"
[ "${#parsed[@]}" -ge 2 ] || die "internal error: could not parse '${repo_input}'."
repo_url="${parsed[0]}"
repo_base="${parsed[1]}"
name="${name_override:-${repo_base}}"

validate_skill_name "${name}"

rel_path="$(skill_rel_path "${root}" "${name}")"
abs_path="${root}/${rel_path}"

# If the target already exists, decide whether this is idempotent success
# or a conflict.
if [ -e "${abs_path}" ]; then
  if is_submodule_path "${rel_path}"; then
    existing_url="$(git config -f .gitmodules --get "submodule.${rel_path}.url" || true)"
    if [ "${existing_url}" = "${repo_url}" ]; then
      # Registered with the right URL. Make sure it is actually initialized.
      if [ ! -e "${abs_path}/.git" ]; then
        info "already registered but not initialized; initializing ${rel_path}"
        git submodule update --init --recursive -- "${rel_path}"
      fi
      pinned_sha="$(cd "${abs_path}" && git rev-parse --short HEAD)"
      info "already installed: ${rel_path} -> ${repo_url}"
      info "pinned at: ${pinned_sha}"
      if [ -n "${pull_branch_arg}" ] || [ -n "${push_branch_arg}" ]; then
        info "note: to change branch configuration, rerun with --reconfigure."
      fi
      exit 0
    fi
    die "path '${rel_path}' is a submodule but points at '${existing_url}', not '${repo_url}'."
  fi
  die "path '${rel_path}' already exists and is not a submodule. remove it or pick a different name."
fi

# Verify the remote is reachable.
info "checking remote: ${repo_url}"
if ! git ls-remote "${repo_url}" >/dev/null 2>&1; then
  die "cannot reach '${repo_url}'. check the URL, network, and gh auth (try: gh auth status)."
fi

# Determine the branch to track on submodule add. Explicit flag wins;
# otherwise fall back to the remote's default branch.
if [ -n "${pull_branch_arg}" ]; then
  track_branch="${pull_branch_arg}"
else
  track_branch="$(git ls-remote --symref "${repo_url}" HEAD 2>/dev/null \
    | awk '/^ref:/ {sub("refs/heads/","",$2); print $2; exit}')"
  track_branch="${track_branch:-main}"
fi

# Ensure the parent directory exists.
mkdir -p "$(dirname "${abs_path}")"

# Ensure the outer repo does not already have staged changes at that path.
ensure_clean_index_for "${rel_path}"

# Rollback hook. Runs on any error between `submodule add` and the final
# commit, undoing partial state so a retry starts clean.
rollback() {
  info "rolling back partial install of ${rel_path}"
  # Unstage any staged changes to .gitmodules and the path.
  git restore --staged .gitmodules "${rel_path}" 2>/dev/null || true
  # Remove the submodule section from .gitmodules if it landed there.
  git config -f .gitmodules --remove-section "submodule.${rel_path}" 2>/dev/null || true
  # Remove the submodule section from .git/config too.
  git config --remove-section "submodule.${rel_path}" 2>/dev/null || true
  # Drop the working tree.
  rm -rf "${abs_path}"
  # Drop the leftover git dir.
  rm -rf "${root}/.git/modules/${rel_path}"
  # Clean up .gitmodules if we made it empty.
  if [ -f .gitmodules ] && [ ! -s .gitmodules ]; then
    rm -f .gitmodules
    git rm --cached -f .gitmodules 2>/dev/null || true
  fi
}
trap 'rc=$?; if [ "${rc}" -ne 0 ]; then rollback; fi' EXIT

info "adding submodule at ${rel_path} tracking ${track_branch}"
git submodule add -b "${track_branch}" "${repo_url}" "${rel_path}"
git submodule update --init --recursive -- "${rel_path}"

# Record two-way sync configuration in .gitmodules when the flags were set.
# ghsmPullBranch is written whenever --pull-branch was passed, even though
# .gitmodules already has `branch = <track_branch>`; keeping the two keys
# separate lets us change the pull branch later without also changing the
# submodule branch, which some git operations use.
if [ -n "${pull_branch_arg}" ]; then
  git config -f .gitmodules "submodule.${rel_path}.ghsmPullBranch" "${pull_branch_arg}"
  info "recorded ghsmPullBranch=${pull_branch_arg}"
fi
if [ -n "${push_branch_arg}" ]; then
  git config -f .gitmodules "submodule.${rel_path}.ghsmPushBranch" "${push_branch_arg}"
  info "recorded ghsmPushBranch=${push_branch_arg}"

  # Create the push branch on origin if it does not exist yet. We push
  # HEAD, which at this point equals the pull branch tip.
  if ( cd "${abs_path}" && git rev-parse --verify --quiet "refs/remotes/origin/${push_branch_arg}" >/dev/null ); then
    info "push branch origin/${push_branch_arg} already exists"
  else
    info "creating origin/${push_branch_arg} from ${track_branch}"
    if ! ( cd "${abs_path}" && git push --quiet origin "HEAD:refs/heads/${push_branch_arg}" ); then
      info "warning: could not create origin/${push_branch_arg}. create it manually or check permissions."
    fi
  fi
fi

# Validate the skill with agentskills if the CLI is available.
# Absolute path so the validator can resolve the directory name.
if command -v agentskills >/dev/null 2>&1; then
  info "validating skill layout"
  agentskills validate "${abs_path}" || die "agentskills validation failed. see message above."
else
  info "note: 'agentskills' CLI not found on PATH; skipping skill validation."
fi

# SKILL.md presence warning (not an error: repo may be a bundle of skills).
if [ ! -f "${abs_path}/SKILL.md" ]; then
  info "warning: no SKILL.md at the root of ${rel_path}. it may still be a valid skill if the repo nests skills under subdirectories, but check its README."
fi

pinned_sha="$(cd "${abs_path}" && git rev-parse --short HEAD)"
git add .gitmodules "${rel_path}"
if git diff --cached --quiet; then
  info "nothing to commit; submodule was already registered."
else
  git commit -m "Install ${name} skill from ${repo_url} at ${pinned_sha}"
fi

# Success: clear the rollback trap so it does not fire on normal exit.
trap - EXIT

info ""
info "installed: ${rel_path} -> ${repo_url}"
info "pinned at: ${pinned_sha}"
if [ -n "${push_branch_arg}" ]; then
  info "sync mode: two-way (push: ${push_branch_arg}, pull: ${pull_branch_arg:-${track_branch}})"
fi
info "next:      git push"
