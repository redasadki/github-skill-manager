# Shared bats helpers. Sourced by every test file.

# Absolute path to the scripts directory of the skill under test.
SKILL_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
SCRIPTS="${SKILL_DIR}/scripts"

# Make sure `bats` and `git` are quiet enough for CI logs.
export GIT_AUTHOR_NAME="Test"
export GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test"
export GIT_COMMITTER_EMAIL="test@example.com"
export GIT_TERMINAL_PROMPT=0

# Modern git (>= 2.38) blocks the file:// transport when cloning submodules
# to mitigate CVE-2022-39253. Production users clone from https://github.com
# so this default is correct. The test suite uses local bare repos as fake
# remotes, so we opt back in for tests only, via GIT_CONFIG_* env vars that
# do not leak into user-level git config.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="protocol.file.allow"
export GIT_CONFIG_VALUE_0="always"

# Create an isolated workspace repo for one test. Sets:
#   WORK          absolute path to the workspace repo
#   FAKE_REMOTES  absolute path to a directory holding bare "remote" repos
setup_workspace() {
  WORK="$(mktemp -d -t ghsm-work-XXXXXX)"
  FAKE_REMOTES="$(mktemp -d -t ghsm-remotes-XXXXXX)"
  export WORK FAKE_REMOTES
  (
    cd "${WORK}"
    git init -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"
    # Turn off gpg signing that some environments enable by default.
    git config commit.gpgsign false
    echo "# workspace" > README.md
    git add -A
    git commit -q -m "init"
  )
}

# Tear down the two temp dirs.
teardown_workspace() {
  [ -n "${WORK:-}" ] && rm -rf "${WORK}" || true
  [ -n "${FAKE_REMOTES:-}" ] && rm -rf "${FAKE_REMOTES}" || true
}

# Create a fake "GitHub" repo (a local bare repo we can clone/push to).
# Args:
#   $1 = repo name, e.g. "epub2md"
#   $2 = SKILL.md contents (optional; defaults to a minimal valid manifest)
# Sets FAKE_URL to the bare repo URL for the caller.
make_fake_remote() {
  local repo_name="$1"
  local skill_body="${2:-}"
  local bare="${FAKE_REMOTES}/${repo_name}.git"
  local seed="${FAKE_REMOTES}/${repo_name}-seed"

  git init -q --bare "${bare}"
  git init -q -b main "${seed}"
  (
    cd "${seed}"
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    if [ -z "${skill_body}" ]; then
      cat > SKILL.md <<EOF
---
name: ${repo_name}
description: "Test skill for ${repo_name}. Used by bats tests only."
license: MIT
---

# ${repo_name}

Test skill.
EOF
    else
      printf '%s' "${skill_body}" > SKILL.md
    fi
    echo "# ${repo_name}" > README.md
    git add -A
    git commit -q -m "init"
    git remote add origin "${bare}"
    git push -q -u origin main
  )
  # Point the seed clone at the bare from now on so callers can add commits.
  # Use a file:// URL so it flows through normalize_repo_url like a real remote.
  export FAKE_URL="file://${bare}"
  export FAKE_SEED="${seed}"
}

# Advance a fake remote by one commit (used to test update behavior).
advance_fake_remote() {
  (
    cd "${FAKE_SEED}"
    git config user.email "test@example.com"
    git config user.name "Test"
    date +%s > CHANGE
    git add -A
    git commit -q -m "advance"
    git push -q origin main
  )
}

# Convenience wrappers so `run` in tests captures stdout+stderr.
run_install()  { run bash "${SCRIPTS}/install.sh"  "$@"; }
run_update()   { run bash "${SCRIPTS}/update.sh"   "$@"; }
run_remove()   { run bash "${SCRIPTS}/remove.sh"   "$@"; }
run_list()     { run bash "${SCRIPTS}/list.sh"     "$@"; }
run_doctor()   { run bash "${SCRIPTS}/doctor.sh"   "$@"; }

# Assert helper: fail with the captured output when the expected substring
# is not found. Bats' built-in output is not always easy to eyeball.
assert_output_contains() {
  local needle="$1"
  if [[ "${output}" != *"${needle}"* ]]; then
    printf 'expected output to contain: %s\n---output---\n%s\n' "${needle}" "${output}" >&2
    return 1
  fi
}
