#!/usr/bin/env bash
# Install a GitHub-hosted skill as a submodule under the skills directory.
#
# Usage:
#   install.sh <repo> [<name>]
#
# <repo> may be:
#   - owner/name              e.g. redasadki/translation
#   - https://github.com/...  full HTTPS URL
#   - git@github.com:...      full SSH URL
#
# <name> defaults to the repo basename. Pass it explicitly only when the
# desired mount name differs from the repo name.
#
# On success, this script has:
#   - added <skills-dir>/<name> as a submodule,
#   - recorded it in .gitmodules,
#   - initialized the working tree,
#   - validated the skill with `agentskills validate` when available,
#   - committed the submodule pointer in the outer workspace repo.
#
# You still need to `git push` the outer repo yourself.
#
# On partial failure, the script rolls back so a subsequent run can retry.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_cmd git

[ $# -ge 1 ] || die "usage: install.sh <repo> [<name>]"
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

root="$(workspace_root)"
cd "${root}"

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

# Determine the default branch (fall back to main).
default_branch="$(git ls-remote --symref "${repo_url}" HEAD 2>/dev/null \
  | awk '/^ref:/ {sub("refs/heads/","",$2); print $2; exit}')"
default_branch="${default_branch:-main}"

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

info "adding submodule at ${rel_path} tracking ${default_branch}"
git submodule add -b "${default_branch}" "${repo_url}" "${rel_path}"
git submodule update --init --recursive -- "${rel_path}"

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
info "next:      git push"
