---
name: pr-checklist
description: Pre-PR gate for SailingGMap — runs the three required checks (swift test, swiftlint, swift-format --lint), verifies negative controls exist for any new mathematical assertion, and confirms the PR body links its issue. TRIGGER when the user says they are ready to open a PR, asks to "check before pushing", or after implementation work completes. DO NOT trigger mid-implementation, for draft/WIP pushes, or for docs-only branches where the test gate is not meaningful.
---

# /pr-checklist — before you open the PR

Run all three gates. All must be green; there is no allowlist.

```bash
swift test --package-path Packages/SailingCore
./scripts/lint.sh          # swiftlint + swift-format --lint
```

And, for anything touching the app target:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -workspace SailingGMap.xcworkspace -scheme SailingGMap \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Content checks the tools can't do

- [ ] **Every new mathematical assertion has a negative control.** Grep your
      diff for `#expect(` — for each property assertion, find the companion test
      that asserts the property is *rejected* for a violating input. This is the
      one review item that is non-negotiable in this repo.
- [ ] **Red-then-green was actually observed.** If you wrote the test after the
      code, say so in the PR body rather than implying otherwise. (Better: stash
      the fix, watch the test fail, unstash.)
- [ ] **No tolerance was loosened without justification.** `git diff` for
      changed epsilons. If one moved, the PR body explains why the looser bound
      is correct, not merely sufficient.
- [ ] **Doc comments match the new behavior.** A stale derivation above changed
      code is the exact failure mode this project is fixing.
- [ ] **`SailingCore` still imports no UI framework.**
      `grep -rE "import (SwiftUI|AppKit)" Packages/SailingCore/Sources` → empty.
- [ ] **`import GeneralizedMap` still appears in exactly one file.**
      `grep -rl "import GeneralizedMap" Packages/SailingCore/Sources | wc -l` → `1`.
- [ ] **Invariants doc updated** if the change adds or alters one
      (`docs/invariants.md`, IDs `I1`…).
- [ ] **Spec saved** to `docs/specs/` if this was a Critical-tier change.

## PR body

Use the template in `.github/PULL_REQUEST_TEMPLATE.md`. Required:

- `Closes #N` (or `Fixes #N`) — otherwise the tracker rots.
- A **before/after** for behavioral fixes, with the actual measured output.
  "Fixed the heading calculation" is not reviewable; the table below is:

  ```
  before: values deg = ["0.0","0.0","0.0","0.0","0.0","0.0","0.0"]
  after:  values deg = ["90.0","90.0","90.0","90.0","90.0","90.0","90.0"]
  ```

- The AI-usage disclosure box, honestly filled in.

## Merging

Squash-merge onto `main` with the PR title as the commit subject. Delete the
branch. Confirm the linked issue auto-closed.
