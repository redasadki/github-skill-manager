#!/usr/bin/env bats

load test_helper

setup()    { setup_workspace; cd "${WORK}"; }
teardown() { teardown_workspace; }

@test "remove.sh: happy path removes the submodule and commits" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  run_remove "sample-skill"
  [ "${status}" -eq 0 ]
  assert_output_contains "removed:"

  [ ! -e "${WORK}/workspace/skills/sample-skill" ]
  # .gitmodules should be gone or no longer contain the entry.
  if [ -f "${WORK}/.gitmodules" ]; then
    ! grep -q "submodule \"workspace/skills/sample-skill\"" "${WORK}/.gitmodules"
  fi

  run git -C "${WORK}" log --oneline
  assert_output_contains "Remove sample-skill skill"
}

@test "remove.sh: refuses when submodule has uncommitted changes" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  echo "local edit" >> "${WORK}/workspace/skills/sample-skill/SKILL.md"

  run_remove "sample-skill"
  [ "${status}" -ne 0 ]
  assert_output_contains "uncommitted changes"
  [ -e "${WORK}/workspace/skills/sample-skill/SKILL.md" ]
}

@test "remove.sh: refuses when submodule has unpushed local commits" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  # Create a local commit that origin does not have.
  (
    cd "${WORK}/workspace/skills/sample-skill"
    git config user.email "test@example.com"
    git config user.name "Test"
    git config commit.gpgsign false
    echo "local only" > LOCAL
    git add -A
    git commit -q -m "local only"
  )

  run_remove "sample-skill"
  [ "${status}" -ne 0 ]
  assert_output_contains "local commits not on origin"

  # Submodule must still exist.
  [ -f "${WORK}/workspace/skills/sample-skill/SKILL.md" ]
}

@test "remove.sh: fails closed when origin cannot be fetched" {
  # Major 4 regression: unreachable origin must NOT allow the removal.
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  # Break the remote by removing the bare repo behind the file:// URL.
  rm -rf "${FAKE_URL#file://}"

  run_remove "sample-skill"
  [ "${status}" -ne 0 ]
  assert_output_contains "cannot fetch from origin"
  [ -f "${WORK}/workspace/skills/sample-skill/SKILL.md" ]
}

@test "remove.sh: rejects invalid skill name" {
  run_remove "bad--name"
  [ "${status}" -ne 0 ]
  assert_output_contains "invalid skill name"
}
