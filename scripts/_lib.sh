#!/usr/bin/env bash
# Shared helpers for the github-skill-manager scripts.
# Sourced with:  source "$(dirname "$0")/_lib.sh"

set -euo pipefail

die() {
  echo "error: $*" >&2
  exit 1
}

info() {
  echo "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

workspace_root() {
  # Must be run inside a git working tree. Return the top-level directory.
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "${root}" ] || die "not inside a git working tree. cd into the workspace repo first."
  echo "${root}"
}

skills_dir() {
  # Convention: skills live at <workspace-root>/workspace/skills or, if the
  # workspace repo IS itself the workspace/ directory, at <root>/skills.
  local root="$1"
  if [ -d "${root}/workspace/skills" ]; then
    echo "${root}/workspace/skills"
  elif [ -d "${root}/skills" ]; then
    echo "${root}/skills"
  else
    # Default to the more common layout and create on demand.
    echo "${root}/workspace/skills"
  fi
}

# Return the path a submodule should live at, relative to workspace-root.
skill_rel_path() {
  local root="$1"
  local name="$2"
  local sd
  sd="$(skills_dir "${root}")"
  # Strip the leading root plus slash.
  echo "${sd#${root}/}/${name}"
}

normalize_repo_url() {
  # Accept owner/name, https://..., or git@github.com:...
  # Print a canonical https URL and, separately, the repo basename.
  local input="$1"
  local url basename
  if [[ "${input}" =~ ^git@github.com:(.+)$ ]]; then
    url="https://github.com/${BASH_REMATCH[1]}"
  elif [[ "${input}" =~ ^https?://github.com/.+$ ]]; then
    url="${input}"
  elif [[ "${input}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]]; then
    url="https://github.com/${input}.git"
  else
    die "cannot parse repo reference: '${input}'. use owner/name, https URL, or git@github.com:owner/name."
  fi
  # Strip a trailing .git for the basename.
  basename="$(basename "${url%.git}")"
  echo "${url}"
  echo "${basename}"
}

ensure_clean_index_for() {
  # Refuse to proceed if <path> has unstaged or staged changes in the outer repo.
  local path="$1"
  if ! git diff --quiet -- "${path}" 2>/dev/null; then
    die "outer repo has unstaged changes touching '${path}'. commit or stash them first."
  fi
  if ! git diff --cached --quiet -- "${path}" 2>/dev/null; then
    die "outer repo has staged changes touching '${path}'. commit or unstage them first."
  fi
}

is_submodule_path() {
  # True if the given path (relative to root) is a registered submodule.
  local rel="$1"
  git config -f .gitmodules --get-regexp "^submodule\\..*\\.path$" 2>/dev/null \
    | awk '{print $2}' \
    | grep -Fxq "${rel}"
}

submodule_names() {
  # Print installed submodule paths relative to workspace root, one per line.
  git config -f .gitmodules --get-regexp "^submodule\\..*\\.path$" 2>/dev/null \
    | awk '{print $2}'
}
