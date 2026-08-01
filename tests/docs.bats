#!/usr/bin/env bats
# Documentation cross-references.
#
# These are cheap invariants that catch a whole class of regression: a
# file gets renamed or moved, its old link in another doc keeps pointing
# at the missing name, and nobody notices until a user tries to click it.
# We assert only the links the manager makes strong claims about.

# Resolve REPO from the location of this file, so the tests do not depend
# on the working directory the caller happens to be in.
REPO="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"

@test "docs: MANUAL.md exists at the repo root" {
  [ -f "${REPO}/MANUAL.md" ]
}

@test "docs: README.md links to MANUAL.md" {
  run grep -F "MANUAL.md" "${REPO}/README.md"
  [ "${status}" -eq 0 ]
}

@test "docs: SKILL.md references MANUAL.md" {
  run grep -F "MANUAL.md" "${REPO}/SKILL.md"
  [ "${status}" -eq 0 ]
}

@test "docs: CHANGELOG has a section for the current SKILL.md version" {
  # Extract the version from SKILL.md frontmatter.
  version="$(grep -E "^  version: " "${REPO}/SKILL.md" | head -1 | sed -E "s/.*version: '([^']+)'.*/\1/")"
  [ -n "${version}" ]

  # CHANGELOG must have a heading for it.
  run grep -F "[${version}]" "${REPO}/CHANGELOG.md"
  [ "${status}" -eq 0 ]
}
