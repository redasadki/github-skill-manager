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

@test "list.sh: silently ignores an out-of-scope submodule (regression)" {
  # v0.3.1 regression. Before v0.3.1, any submodule at a path outside the
  # configured skills directory (for example, .superpowers/ used by the
  # obra/superpowers framework) caused list.sh, update.sh --all, doctor.sh,
  # and sync.sh --all to die with:
  #   error: refusing .gitmodules path outside skills dir 'skills': '.superpowers'.
  # A workspace must be able to host non-skill submodules freely.
  add_out_of_scope_submodule ".superpowers" "framework"

  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  run_list
  [ "${status}" -eq 0 ]
  assert_output_contains "sample-skill"
  # .superpowers must NOT appear in the table.
  if [[ "${output}" == *".superpowers"* ]]; then
    printf 'expected .superpowers to be filtered out, got:\n%s\n' "${output}" >&2
    return 1
  fi
}

@test "list.sh: reports when only non-skill submodules exist" {
  add_out_of_scope_submodule ".superpowers" "framework"

  run_list
  [ "${status}" -eq 0 ]
  assert_output_contains "No skill submodules installed"
}
