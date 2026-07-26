#!/usr/bin/env bash
# List installed skill submodules with their pinned SHA, branch, and remote.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_cmd git

root="$(workspace_root)"
cd "${root}"

mapfile -t paths < <(submodule_names)
if [ "${#paths[@]}" -eq 0 ]; then
  echo "No submodules installed."
  exit 0
fi

printf "%-28s %-12s %-8s %s\n" "NAME" "PINNED" "BRANCH" "REMOTE"
for p in "${paths[@]}"; do
  validate_gitmodules_path "${root}" "${p}"
  name="$(basename "${p}")"
  url="$(git config -f .gitmodules --get "submodule.${p}.url" || echo "?")"
  branch="$(git config -f .gitmodules --get "submodule.${p}.branch" || echo "-")"
  if [ -e "${root}/${p}/.git" ]; then
    sha="$(cd "${root}/${p}" && git rev-parse --short HEAD 2>/dev/null || echo "-")"
  else
    sha="uninit"
  fi
  display_remote="${url}"
  display_remote="${display_remote#https://}"
  display_remote="${display_remote#git@}"
  display_remote="${display_remote%.git}"
  display_remote="${display_remote/\//:}"
  printf "%-28s %-12s %-8s %s\n" "${name}" "${sha}" "${branch}" "${display_remote}"
done
