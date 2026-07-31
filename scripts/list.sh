#!/usr/bin/env bash
# List installed skill submodules with their pinned SHA, sync mode, and remote.

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

printf "%-28s %-12s %-24s %s\n" "NAME" "PINNED" "SYNC" "REMOTE"
for p in "${paths[@]}"; do
  validate_gitmodules_path "${root}" "${p}"
  name="$(basename "${p}")"
  url="$(git config -f .gitmodules --get "submodule.${p}.url" || echo "?")"
  pull_branch="$(skill_pull_branch "${p}")"
  push_branch="$(skill_push_branch "${p}")"
  if [ -e "${root}/${p}/.git" ]; then
    sha="$(cd "${root}/${p}" && git rev-parse --short HEAD 2>/dev/null || echo "-")"
  else
    sha="uninit"
  fi
  # Sync column: "pull:<branch>" for one-way, "pull:<a>/push:<b>" for two-way.
  if [ -n "${push_branch}" ]; then
    sync_desc="pull:${pull_branch:-?}/push:${push_branch}"
  elif [ -n "${pull_branch}" ]; then
    sync_desc="pull:${pull_branch}"
  else
    sync_desc="-"
  fi
  display_remote="${url}"
  display_remote="${display_remote#https://}"
  display_remote="${display_remote#git@}"
  display_remote="${display_remote%.git}"
  display_remote="${display_remote/\//:}"
  printf "%-28s %-12s %-24s %s\n" "${name}" "${sha}" "${sync_desc}" "${display_remote}"
done
