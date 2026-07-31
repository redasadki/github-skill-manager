#!/usr/bin/env bash
# Fast-forward one or all installed skills to their upstream branch and bump
# the outer pointer.
#
# Usage:
#   update.sh <name>
#   update.sh --all
#
# Refuses to touch submodules with:
#   - uncommitted local changes, or
#   - local commits that do not exist on the configured upstream branch.
#
# The second guard closes the v0.2.0 clobber gap: previously, local commits
# that happened to be an ancestor of origin/main slipped through and only
# broke on the next upstream push. In two-way sync mode, use sync.sh instead,
# which pushes local work to the configured push branch and then updates.
#
# In --all mode, per-skill failures are reported but do not stop the batch;
# the script exits non-zero if any skill failed.
#
# You still need to `git push` the outer repo yourself when this returns.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_cmd git

[ $# -ge 1 ] || die "usage: update.sh <name>|--all"

root="$(workspace_root)"
cd "${root}"

# Resolve the upstream branch to update from. Order of preference:
#   1. ghsmPullBranch in .gitmodules
#   2. branch in .gitmodules
#   3. the default branch reported by the remote (via origin/HEAD)
#
# Prints the branch name on stdout. Never dies; returns 1 if it cannot be
# resolved so the caller can produce a per-skill error.
resolve_pull_branch() {
  local rel_path="$1"
  local b
  b="$(skill_pull_branch "${rel_path}")"
  if [ -n "${b}" ]; then
    echo "${b}"
    return 0
  fi
  # Fall back to origin/HEAD inside the submodule.
  b="$( cd "${root}/${rel_path}" \
        && git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's|^origin/||' )" || true
  if [ -n "${b}" ]; then
    echo "${b}"
    return 0
  fi
  return 1
}

# Perform the update for one submodule. Returns 0 on success or no-op, 1 on
# per-skill failure. Never calls `die` so callers can iterate.
update_one() {
  local rel_path="$1"
  local name
  name="$(basename "${rel_path}")"

  if [ ! -e "${root}/${rel_path}/.git" ]; then
    echo "error: submodule '${rel_path}' is not initialized. run: git submodule update --init -- '${rel_path}'" >&2
    return 1
  fi

  if ! ( cd "${root}/${rel_path}" && git diff --quiet && git diff --cached --quiet ); then
    echo "error: submodule '${rel_path}' has uncommitted changes. commit or stash them first, then rerun." >&2
    return 1
  fi

  local pull_branch
  if ! pull_branch="$(resolve_pull_branch "${rel_path}")"; then
    echo "error: cannot resolve upstream branch for '${rel_path}'. set submodule.${rel_path}.branch in .gitmodules or make sure origin has a default branch." >&2
    return 1
  fi
  validate_branch_name "${pull_branch}" 2>/dev/null || {
    echo "error: refusing malformed pull branch '${pull_branch}' for '${rel_path}'." >&2
    return 1
  }

  info "updating ${rel_path} from origin/${pull_branch}"
  if ! ( cd "${root}/${rel_path}" && git fetch --tags --quiet origin ); then
    echo "error: cannot fetch origin for '${rel_path}'. check network and auth, then rerun." >&2
    return 1
  fi

  local upstream="origin/${pull_branch}"
  if ! ( cd "${root}/${rel_path}" && git rev-parse --verify --quiet "${upstream}" >/dev/null ); then
    echo "error: upstream ref '${upstream}' does not exist inside '${rel_path}'." >&2
    return 1
  fi

  # Clobber-prevention guard. Any local commit that is not reachable from
  # the upstream branch is at risk of being lost, silently in v0.2.0 or
  # noisily on the next upstream advance.
  local local_only remote_only
  local_only="$(count_local_only "${root}/${rel_path}" "${upstream}")"
  remote_only="$(count_remote_only "${root}/${rel_path}" "${upstream}")"

  local push_branch
  push_branch="$(skill_push_branch "${rel_path}")"

  if [ "${local_only}" -gt 0 ]; then
    if [ -n "${push_branch}" ]; then
      echo "error: submodule '${rel_path}' has ${local_only} local commit(s) not on origin/${pull_branch}." >&2
      echo "       two-way sync is configured (push branch: ${push_branch})." >&2
      echo "       fix: bash workspace/skills/github-skill-manager/scripts/sync.sh ${name}" >&2
    else
      echo "error: submodule '${rel_path}' has ${local_only} local commit(s) not on origin/${pull_branch}." >&2
      echo "       update.sh refuses to fast-forward when local work exists (clobber risk)." >&2
      echo "       options: push local work with 'cd ${rel_path} && git push', OR configure two-way sync:" >&2
      echo "       bash workspace/skills/github-skill-manager/scripts/install.sh --push-branch <branch> --reconfigure ${name}" >&2
    fi
    return 1
  fi

  local before after
  before="$( cd "${root}/${rel_path}" && git rev-parse HEAD )"

  if [ "${remote_only}" -eq 0 ]; then
    info "  already up to date (${before:0:7})"
    return 0
  fi

  if ! ( cd "${root}/${rel_path}" && git merge --ff-only "${upstream}" >/dev/null ); then
    echo "error: fast-forward failed for '${rel_path}'. resolve manually inside the submodule." >&2
    return 1
  fi

  after="$( cd "${root}/${rel_path}" && git rev-parse HEAD )"

  git add "${rel_path}"
  git commit -m "Bump ${name} skill to ${after:0:7}"
  info "  bumped ${before:0:7} -> ${after:0:7}"
  return 0
}

if [ "$1" = "--all" ]; then
  mapfile -t all_paths < <(submodule_names)
  [ "${#all_paths[@]}" -gt 0 ] || die "no submodules found in .gitmodules."

  # Filter down to entries the manager owns. A workspace can freely host
  # non-skill submodules (a framework mount, a fork of a shared repo) at
  # paths outside the skills directory; update.sh --all silently ignores
  # them.
  scoped_paths=()
  for p in "${all_paths[@]}"; do
    is_in_scope_submodule "${root}" "${p}" || continue
    scoped_paths+=("${p}")
  done
  [ "${#scoped_paths[@]}" -gt 0 ] || die "no skill submodules found under the configured skills directory."

  failed=()
  for p in "${scoped_paths[@]}"; do
    validate_gitmodules_path "${root}" "${p}"
    if ! update_one "${p}"; then
      failed+=("${p}")
    fi
  done

  info ""
  if [ "${#failed[@]}" -gt 0 ]; then
    info "failed skills:"
    for f in "${failed[@]}"; do
      info "  - ${f}"
    done
    info "next: fix the failures above, then rerun update.sh --all"
    exit 1
  fi
  info "next: git push"
else
  name="$1"
  validate_skill_name "${name}"
  rel_path="$(skill_rel_path "${root}" "${name}")"
  is_submodule_path "${rel_path}" || die "'${name}' is not an installed submodule at '${rel_path}'."
  update_one "${rel_path}" || exit 1
  info ""
  info "next: git push"
fi
