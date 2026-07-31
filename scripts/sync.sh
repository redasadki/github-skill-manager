#!/usr/bin/env bash
# Two-way sync between a local skill submodule and its GitHub remote.
#
# Usage:
#   sync.sh <name>
#   sync.sh --all
#
# For each skill, sync.sh:
#   1. refuses if the working tree is dirty,
#   2. reads submodule.<path>.ghsmPullBranch (or `branch`, or origin/HEAD)
#      and submodule.<path>.ghsmPushBranch from .gitmodules,
#   3. fetches origin,
#   4. computes local-only and remote-only commit counts against the
#      pull branch,
#   5. picks one of four actions based on the counts:
#        - In sync:   no-op.
#        - Push only: push HEAD to the push branch, bump outer pointer.
#        - Pull only: fast-forward from the pull branch, bump outer pointer.
#        - Diverged:  print counts and three fix options, exit 1.
#
# A skill without a push branch configured behaves like update.sh: it
# can pull but never pushes, and diverged state is a hard error. Configure
# a push branch with install.sh --push-branch or by adding
# submodule.<path>.ghsmPushBranch = <branch> to .gitmodules by hand.
#
# In --all mode, per-skill failures are reported but do not stop the batch;
# the script exits non-zero if any skill failed.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_cmd git

[ $# -ge 1 ] || die "usage: sync.sh <name>|--all"

root="$(workspace_root)"
cd "${root}"

# Resolve the pull branch for one submodule. Prints on stdout, returns 1
# when nothing usable is configured or discoverable.
resolve_pull_branch() {
  local rel_path="$1"
  local b
  b="$(skill_pull_branch "${rel_path}")"
  if [ -n "${b}" ]; then
    echo "${b}"
    return 0
  fi
  b="$( cd "${root}/${rel_path}" \
        && git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
        | sed 's|^origin/||' )" || true
  if [ -n "${b}" ]; then
    echo "${b}"
    return 0
  fi
  return 1
}

# sync_one: full state machine for one submodule.
# Returns 0 on success (including no-op), 1 on per-skill failure.
# Never calls `die` so --all can keep going.
sync_one() {
  local rel_path="$1"
  local name
  name="$(basename "${rel_path}")"

  if [ ! -e "${root}/${rel_path}/.git" ]; then
    echo "error: submodule '${rel_path}' is not initialized. run: git submodule update --init -- '${rel_path}'" >&2
    return 1
  fi

  if ! ( cd "${root}/${rel_path}" && git diff --quiet && git diff --cached --quiet ); then
    echo "error: submodule '${rel_path}' has uncommitted changes. commit or stash them, then rerun." >&2
    return 1
  fi

  local pull_branch push_branch
  if ! pull_branch="$(resolve_pull_branch "${rel_path}")"; then
    echo "error: cannot resolve pull branch for '${rel_path}'. set submodule.${rel_path}.ghsmPullBranch or branch in .gitmodules." >&2
    return 1
  fi
  validate_branch_name "${pull_branch}" 2>/dev/null || {
    echo "error: refusing malformed pull branch '${pull_branch}' for '${rel_path}'." >&2
    return 1
  }

  push_branch="$(skill_push_branch "${rel_path}")"
  if [ -n "${push_branch}" ]; then
    validate_branch_name "${push_branch}" 2>/dev/null || {
      echo "error: refusing malformed push branch '${push_branch}' for '${rel_path}'." >&2
      return 1
    }
  fi

  info "syncing ${rel_path} (pull: ${pull_branch}${push_branch:+, push: ${push_branch}})"

  if ! ( cd "${root}/${rel_path}" && git fetch --tags --quiet origin ); then
    echo "error: cannot fetch origin for '${rel_path}'. check network and auth, then rerun." >&2
    return 1
  fi

  local pull_upstream="origin/${pull_branch}"
  if ! ( cd "${root}/${rel_path}" && git rev-parse --verify --quiet "${pull_upstream}" >/dev/null ); then
    echo "error: upstream ref '${pull_upstream}' does not exist inside '${rel_path}'." >&2
    return 1
  fi

  local local_only remote_only
  local_only="$(count_local_only "${root}/${rel_path}" "${pull_upstream}")"
  remote_only="$(count_remote_only "${root}/${rel_path}" "${pull_upstream}")"

  # State 1: in sync.
  if [ "${local_only}" -eq 0 ] && [ "${remote_only}" -eq 0 ]; then
    local sha
    sha="$( cd "${root}/${rel_path}" && git rev-parse --short HEAD )"
    info "  in sync (${sha})"
    return 0
  fi

  # State 2: pull only. Fast-forward from the pull branch.
  if [ "${local_only}" -eq 0 ] && [ "${remote_only}" -gt 0 ]; then
    local before after
    before="$( cd "${root}/${rel_path}" && git rev-parse HEAD )"
    if ! ( cd "${root}/${rel_path}" && git merge --ff-only "${pull_upstream}" >/dev/null ); then
      echo "error: fast-forward from ${pull_upstream} failed for '${rel_path}'. resolve manually." >&2
      return 1
    fi
    after="$( cd "${root}/${rel_path}" && git rev-parse HEAD )"
    git add "${rel_path}"
    git commit -m "Bump ${name} skill to ${after:0:7}"
    info "  pulled ${before:0:7} -> ${after:0:7} from origin/${pull_branch}"
    return 0
  fi

  # State 3: push only. Push HEAD to the push branch, then bump the outer
  # pointer so the workspace records the same SHA. This requires a push
  # branch to be configured; without one, the operation would be identical
  # to `update.sh` refusing to clobber local work.
  if [ "${local_only}" -gt 0 ] && [ "${remote_only}" -eq 0 ]; then
    if [ -z "${push_branch}" ]; then
      echo "error: '${rel_path}' has ${local_only} local commit(s) but no push branch configured." >&2
      echo "       configure one:" >&2
      echo "         git config -f .gitmodules submodule.${rel_path}.ghsmPushBranch <branch>" >&2
      echo "         git add .gitmodules && git commit -m 'Configure ${name} push branch'" >&2
      echo "       or push by hand: cd ${rel_path} && git push origin HEAD:<branch>" >&2
      return 1
    fi
    local sha
    sha="$( cd "${root}/${rel_path}" && git rev-parse HEAD )"
    info "  pushing ${local_only} local commit(s) to origin/${push_branch}"
    if ! ( cd "${root}/${rel_path}" && git push --quiet origin "HEAD:refs/heads/${push_branch}" ); then
      echo "error: push to origin/${push_branch} failed for '${rel_path}'. check permissions, then rerun." >&2
      return 1
    fi
    # Only bump the outer pointer if the outer SHA actually differs from
    # the inner HEAD. When the caller is running sync.sh right after a
    # local commit, they may already have bumped the pointer manually.
    local outer_ptr
    outer_ptr="$(git ls-tree HEAD -- "${rel_path}" 2>/dev/null | awk '{print $3}')"
    if [ "${outer_ptr}" != "${sha}" ]; then
      git add "${rel_path}"
      git commit -m "Bump ${name} skill to ${sha:0:7}"
      info "  pushed and bumped outer pointer to ${sha:0:7}"
    else
      info "  pushed (outer pointer already at ${sha:0:7})"
    fi
    return 0
  fi

  # State 4: diverged. Both counts are positive. sync.sh does not choose
  # a merge strategy for the user; it prints the state and the three
  # options and returns non-zero.
  echo "error: '${rel_path}' has diverged from origin/${pull_branch}." >&2
  echo "       local-only commits:  ${local_only}" >&2
  echo "       remote-only commits: ${remote_only}" >&2
  echo "       options (run inside ${rel_path}):" >&2
  echo "         1. merge upstream:  git merge origin/${pull_branch}" >&2
  echo "         2. rebase onto it:  git rebase origin/${pull_branch}" >&2
  echo "         3. defer:           do nothing now, resolve later" >&2
  if [ -n "${push_branch}" ]; then
    echo "       after resolving, rerun sync.sh ${name}." >&2
  else
    echo "       after resolving, rerun update.sh ${name}." >&2
  fi
  return 1
}

if [ "$1" = "--all" ]; then
  mapfile -t all_paths < <(submodule_names)
  [ "${#all_paths[@]}" -gt 0 ] || die "no submodules found in .gitmodules."

  # Silently skip out-of-scope submodules. See update.sh for the same
  # pattern and rationale.
  scoped_paths=()
  for p in "${all_paths[@]}"; do
    is_in_scope_submodule "${root}" "${p}" || continue
    scoped_paths+=("${p}")
  done
  [ "${#scoped_paths[@]}" -gt 0 ] || die "no skill submodules found under the configured skills directory."

  failed=()
  for p in "${scoped_paths[@]}"; do
    validate_gitmodules_path "${root}" "${p}"
    if ! sync_one "${p}"; then
      failed+=("${p}")
    fi
  done

  info ""
  if [ "${#failed[@]}" -gt 0 ]; then
    info "failed skills:"
    for f in "${failed[@]}"; do
      info "  - ${f}"
    done
    info "next: fix the failures above, then rerun sync.sh --all"
    exit 1
  fi
  info "next: git push"
else
  name="$1"
  validate_skill_name "${name}"
  rel_path="$(skill_rel_path "${root}" "${name}")"
  is_submodule_path "${rel_path}" || die "'${name}' is not an installed submodule at '${rel_path}'."
  sync_one "${rel_path}" || exit 1
  info ""
  info "next: git push"
fi
