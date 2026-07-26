#!/usr/bin/env bash
# Cleanly remove an installed skill submodule.
#
# Usage:
#   remove.sh <name>
#
# Refuses to remove a submodule that has unpushed commits, unless the
# submodule's origin remote is unreachable (in which case the caller has
# already dealt with data loss risk).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_cmd git

[ $# -eq 1 ] || die "usage: remove.sh <name>"
name="$1"

root="$(workspace_root)"
cd "${root}"

rel_path="$(skill_rel_path "${root}" "${name}")"
is_submodule_path "${rel_path}" || die "'${name}' is not an installed submodule at '${rel_path}'."

# Refuse if the submodule has uncommitted or unpushed changes.
if [ -d "${root}/${rel_path}/.git" ] || [ -f "${root}/${rel_path}/.git" ]; then
  ( cd "${root}/${rel_path}" && git diff --quiet && git diff --cached --quiet ) \
    || die "submodule '${rel_path}' has uncommitted changes. commit or stash them, then rerun."
  # Check unpushed commits against origin/HEAD.
  local_head="$(cd "${root}/${rel_path}" && git rev-parse HEAD)"
  remote_head="$(cd "${root}/${rel_path}" && git ls-remote origin HEAD 2>/dev/null | awk '{print $1}')"
  if [ -n "${remote_head}" ] && [ "${local_head}" != "${remote_head}" ]; then
    # It might just be that origin has advanced past us; check ancestry.
    if ! ( cd "${root}/${rel_path}" && git merge-base --is-ancestor "${local_head}" "${remote_head}" 2>/dev/null ); then
      die "submodule '${rel_path}' has local commits not on origin. push them first, or use: --force (not implemented on purpose)."
    fi
  fi
fi

info "deinitializing ${rel_path}"
git submodule deinit -f -- "${rel_path}"

info "removing ${rel_path} from index and working tree"
git rm -f "${rel_path}"

# Clean up leftover git dir.
mod_dir="${root}/.git/modules/${rel_path}"
if [ -d "${mod_dir}" ]; then
  rm -rf "${mod_dir}"
fi

git commit -m "Remove ${name} skill"

info ""
info "removed: ${rel_path}"
info "next:    git push"
