#!/usr/bin/env bats

load test_helper

setup()    { setup_workspace; cd "${WORK}"; }
teardown() { teardown_workspace; }

# Convenience wrapper for sync.sh.
run_sync() { run bash "${SCRIPTS}/sync.sh" "$@"; }

# Helper: commit a local change inside the given submodule without pushing.
# Args: <submodule-path-relative-to-WORK> <commit-message>
add_local_commit_in_submodule() {
  local rel="$1"
  local msg="$2"
  (
    cd "${WORK}/${rel}"
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    date +%s%N > LOCAL
    git add -A
    git commit -q -m "${msg}"
  )
}

@test "sync.sh: rejects invalid skill name" {
  run_sync "bad--name"
  [ "${status}" -ne 0 ]
  assert_output_contains "invalid skill name"
}

@test "sync.sh: reports in-sync state as no-op" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  run_sync "sample-skill"
  [ "${status}" -eq 0 ]
  assert_output_contains "in sync"
}

@test "sync.sh: pull only — fast-forwards from origin and bumps outer pointer" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  advance_fake_remote

  run_sync "sample-skill"
  [ "${status}" -eq 0 ]
  assert_output_contains "pulled"

  run git -C "${WORK}" log --oneline
  assert_output_contains "Bump sample-skill skill to"
}

@test "sync.sh: push only — pushes local commits to configured push branch" {
  make_fake_remote "sample-skill"
  run_install --push-branch "openclaw/test" "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  add_local_commit_in_submodule "workspace/skills/sample-skill" "local host edit"

  local_head_before="$(cd "${WORK}/workspace/skills/sample-skill" && git rev-parse HEAD)"

  run_sync "sample-skill"
  [ "${status}" -eq 0 ]
  assert_output_contains "pushing 1 local commit"
  assert_output_contains "openclaw/test"

  # The push branch on the fake remote must now point at the local HEAD.
  remote_head="$(git -C "${WORK}/workspace/skills/sample-skill" ls-remote origin "refs/heads/openclaw/test" | awk '{print $1}')"
  [ "${remote_head}" = "${local_head_before}" ]

  # The main branch on the fake remote must NOT contain the local commit
  # (that is the whole point of the push branch split).
  main_head="$(git -C "${WORK}/workspace/skills/sample-skill" ls-remote origin "refs/heads/main" | awk '{print $1}')"
  [ "${main_head}" != "${local_head_before}" ]
}

@test "sync.sh: push only — refuses when no push branch is configured" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  add_local_commit_in_submodule "workspace/skills/sample-skill" "orphan local edit"

  run_sync "sample-skill"
  [ "${status}" -ne 0 ]
  assert_output_contains "no push branch configured"
  assert_output_contains "ghsmPushBranch"
}

@test "sync.sh: diverged — prints options and exits non-zero without changing state" {
  make_fake_remote "sample-skill"
  run_install --push-branch "openclaw/test" "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  # Local commit that will not be pushed by this test.
  add_local_commit_in_submodule "workspace/skills/sample-skill" "local host edit"
  local_before="$(cd "${WORK}/workspace/skills/sample-skill" && git rev-parse HEAD)"

  # Remote advance on main.
  advance_fake_remote

  run_sync "sample-skill"
  [ "${status}" -ne 0 ]
  assert_output_contains "has diverged from origin/main"
  assert_output_contains "local-only commits:  1"
  assert_output_contains "remote-only commits: 1"
  assert_output_contains "merge upstream"
  assert_output_contains "rebase onto it"

  # No state change: the local HEAD must be untouched.
  local_after="$(cd "${WORK}/workspace/skills/sample-skill" && git rev-parse HEAD)"
  [ "${local_before}" = "${local_after}" ]
}

@test "sync.sh: refuses when submodule has uncommitted changes" {
  make_fake_remote "sample-skill"
  run_install --push-branch "openclaw/test" "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  echo "dirty" >> "${WORK}/workspace/skills/sample-skill/SKILL.md"

  run_sync "sample-skill"
  [ "${status}" -ne 0 ]
  assert_output_contains "uncommitted changes"
}

@test "sync.sh --all: mixed workspace — some skills in sync, one diverged" {
  make_fake_remote "skill-a"
  run_install --push-branch "openclaw/test" "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  make_fake_remote "skill-b"
  run_install --push-branch "openclaw/test" "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  # Advance skill-a on main and add a local commit on top: diverged.
  FAKE_SEED="${FAKE_REMOTES}/skill-a-seed"
  advance_fake_remote
  add_local_commit_in_submodule "workspace/skills/skill-a" "local a"

  run_sync "--all"
  [ "${status}" -ne 0 ]
  assert_output_contains "diverged"
  assert_output_contains "skill-a"
  # skill-b was in sync; the batch must have kept going.
  assert_output_contains "skill-b"
}
