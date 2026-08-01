---
name: architecture
description: Module map, layering rules, and data flow for SailingGMap — what depends on what, where the GeneralizedMap boundary sits, how a slider change propagates to a rendered pixel, and which layering violations to reject in review. Run with no arguments for a full snapshot. TRIGGER when orienting before a large change, when asked for a system overview, or when deciding which layer new code belongs in. DO NOT trigger for specific bug fixes, single-file questions, or implementation tasks where the relevant file is already known.
---

# Architecture — SailingGMap

## Layers, strictly ordered

```
                    ┌─────────────────────────────┐
  no UI imports  →  │  Packages/SailingCore       │
                    │    Models/       (values)   │
                    │    Mathematics/  (pure fns) │
                    └──────────┬──────────────────┘
                               │ imports
                    ┌──────────▼──────────────────┐
      @MainActor →  │  SailingGMapViewModel       │  derives + caches
                    └──────────┬──────────────────┘
                               │ @ObservedObject
                    ┌──────────▼──────────────────┐
                    │  ContentView                │
                    │    ControlsView             │  sliders → bindings
                    │    SailingGMapCanvasView    │  draws, no math
                    └─────────────────────────────┘
```

**Dependencies point one way only.** `SailingCore` knows nothing about the app.

### The two boundaries that matter

1. **`SailingCore` imports no UI framework.**
   ```bash
   grep -rE "import (SwiftUI|AppKit|UIKit)" Packages/SailingCore/Sources   # must be empty
   ```
   This is what lets `swift test` run headless in ~5 s with no window server.
   Breaking it costs the entire CI story.

2. **`import GeneralizedMap` appears in exactly one file.**
   ```bash
   grep -rl "import GeneralizedMap" Packages/SailingCore/Sources   # must be 1
   ```
   `Mathematics/SailingGMapTopology.swift` is the whole adapter surface — darts,
   orbits, cells, sewing, attributes. This is the project's headline
   architectural claim and the README advertises it. Route new topology work
   through the adapter, don't widen the boundary.

## Data flow — slider to pixel

```
ControlsView slider
  → @Published var on SailingGMapViewModel        (stripCount, θ, courseLength, …)
    → derived: axis → progressField → rhumbPath / generalizedPath
      → metrics: costBreakdown, gmapSummary, monotonicityViolation
      → geometry: courseVertices, unfoldedVertices, foliationLevelCurves,
                  integratedTrajectoryCourse
        → SailingGMapCanvasView.Canvas
          → makeTransform(domain → screen) → Path → ctx.stroke/fill
```

Every derived value is a **cached** property on the ViewModel keyed on its
inputs. SwiftUI calls `body` far more often than the user changes anything;
recomputing the G-map or re-integrating the trajectory inside `body` is the
performance bug this project already shipped once (measured 27 ms/redraw in
Debug at `N = 32`, ≈37 fps before any drawing).

## Module map

| Module | Responsibility | Depends on |
|---|---|---|
| `Models/Geometry` | `Point2D`, `Vector2D`, `CourseAxis`, frame conversion | — |
| `Models/Wind` | `WindModel`, `Tack` | Geometry |
| `Models/Strip` | one band of the corridor | Wind |
| `Models/TackPath` | strips → zig-zag polyline, lengths, arrival | Strip, Geometry |
| `Mathematics/Unfolding` | reflection isometries, straightness check | TackPath |
| `Mathematics/ProgressField` | `s: Ω → [0,1]`, gradient, Laplacian | Geometry |
| `Mathematics/Foliation` | level-curve extraction by bisection | ProgressField |
| `Mathematics/GeneralizedTackPath` | integrate the heading field over bands | ProgressField |
| `Mathematics/Optimization` | cost model + parameter sweeps | TackPath, GeneralizedTackPath |
| `Mathematics/SailingGMapTopology` | **the only** GeneralizedMap adapter | TackPath, GeneralizedMap |

## Review: layering violations to reject

| Smell | Why it's wrong | Fix |
|---|---|---|
| `import SwiftUI` in `SailingCore` | breaks headless testing | move the type to the app, or drop the convenience |
| `Canvas` block computing level curves | duplicates ViewModel work per frame | read the cached ViewModel property |
| `import GeneralizedMap` in a second file | widens the adapter boundary | extend `SailingGMapTopology` instead |
| ViewModel storing a `Path` or `Color` | view concerns leaking down | return domain points; let the view style them |
| Math function taking `CGPoint` | ambiguous frame + UI type in the core | `Point2D`, and name the frame in the signature |
| New `@Published` with a `didSet` mutating itself | re-entrant publish, hard to reason about | validate in the binding or a computed setter |

## Complexity hotspots

- `SailingGMapCanvasView.drawCourseFrame` — the largest single function; it both
  transforms and draws. Any further growth should split transform-building from
  stroking.
- `GeneralizedTackPath.integrateInCourseFrame` — the only stateful loop in the
  core; every metric (`sailedLength`, `crossTrackPeak`, `headingChangesAtTurns`)
  calls it independently. Cache one trajectory per configuration.
- `SailingGMapTopology.init` — rebuilds the entire map from scratch; ~3.4 ms at
  `N = 32`. Cache on `(stripCount, tackSequence)`.
