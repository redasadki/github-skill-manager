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
