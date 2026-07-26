#!/usr/bin/env bats

load test_helper

setup()    { setup_workspace; cd "${WORK}"; }
teardown() { teardown_workspace; }

@test "list.sh: empty workspace with no .gitmodules is clean, exits 0" {
  # Blocker 1 regression: .gitmodules is absent on a fresh workspace.
  run_list
  [ "${status}" -eq 0 ]
  assert_output_contains "No submodules installed."
}

@test "list.sh: single installed skill is reported" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  run_list
  [ "${status}" -eq 0 ]
  assert_output_contains "NAME"
  assert_output_contains "sample-skill"
  assert_output_contains "main"
}
