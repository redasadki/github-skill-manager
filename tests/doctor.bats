#!/usr/bin/env bats

load test_helper

setup()    { setup_workspace; cd "${WORK}"; }
teardown() { teardown_workspace; }

@test "doctor.sh: empty workspace is healthy (no .gitmodules)" {
  # Blocker 1 regression: doctor must not crash without .gitmodules.
  run_doctor
  [ "${status}" -eq 0 ]
  assert_output_contains "No submodules installed."
}

@test "doctor.sh: healthy install reports all clean" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  run_doctor
  [ "${status}" -eq 0 ]
  assert_output_contains "all submodules healthy"
}

@test "doctor.sh: detects uncommitted changes in a submodule" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  echo "edit" >> "${WORK}/workspace/skills/sample-skill/SKILL.md"

  run_doctor
  [ "${status}" -ne 0 ]
  assert_output_contains "uncommitted changes"
}

@test "doctor.sh: detects pointer drift when submodule advances alone" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  # Advance the submodule without bumping the outer pointer.
  (
    cd "${WORK}/workspace/skills/sample-skill"
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    echo "drift" > DRIFT
    git add -A
    git commit -q -m "drift"
  )

  run_doctor
  [ "${status}" -ne 0 ]
  assert_output_contains "pointer drift"
}
