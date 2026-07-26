#!/usr/bin/env bash
# Install a GitHub-hosted skill as a submodule under workspace/skills/.
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
#   - added workspace/skills/<name> as a submodule,
#   - recorded it in .gitmodules,
#   - committed the submodule pointer in the outer workspace repo,
#   - validated the skill with `agentskills validate` when available.
#
# You still need to `git push` the outer repo yourself.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
source "${SCRIPT_DIR}/_lib.sh"

require_cmd git

[ $# -ge 1 ] || die "usage: install.sh <repo> [<name>]"
repo_input="$1"
name_override="${2:-}"

# Parse the repo reference.
mapfile -t parsed < <(normalize_repo_url "${repo_input}")
repo_url="${parsed[0]}"
repo_base="${parsed[1]}"
name="${name_override:-${repo_base}}"

# Validate name shape (agentskills rule: lowercase alnum + hyphen, no leading/trailing hyphen).
[[ "${name}" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] \
  || die "invalid skill name '${name}'. use lowercase letters, digits, and single hyphens."

root="$(workspace_root)"
cd "${root}"

rel_path="$(skill_rel_path "${root}" "${name}")"
abs_path="${root}/${rel_path}"

# Refuse if a directory already exists at the target path.
if [ -e "${abs_path}" ]; then
  # Idempotent: if it is already the expected submodule pointing at the same URL, exit 0.
  if is_submodule_path "${rel_path}"; then
    existing_url="$(git config -f .gitmodules --get "submodule.${rel_path}.url" || true)"
    if [ "${existing_url}" = "${repo_url}" ]; then
      info "already installed: ${rel_path} -> ${repo_url}"
      exit 0
    fi
    die "path '${rel_path}' is a submodule but points at '${existing_url}', not '${repo_url}'."
  fi
  die "path '${rel_path}' already exists and is not a submodule. remove it or pick a different name."
fi

# Verify the remote is reachable and has the requested branch.
info "checking remote: ${repo_url}"
if ! git ls-remote "${repo_url}" >/dev/null 2>&1; then
  die "cannot reach '${repo_url}'. check the URL, network, and gh auth (try: gh auth status)."
fi

# Determine the default branch (fall back to main).
default_branch="$(git ls-remote --symref "${repo_url}" HEAD 2>/dev/null \
  | awk '/^ref:/ {sub("refs/heads/","",$2); print $2; exit}')"
default_branch="${default_branch:-main}"

# Make sure the target parent directory exists (workspace/skills/).
mkdir -p "$(dirname "${abs_path}")"

# Ensure the outer repo does not already have staged changes at that path.
ensure_clean_index_for "${rel_path}"

# Add the submodule.
info "adding submodule at ${rel_path} tracking ${default_branch}"
git submodule add -b "${default_branch}" "${repo_url}" "${rel_path}"
git submodule update --init --recursive -- "${rel_path}"

# Validate the skill with agentskills if the CLI is available.
# Pass an absolute path so the validator can resolve the directory name; it
# rejects "." because that literal has no name to compare with the skill's
# frontmatter.
if command -v agentskills >/dev/null 2>&1; then
  info "validating skill layout"
  agentskills validate "${abs_path}" || die "agentskills validation failed. see message above."
else
  info "note: 'agentskills' CLI not found on PATH; skipping skill validation."
fi

# Verify SKILL.md at least exists.
[ -f "${abs_path}/SKILL.md" ] \
  || info "warning: no SKILL.md at the root of the submodule. it may still be a valid skill if the repo has a nested layout, but check its README."

# Commit the pointer.
pinned_sha="$(cd "${abs_path}" && git rev-parse --short HEAD)"
git add .gitmodules "${rel_path}"
if git diff --cached --quiet; then
  info "nothing to commit; submodule was already registered."
else
  git commit -m "Install ${name} skill from ${repo_url} at ${pinned_sha}"
fi

info ""
info "installed: ${rel_path} -> ${repo_url}"
info "pinned at: ${pinned_sha}"
info "next:      git push"
