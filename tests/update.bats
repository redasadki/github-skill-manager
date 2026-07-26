#!/usr/bin/env bats

load test_helper

setup()    { setup_workspace; cd "${WORK}"; }
teardown() { teardown_workspace; }

@test "update.sh: no-op when already up to date" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  run_update "sample-skill"
  [ "${status}" -eq 0 ]
  assert_output_contains "already up to date"
}

@test "update.sh: bumps the outer pointer when the remote has advanced" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  before_sha="$(cd "${WORK}/workspace/skills/sample-skill" && git rev-parse HEAD)"
  advance_fake_remote

  run_update "sample-skill"
  [ "${status}" -eq 0 ]
  assert_output_contains "bumped"

  after_sha="$(cd "${WORK}/workspace/skills/sample-skill" && git rev-parse HEAD)"
  [ "${before_sha}" != "${after_sha}" ]

  # Outer repo got a bump commit.
  run git -C "${WORK}" log --oneline
  assert_output_contains "Bump sample-skill skill to"
}

@test "update.sh: refuses when submodule has uncommitted changes" {
  make_fake_remote "sample-skill"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  echo "local edit" >> "${WORK}/workspace/skills/sample-skill/SKILL.md"

  run_update "sample-skill"
  [ "${status}" -ne 0 ]
  assert_output_contains "uncommitted changes"
}

@test "update.sh --all: one failing skill does not stop the batch" {
  # Major 5 regression: --all must continue past per-skill failures and
  # exit non-zero at the end.
  make_fake_remote "skill-good"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  make_fake_remote "skill-bad"
  run_install "${FAKE_URL}"
  [ "${status}" -eq 0 ]

  # Advance skill-good so it has real work to do; leave skill-bad broken
  # with a dirty working tree so it fails.
  (
    cd "${FAKE_SEED}"      # currently pointing at skill-bad by construction
    echo "dirty" >> "${WORK}/workspace/skills/skill-bad/SKILL.md"
  )
  # And advance skill-good by re-pointing the seed at it.
  FAKE_SEED="${FAKE_REMOTES}/skill-good-seed"
  advance_fake_remote

  run_update "--all"
  [ "${status}" -ne 0 ]
  assert_output_contains "failed skills:"
  assert_output_contains "skill-bad"
  # skill-good must still have been bumped.
  run git -C "${WORK}" log --oneline
  assert_output_contains "Bump skill-good skill to"
}

@test "update.sh: rejects invalid skill name" {
  run_update "bad--name"
  [ "${status}" -ne 0 ]
  assert_output_contains "invalid skill name"
}
