## Summary

<!-- 1-3 bullets: what this does and why -->

-

## Before / after

<!-- Required for behavioral fixes. Paste actual measured output, not a
     description. "Fixed the heading calculation" is not reviewable. -->

```
before:
after:
```

## Invariants

<!-- Which docs/invariants.md IDs does this touch? New ones added? -->

- Touches:
- Adds:

## Test plan

- [ ] `swift test --package-path Packages/SailingCore` — green
- [ ] `./scripts/lint.sh` — swiftlint + swift-format clean
- [ ] `xcodebuild -workspace SailingGMap.xcworkspace -scheme SailingGMap build` — clean (if app target touched)
- [ ] **Every new property assertion has a negative control** (an input where
      the property is false, asserted to be rejected)
- [ ] Red-then-green was actually observed — the test failed before the fix
- [ ] No tolerance loosened without justification below
- [ ] Doc comments updated to match new behavior

<!-- If a tolerance changed, justify it here: -->

## Risk tier

- [ ] Critical — spec approved on the issue and archived to `docs/specs/`
- [ ] High — negative-control tests present
- [ ] Normal / Low

## AI usage

- [ ] AI-assisted (tool and scope: _e.g. Claude Code, test generation + implementation_)

## Related issues

<!-- Closes #N -->
