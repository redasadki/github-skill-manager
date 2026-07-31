#!/usr/bin/env bash
# Shared helpers for the github-skill-manager scripts.
# Sourced with:  source "$(dirname "$0")/_lib.sh"
#
# Not intended to be sourced from an interactive shell.

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

# Canonical skill name shape: agentskills spec.
# - 1..64 characters
# - lowercase letters, digits, single hyphens
# - no leading or trailing hyphen
# - no consecutive hyphens
readonly SKILL_NAME_REGEX='^[a-z0-9](-?[a-z0-9])*$'

validate_skill_name() {
  local name="$1"
  local n="${#name}"
  [ "${n}" -ge 1 ] && [ "${n}" -le 64 ] \
    || die "invalid skill name '${name}': length must be 1..64 characters."
  [[ "${name}" =~ ${SKILL_NAME_REGEX} ]] \
    || die "invalid skill name '${name}': use lowercase letters, digits, and single hyphens (no leading, trailing, or consecutive hyphens)."
}

workspace_root() {
  # Must be run inside a git working tree. Return the top-level directory.
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "${root}" ] || die "not inside a git working tree. cd into the workspace repo first."
  echo "${root}"
}

skills_dir() {
  # Location for skill submodules. Order of preference:
  #   1. $GHSM_SKILLS_DIR (absolute or relative to root)
  #   2. <root>/workspace/skills if it exists
  #   3. <root>/skills if it exists
  #   4. <root>/workspace/skills as the default
  local root="$1"
  if [ -n "${GHSM_SKILLS_DIR:-}" ]; then
    case "${GHSM_SKILLS_DIR}" in
      /*) echo "${GHSM_SKILLS_DIR}" ;;
      *)  echo "${root}/${GHSM_SKILLS_DIR}" ;;
    esac
    return
  fi
  if [ -d "${root}/workspace/skills" ]; then
    echo "${root}/workspace/skills"
  elif [ -d "${root}/skills" ]; then
    echo "${root}/skills"
  else
    echo "${root}/workspace/skills"
  fi
}

# Return the submodule path for <name>, relative to workspace root.
skill_rel_path() {
  local root="$1"
  local name="$2"
  local sd
  sd="$(skills_dir "${root}")"
  # Strip leading root/ if present, else use the path as-is (when GHSM_SKILLS_DIR is absolute outside root).
  echo "${sd#${root}/}/${name}"
}

# Parse a repo reference into a canonical URL and a repo basename.
# Prints two lines: URL then basename. Rejects anything ambiguous.
#
# Accepted forms:
#   - owner/name                                (GitHub short form)
#   - https://github.com/owner/name(.git)?
#   - git@github.com:owner/name(.git)?
#   - file:///absolute/path/to/repo(.git)?      (for tests and self-hosted mirrors)
normalize_repo_url() {
  local input="$1"
  local url basename owner_repo

  # file:// form: used by the test suite and by anyone mirroring a repo
  # to a local bare clone.
  if [[ "${input}" =~ ^file://(/.+)$ ]]; then
    url="${input}"
    basename="$(basename "${BASH_REMATCH[1]}")"
    basename="${basename%.git}"
    echo "${url}"
    echo "${basename}"
    return 0
  fi

  # SSH form: git@github.com:owner/name(.git)?
  if [[ "${input}" =~ ^git@github\.com:([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)$ ]]; then
    owner_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    url="https://github.com/${owner_repo}"
  # HTTPS form: https://github.com/owner/name(.git)?
  elif [[ "${input}" =~ ^https?://github\.com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)$ ]]; then
    owner_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    url="https://github.com/${owner_repo}"
  # Short form: owner/name
  elif [[ "${input}" =~ ^([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)$ ]]; then
    owner_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    url="https://github.com/${owner_repo}.git"
  else
    die "cannot parse repo reference: '${input}'. use owner/name, https URL, git@github.com:owner/name, or file:///path/to/repo.git."
  fi

  # Forbid path traversal segments and empty parts.
  local owner name_part
  owner="${owner_repo%%/*}"
  name_part="${owner_repo##*/}"
  case "${owner}" in
    ""|"."|"..") die "invalid owner in '${input}'." ;;
  esac
  case "${name_part}" in
    ""|"."|"..") die "invalid repo name in '${input}'." ;;
  esac

  basename="${name_part%.git}"
  case "${url}" in
    *.git) : ;;
    *) url="${url}.git" ;;
  esac

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

# True if the given path (relative to root) is a registered submodule.
# Returns false quietly when .gitmodules is absent.
is_submodule_path() {
  local rel="$1"
  [ -f .gitmodules ] || return 1
  git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null \
    | awk '{print $2}' \
    | grep -Fxq "${rel}"
}

# Print installed submodule paths relative to workspace root, one per line.
# Returns 0 with empty output when .gitmodules is absent.
submodule_names() {
  [ -f .gitmodules ] || return 0
  git config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null \
    | awk '{print $2}' \
    || true
}

# Number of commits reachable from HEAD but not from the given upstream ref.
# Prints 0 when the upstream ref does not exist or cannot be resolved. Callers
# that need to distinguish "no upstream" from "in sync" should check the
# upstream ref separately (via `git rev-parse --verify`).
#
# Usage: count_local_only <submodule-abs-path> <upstream-ref>
count_local_only() {
  local path="$1"
  local upstream="$2"
  ( cd "${path}" && git rev-list --count "${upstream}..HEAD" 2>/dev/null ) || echo 0
}

# Number of commits reachable from the given upstream ref but not from HEAD.
# Same conventions as count_local_only.
#
# Usage: count_remote_only <submodule-abs-path> <upstream-ref>
count_remote_only() {
  local path="$1"
  local upstream="$2"
  ( cd "${path}" && git rev-list --count "HEAD..${upstream}" 2>/dev/null ) || echo 0
}

# Read the ghsmPushBranch extension field from .gitmodules for a given
# submodule path. Prints the empty string when absent.
#
# Usage: skill_push_branch <rel-path>
skill_push_branch() {
  local rel="$1"
  [ -f .gitmodules ] || { echo ""; return 0; }
  git config -f .gitmodules --get "submodule.${rel}.ghsmPushBranch" 2>/dev/null || echo ""
}

# Read the ghsmPullBranch extension field from .gitmodules for a given
# submodule path. Falls back to the standard `branch` field, then to the
# empty string. The caller decides what to do with an empty value.
#
# Usage: skill_pull_branch <rel-path>
skill_pull_branch() {
  local rel="$1"
  local v
  [ -f .gitmodules ] || { echo ""; return 0; }
  v="$(git config -f .gitmodules --get "submodule.${rel}.ghsmPullBranch" 2>/dev/null || true)"
  if [ -n "${v}" ]; then
    echo "${v}"
    return 0
  fi
  git config -f .gitmodules --get "submodule.${rel}.branch" 2>/dev/null || echo ""
}

# Validate a git branch name at the level we care about: not empty, no
# whitespace, no leading dash, no `..`, no ASCII control characters, no
# `~^:?*[\` and no trailing `.lock`. Not as strict as `git check-ref-format`
# but catches obvious misuse without shelling out to git for each name.
#
# Usage: validate_branch_name <branch>
validate_branch_name() {
  local b="$1"
  [ -n "${b}" ] || die "branch name cannot be empty."
  case "${b}" in
    -*)   die "invalid branch name '${b}': cannot start with '-'." ;;
    *..*) die "invalid branch name '${b}': cannot contain '..'." ;;
    *.lock) die "invalid branch name '${b}': cannot end with '.lock'." ;;
  esac
  if [[ "${b}" =~ [[:space:]] ]]; then
    die "invalid branch name '${b}': cannot contain whitespace."
  fi
  if [[ "${b}" =~ [~\^:\?\*\[\\] ]]; then
    die "invalid branch name '${b}': contains one of ~ ^ : ? * [ \\."
  fi
}

# Validate that a path read from .gitmodules is well-formed and lives under
# the configured skills directory. Rejects absolute paths, path traversal,
# and anything outside the skills directory. Dies with a clear message.
validate_gitmodules_path() {
  local root="$1"
  local rel="$2"

  case "${rel}" in
    ""|/*) die "refusing malformed .gitmodules path: '${rel}'." ;;
  esac
  case "${rel}" in
    *..*) die "refusing .gitmodules path with '..': '${rel}'." ;;
  esac

  local sd_rel
  sd_rel="$(skills_dir "${root}")"
  sd_rel="${sd_rel#${root}/}"
  case "${rel}" in
    "${sd_rel}"/*) : ;;
    *) die "refusing .gitmodules path outside skills dir '${sd_rel}': '${rel}'." ;;
  esac

  # The final path component must be a valid skill name.
  validate_skill_name "$(basename "${rel}")"
}
