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
  assert_output_contains "all skill submodules healthy"
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

@test "doctor.sh: reports two-way sync misconfiguration when push == pull" {
  make_fake_remote "sample-skill"
  run_install --pull-branch "main" --push-branch "main" "${FAKE_URL}"
  # Note: install itself does not refuse this combination (it is a valid
  # git configuration, just semantically wrong), so we rely on doctor to
  # catch it. install exits 0.
  [ "${status}" -eq 0 ]

  run_doctor
  [ "${status}" -ne 0 ]
  assert_output_contains "defeats two-way sync"
}

@test "doctor.sh: silently ignores an out-of-scope submodule (regression)" {
  add_out_of_scope_submodule ".superpowers" "framework"
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  run_doctor
  [ "${status}" -eq 0 ]
  assert_output_contains "all skill submodules healthy"
  # Doctor must not have tried to check the framework submodule.
  if [[ "${output}" == *"checking .superpowers"* ]]; then
    printf 'expected .superpowers to be skipped, got:\n%s\n' "${output}" >&2
    return 1
  fi
}

@test "doctor.sh: unpushed commits with push branch suggest sync.sh" {
  make_fake_remote "sample-skill"
  run_install --push-branch "openclaw/test" "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  # Commit a local change and do not push it.
  (
    cd "${WORK}/workspace/skills/sample-skill"
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    echo "local" >> SKILL.md
    git add -A
    git commit -q -m "local"
  )

  run_doctor
  [ "${status}" -ne 0 ]
  assert_output_contains "unpushed commit"
  assert_output_contains "sync.sh sample-skill"
}
