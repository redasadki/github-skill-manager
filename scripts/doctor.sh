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

for p in "${paths[@]}"; do
  # Validate the path before letting it flow into any command below.
  if ! validate_gitmodules_path "${root}" "${p}" 2>/dev/null; then
    report "malformed .gitmodules entry: '${p}'" "edit .gitmodules and fix or remove the invalid entry"
    continue
  fi

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

  # Unpushed commits (only when an upstream is configured).
  if ( cd "${root}/${p}" && git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 ); then
    ahead="$(cd "${root}/${p}" && git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)"
    if [ "${ahead}" -gt 0 ]; then
      report "submodule '${p}' has ${ahead} unpushed commit(s)" "cd ${p} && git push"
    fi
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
if [ "${problems}" -eq 0 ]; then
  echo "all submodules healthy."
else
  echo "found ${problems} problem(s)."
  exit 1
fi
