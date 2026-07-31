#!/usr/bin/env bash
# Diagnose common submodule and skill problems. Reports findings and prints
# concrete fix commands. Never applies fixes on its own.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_cmd git

root="$(workspace_root)"
cd "${root}"

problems=0

report() {
  problems=$((problems + 1))
  echo "PROBLEM: $1"
  [ -n "${2:-}" ] && echo "  fix: $2"
}

mapfile -t paths < <(submodule_names)
if [ "${#paths[@]}" -eq 0 ]; then
  echo "No submodules installed."
  exit 0
fi

checked=0
for p in "${paths[@]}"; do
  # Silently skip submodules that are not the manager's business. A path
  # can be a framework mount (`.superpowers/`) or something else entirely;
  # we only diagnose skill submodules living under the configured skills
  # directory.
  is_in_scope_submodule "${root}" "${p}" || continue

  # In-scope but malformed name: report it. This should never happen in
  # practice because is_in_scope_submodule already checks the shape, but
  # keeps the guard explicit for future maintainers.
  if ! validate_gitmodules_path "${root}" "${p}" 2>/dev/null; then
    report "malformed .gitmodules entry: '${p}'" "edit .gitmodules and fix or remove the invalid entry"
    continue
  fi
  checked=$((checked + 1))

  name="$(basename "${p}")"
  echo "checking ${p}"
  url="$(git config -f .gitmodules --get "submodule.${p}.url" || echo "")"
  [ -n "${url}" ] || report "no url recorded in .gitmodules for '${p}'" "re-add with: bash workspace/skills/github-skill-manager/scripts/install.sh <owner>/${name}"

  if [ ! -d "${root}/${p}" ] || [ -z "$(ls -A "${root}/${p}" 2>/dev/null || true)" ]; then
    report "submodule '${p}' is empty (not initialized)" "run: git submodule update --init --recursive -- ${p}"
    continue
  fi

  if [ ! -e "${root}/${p}/.git" ]; then
    report "submodule '${p}' has content but no .git link" "run: git submodule update --init --recursive -- ${p}"
    continue
  fi

  # Pointer vs HEAD.
  outer_ptr="$(git ls-tree HEAD -- "${p}" 2>/dev/null | awk '{print $3}')"
  inner_head="$(cd "${root}/${p}" && git rev-parse HEAD)"
  if [ -n "${outer_ptr}" ] && [ "${outer_ptr}" != "${inner_head}" ]; then
    report "pointer drift on '${p}': outer=${outer_ptr:0:7} inner=${inner_head:0:7}" \
      "if inner is intended, run: git add ${p} && git commit -m 'Bump ${name} to ${inner_head:0:7}' ; else: git submodule update -- ${p}"
  fi

  # Uncommitted changes.
  if ! ( cd "${root}/${p}" && git diff --quiet && git diff --cached --quiet ); then
    report "submodule '${p}' has uncommitted changes" "cd ${p} && git status ; commit and push, then bump the outer pointer"
  fi

  # Unpushed commits, plus two-way sync configuration checks.
  #
  # Order of preference for the upstream ref to compare against:
  #   1. tracked upstream (`@{u}`) when set,
  #   2. origin/<ghsmPullBranch>, origin/<branch>, in that order,
  #   3. origin/HEAD as a last resort.
  pull_branch="$(skill_pull_branch "${p}")"
  push_branch="$(skill_push_branch "${p}")"

  upstream=""
  if ( cd "${root}/${p}" && git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 ); then
    upstream="$(cd "${root}/${p}" && git rev-parse --abbrev-ref '@{u}')"
  elif [ -n "${pull_branch}" ]; then
    upstream="origin/${pull_branch}"
  elif ( cd "${root}/${p}" && git rev-parse --verify --quiet 'refs/remotes/origin/HEAD' >/dev/null ); then
    upstream="$(cd "${root}/${p}" && git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  fi

  if [ -n "${upstream}" ]; then
    ahead="$(count_local_only "${root}/${p}" "${upstream}")"
    if [ "${ahead}" -gt 0 ]; then
      if [ -n "${push_branch}" ]; then
        report "submodule '${p}' has ${ahead} unpushed commit(s) (two-way sync configured)" \
          "bash workspace/skills/github-skill-manager/scripts/sync.sh ${name}"
      else
        report "submodule '${p}' has ${ahead} unpushed commit(s) (no push branch configured)" \
          "push manually with 'cd ${p} && git push origin HEAD:${pull_branch:-main}', or configure two-way sync: bash workspace/skills/github-skill-manager/scripts/install.sh --reconfigure --push-branch <branch> ${name}"
      fi
    fi
  fi

  # Two-way sync misconfiguration: a push branch is set but the pull
  # branch is not, or the push and pull branches are identical (which
  # defeats the whole point of the split).
  if [ -n "${push_branch}" ] && [ -z "${pull_branch}" ]; then
    report "submodule '${p}' has ghsmPushBranch=${push_branch} but no ghsmPullBranch" \
      "bash workspace/skills/github-skill-manager/scripts/install.sh --reconfigure --pull-branch <branch> ${name}"
  fi
  if [ -n "${push_branch}" ] && [ "${push_branch}" = "${pull_branch}" ]; then
    report "submodule '${p}' has ghsmPushBranch=ghsmPullBranch=${push_branch} (defeats two-way sync)" \
      "set them to different branches, for example ghsmPullBranch=main and ghsmPushBranch=openclaw/2026.7.x"
  fi

  # SKILL.md presence.
  if [ ! -f "${root}/${p}/SKILL.md" ]; then
    report "submodule '${p}' has no SKILL.md at the root" "check the repo layout; some skills nest under a subdirectory"
  else
    if command -v agentskills >/dev/null 2>&1; then
      if ! agentskills validate "${root}/${p}" >/dev/null 2>&1; then
        report "skill '${name}' fails agentskills validation" "agentskills validate ${root}/${p}"
      fi
    fi
  fi

  # Remote reachability.
  if [ -n "${url}" ] && ! git ls-remote "${url}" >/dev/null 2>&1; then
    report "remote unreachable for '${p}' (${url})" "check network and gh auth (gh auth status). if the repo moved, edit .gitmodules and run: git submodule sync -- ${p}"
  fi
done

echo ""
if [ "${checked}" -eq 0 ]; then
  echo "No skill submodules installed under the configured skills directory."
  exit 0
fi
if [ "${problems}" -eq 0 ]; then
  echo "all skill submodules healthy (${checked} checked)."
else
  echo "found ${problems} problem(s) across ${checked} skill submodule(s)."
  exit 1
fi
