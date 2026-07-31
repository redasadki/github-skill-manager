#!/usr/bin/env bats

load test_helper

setup()    { setup_workspace; cd "${WORK}"; }
teardown() { teardown_workspace; }

@test "install.sh: happy path installs, initializes, and commits a pointer" {
  make_fake_remote "sample-skill"

  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]
  assert_output_contains "installed: workspace/skills/sample-skill"

  [ -f "${WORK}/workspace/skills/sample-skill/SKILL.md" ]
  [ -f "${WORK}/.gitmodules" ]

  # The outer repo has a new commit.
  run git -C "${WORK}" log --oneline
  [ "${status}" -eq 0 ]
  assert_output_contains "Install sample-skill skill from"
}

@test "install.sh: idempotent second run exits 0 with 'already installed'" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]
  assert_output_contains "already installed"
}

@test "install.sh: idempotent run self-heals when working tree is empty" {
  # Minor 6 regression: install + wipe the working tree, rerun install,
  # expect the tree to be re-initialized rather than left empty.
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  # Simulate a half-broken checkout by removing the working tree contents.
  rm -rf "${WORK}/workspace/skills/sample-skill"
  mkdir -p "${WORK}/workspace/skills/sample-skill"

  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]
  [ -f "${WORK}/workspace/skills/sample-skill/SKILL.md" ]
}

@test "install.sh: rejects invalid skill name via --name override" {
  # Blocker 2 regression: consecutive hyphens must be rejected.
  make_fake_remote "sample-skill"

  run_install "${FAKE_URL}" "bad--name"
  [ "${status}" -ne 0 ]
  assert_output_contains "invalid skill name"
}

@test "install.sh: rejects malformed repo reference" {
  # Major 3 regression: '..' segments must not be accepted.
  run_install "../etc/passwd"
  [ "${status}" -ne 0 ]
  assert_output_contains "cannot parse repo reference"
}

@test "install.sh: refuses when path exists but is not a submodule" {
  mkdir -p "${WORK}/workspace/skills/sample-skill"
  touch "${WORK}/workspace/skills/sample-skill/keep"

  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -ne 0 ]
  assert_output_contains "already exists and is not a submodule"
}

@test "install.sh: unreachable remote fails cleanly and rolls back" {
  # Major 11 regression: partial state must not be left behind.
  run_install "file:///does/not/exist.git"
  [ "${status}" -ne 0 ]
  assert_output_contains "cannot reach"

  # No half-installed state anywhere.
  [ ! -e "${WORK}/workspace/skills" ] || [ -z "$(ls -A "${WORK}/workspace/skills")" ]
  [ ! -f "${WORK}/.gitmodules" ]
}

@test "install.sh: two skills side-by-side both install cleanly" {
  make_fake_remote "skill-a"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  make_fake_remote "skill-b"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  [ -f "${WORK}/workspace/skills/skill-a/SKILL.md" ]
  [ -f "${WORK}/workspace/skills/skill-b/SKILL.md" ]
}

@test "install.sh --push-branch: writes ghsmPushBranch and creates the branch on origin" {
  make_fake_remote "sample-skill"

  run_install --push-branch "openclaw/2026.7.x" "${FAKE_URL}"
  [ "${status}" -eq 0 ]
  assert_output_contains "recorded ghsmPushBranch=openclaw/2026.7.x"

  # .gitmodules records the extension field.
  run git -C "${WORK}" config -f .gitmodules --get "submodule.workspace/skills/sample-skill.ghsmPushBranch"
  [ "${status}" -eq 0 ]
  [ "${output}" = "openclaw/2026.7.x" ]

  # The push branch exists on the fake remote.
  run git -C "${WORK}/workspace/skills/sample-skill" ls-remote origin "refs/heads/openclaw/2026.7.x"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "install.sh --pull-branch: writes ghsmPullBranch" {
  make_fake_remote "sample-skill"

  run_install --pull-branch "main" "${FAKE_URL}"
  [ "${status}" -eq 0 ]
  assert_output_contains "recorded ghsmPullBranch=main"

  run git -C "${WORK}" config -f .gitmodules --get "submodule.workspace/skills/sample-skill.ghsmPullBranch"
  [ "${status}" -eq 0 ]
  [ "${output}" = "main" ]
}

@test "install.sh --reconfigure: sets push branch on an already-installed skill" {
  make_fake_remote "sample-skill"

  # Install one-way first.
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  # Then reconfigure for two-way.
  run_install --reconfigure --push-branch "openclaw/2026.7.x" "sample-skill"
  [ "${status}" -eq 0 ]
  assert_output_contains "recorded ghsmPushBranch=openclaw/2026.7.x"

  run git -C "${WORK}" config -f .gitmodules --get "submodule.workspace/skills/sample-skill.ghsmPushBranch"
  [ "${status}" -eq 0 ]
  [ "${output}" = "openclaw/2026.7.x" ]

  # Outer repo commit records the configuration change.
  run git -C "${WORK}" log --oneline
  assert_output_contains "Configure sample-skill skill for two-way sync"
}

@test "install.sh --reconfigure: requires at least one branch flag" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  run_install --reconfigure "sample-skill"
  [ "${status}" -ne 0 ]
  assert_output_contains "requires --pull-branch and/or --push-branch"
}

@test "install.sh: rejects unknown flag" {
  run_install --nonsense "redasadki/whatever"
  [ "${status}" -ne 0 ]
  assert_output_contains "unknown flag"
}

@test "install.sh --push-branch: rejects malformed branch name" {
  make_fake_remote "sample-skill"
  run_install --push-branch "bad branch" "${FAKE_URL}"
  [ "${status}" -ne 0 ]
  assert_output_contains "invalid branch name"
}
