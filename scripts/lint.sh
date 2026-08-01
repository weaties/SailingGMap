#!/usr/bin/env bash
#
# lint.sh — the formatting and lint gate.
#
#   ./scripts/lint.sh          # check only (what CI runs)
#   ./scripts/lint.sh --fix    # apply formatting in place
#
# swift-format ships with the Xcode toolchain, so the format gate has no
# install step. SwiftLint is optional locally (brew install swiftlint) and
# required in CI; when it is missing this script says so and continues rather
# than silently passing.
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MODE="check"
[ "${1:-}" = "--fix" ] && MODE="fix"

PATHS=(Packages/SailingCore/Sources Packages/SailingCore/Tests SailingGMap)
EXISTING=()
for p in "${PATHS[@]}"; do [ -d "$p" ] && EXISTING+=("$p"); done

status=0
log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31mFAIL\033[0m %s\n' "$*" >&2; status=1; }
skip() { printf '\033[1;33mSKIP\033[0m %s\n' "$*" >&2; }

# --- swift-format ------------------------------------------------------------
# Prefer the toolchain's `swift format` subcommand; fall back to a standalone
# swift-format binary if one is on PATH.

if command -v swift-format >/dev/null 2>&1; then
  FMT=(swift-format)
elif xcrun --find swift-format >/dev/null 2>&1; then
  FMT=(xcrun swift-format)
elif swift format --version >/dev/null 2>&1; then
  FMT=(swift format)
else
  FMT=()
fi

if [ ${#FMT[@]} -eq 0 ]; then
  skip "swift-format not found — format gate not enforced locally"
elif [ ${#EXISTING[@]} -eq 0 ]; then
  skip "no source directories present yet"
elif [ "$MODE" = "fix" ]; then
  log "swift-format (applying)"
  "${FMT[@]}" format --in-place --recursive --parallel "${EXISTING[@]}" || fail "swift-format errored"
else
  log "swift-format --lint"
  "${FMT[@]}" lint --strict --recursive --parallel "${EXISTING[@]}" || fail "swift-format found issues (run ./scripts/lint.sh --fix)"
fi

# --- SwiftLint ---------------------------------------------------------------

if ! command -v swiftlint >/dev/null 2>&1; then
  skip "swiftlint not installed (brew install swiftlint) — required in CI"
elif [ "$MODE" = "fix" ]; then
  log "swiftlint --fix"
  swiftlint --fix --quiet || fail "swiftlint --fix errored"
  swiftlint --quiet --strict || fail "swiftlint found issues it could not autocorrect"
else
  log "swiftlint --strict"
  swiftlint --quiet --strict || fail "swiftlint found issues"
fi

# --- layering invariants -----------------------------------------------------
# Cheap structural checks that no formatter enforces but AGENTS.md requires.

if [ -d Packages/SailingCore/Sources ]; then
  log "layering: SailingCore imports no UI framework"
  if grep -rnE '^\s*import (SwiftUI|AppKit|UIKit)' Packages/SailingCore/Sources; then
    fail "SailingCore must not import a UI framework (AGENTS.md § Architecture principles)"
  fi

  log "layering: GeneralizedMap boundary is exactly one file"
  n=$(grep -rl 'import GeneralizedMap' Packages/SailingCore/Sources | wc -l | tr -d ' ')
  if [ "$n" != "1" ]; then
    fail "import GeneralizedMap appears in $n files, expected exactly 1 (SailingGMapTopology.swift)"
  fi
fi

if [ "$status" -eq 0 ]; then
  printf '\033[1;32mAll lint gates passed.\033[0m\n'
fi
exit "$status"
