# CLAUDE.md — SailingGMap

The canonical project guide for all agents (human or AI) lives in `AGENTS.md`.
It is imported here so Claude Code loads it as project instructions:

@AGENTS.md

Everything in `AGENTS.md` applies. The rest of this file is **only** the
Claude-Code-specific mechanics that implement or extend those rules — keep
project conventions in `AGENTS.md`, not here.

## Claude Code specifics

- **Skills.** The harness lists available skills each session; invoke them with
  the Skill tool (`/name`). The ones that back rules in `AGENTS.md`:

  | Skill | Backs which rule |
  |---|---|
  | `/tdd` | "Follow TDD" + the falsifiability rule — Swift Testing patterns, negative-control recipes, the tolerance table in executable form |
  | `/math-invariants` | The sign/frame conventions table and the system-wide invariants every change must preserve |
  | `/spec` | The Critical-tier "structured spec before implementation" gate |
  | `/toolchain` | The `GeneralizedMap` `swift-tools-version: 6.4` gotcha and the `DEVELOPER_DIR` / Rosetta pitfalls |
  | `/pr-checklist` | The three gates (`swift test`, `swiftlint`, `swift-format --lint`) plus `Closes #N` |
  | `/architecture` | The layering rules — `SailingCore` has no UI imports, the G-map boundary is one file |

- **Critical-tier gate.** Before editing anything under
  `Packages/SailingCore/Sources/SailingCore/Mathematics/`, run `/spec <issue>`
  and get the spec approved on the issue. Do not start with implementation.

- **Running the app.** The app needs real Xcode, not Command Line Tools. If
  `xcodebuild` errors with "requires Xcode, but active developer directory is a
  command line tools instance", prefix commands with
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` rather than
  running `sudo xcode-select -s` unasked — changing the machine's active
  toolchain is the user's call.

- **Shell architecture.** Bash tool sessions may run under Rosetta
  (`uname -m` → `x86_64` on Apple Silicon). Tools that dispatch on architecture
  — `nm`, `swift` from `/Library/Developer/CommandLineTools` — will silently
  read the wrong slice or fail to load. Prefix with `arch -arm64` when a
  binary-inspection result looks impossibly empty.

- **Memory.** File-based memory persists across sessions under
  `~/.claude/projects/-Users-dweatbrook-tmp-sailing-fork/memory/`, indexed by
  `MEMORY.md`. Save durable facts there (user preferences, project state,
  external references); don't restate what the repo or `AGENTS.md` already
  records.
