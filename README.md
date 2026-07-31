# SailingGMap - Tacking by Unfolding

`SailingGMap` is a macOS SwiftUI experiment that gives a precise mathematical
home to an old sailing intuition: flip alternating tacking strips end-to-end
and the zig-zag path becomes a straight line.

The application combines three views of the same problem:

- reflection unfolding turns the alternating path into a straight geodesic;
- a generalized map records the topology of strips and their shared seams;
- a continuous progress field extends straight strips to curved foliations.

This project is the
[`GeneralizedMap`](https://github.com/SinanKarasu/GeneralizedMap)-backed
successor to the earlier `Sailing` prototype. The sailing and optimization
models remain application code; all dart, orbit, cell, sewing, and attribute
machinery comes from the separate Swift package.

## Project layout

```text
SailingGMap/
├── SailingGMap.xcodeproj/
└── SailingGMap/
    ├── SailingGMapApp.swift        # application entry point
    ├── ContentView.swift           # controls and canvases
    ├── Models/
    │   ├── Geometry.swift          # Point2D, Vector2D, course frame
    │   ├── Wind.swift              # WindModel and Tack
    │   ├── Strip.swift             # one band of the corridor
    │   └── TackPath.swift          # strips and path geometry
    ├── Mathematics/
    │   ├── Unfolding.swift         # reflection isometries
    │   ├── SailingGMapTopology.swift # the GeneralizedMap bridge
    │   ├── Optimization.swift      # sailing cost model
    │   ├── ProgressField.swift     # affine and warped progress fields
    │   ├── Foliation.swift         # level-curve extraction
    │   └── GeneralizedTackPath.swift # curved-path integration
    ├── ViewModels/
    │   └── SailingGMapViewModel.swift
    └── Views/
        ├── ControlsView.swift
        └── SailingGMapCanvasView.swift
```

## The mathematics

### Course coordinates

Place a course frame along the rhumb line from `A` to `B`:

- `u` is the unit vector along `AB`, the along-course axis;
- `n` is `u` rotated 90 degrees left, the cross-track axis.

Partition the corridor into strips perpendicular to `u`. Strip `i` spans
`s in [s_i, s_(i+1)]` and carries a tack `sigma_i` in `{+1, -1}`. For a
tacking angle `theta`, its heading in course coordinates is

```text
h_i = (cos(theta), sigma_i sin(theta)).
```

If the strip width is `w_i = s_(i+1) - s_i`, the cross-track displacement is
`sigma_i w_i tan(theta)`.

### Unfolding

Reflect every down-going leg across the horizontal line through its starting
cross-track position. Successive reflections straighten the zig-zag into

```text
s -> (s, s tan(theta))
```

in a covering plane. The sailed length is therefore `L / cos(theta)`,
independent of the number of strips. This is the same geometric device that
appears in rational billiards, translation surfaces, and polyhedral
unfoldings.

`PlanarIsometry` in `Unfolding.swift` represents the reflections.
`Unfolding.unfoldByHorizontalReflections(of:)` constructs the lifted path,
and `Unfolding.unfoldedIsStraight(_:)` checks the result.

## Generalized-map topology

Each sailing strip is one quadrilateral face of a 2-dimensional generalized
map. Its darts are related by three involutions:

- `alpha(0)` crosses an edge;
- `alpha(1)` turns around a vertex within a face;
- `alpha(2)` crosses a shared edge into the neighboring face.

The entire application/package boundary is
[`SailingGMapTopology.swift`](SailingGMap/Mathematics/SailingGMapTopology.swift).
For every path, that adapter:

1. creates one quadrilateral face with `createRing(4)` per strip;
2. sews neighboring right and left edges through `alpha(2)`;
3. attaches typed metadata to each internal seam;
4. records whether crossing the seam reverses the tack;
5. derives dart, vertex, edge, face, Euler-characteristic, and validity
   diagnostics through the package API.

The validator checks the characteristic G-map relations: each alpha is an
involution, and `alpha(i) alpha(j)` is an involution for non-adjacent
dimensions.

### Why Damiand and Lienhardt matters

Guillaume Damiand and Pascal Lienhardt's *Combinatorial Maps: Efficient Data
Structures for Computer Graphics and Image Processing* (CRC Press, 2014) is
more than a definition of darts and involutions. It gives a rare book-length
development from the topology of cellular subdivisions to concrete data
structures, iterators, sewing and unsewing, removal and contraction,
embedding, geometric modeling, and image-processing applications.

That breadth is important here. The book shows how an abstract algebra of
permutations and orbits becomes a programmable topology kernel whose
operations preserve meaningful invariants. `GeneralizedMap` follows that
vocabulary and algorithmic lineage, while `SailingGMapTopology` demonstrates
how a domain model can use the kernel through a very small interface.

## Continuous progress fields

The rectangular-strip prototype uses the affine progress field

```text
s(p) = (p - A) dot u_AB / L.
```

More generally, choose a smooth scalar field

```text
s: Omega -> [0, 1],
s(A) = 0,
s(B) = 1,
grad(s) dot (B - A) > 0.
```

The level sets `{s = c}` are curved strip boundaries. Within band `i`, the
boat follows

```text
h(p) = cos(theta) u_hat(p) + sigma_i sin(theta) n_hat(p),
u_hat(p) = grad(s(p)) / |grad(s(p))|.
```

The included `LinearProgressField` reproduces the rhumb-line construction.
`WarpedProgressField` adds a Gaussian bump, `Foliation.swift` extracts its
level curves, and `GeneralizedTackPath.swift` integrates the resulting
trajectory. The local reflection picture and the same generalized-map seam
model continue to apply when the bands curve.

## Cost and optimization

The application evaluates both the strip path and the curved path with

```text
J = lengthWeight * sailedLength
  + turnPenalty * (N - 1)
  + headingWeight * sum |delta theta_i|^2
  + swingPenalty * max |n|
  + smoothnessWeight * integral |Laplacian(s)|^2 dA.
```

For uniform rhumb-line strips, the turn penalty favors fewer bands while the
cross-track swing favors more; the simple parameter sweep can therefore find
an interior optimum. The warped-field version measures heading changes along
the integrated trajectory.

## Building

Requirements:

- Xcode 27 beta or newer;
- Swift 6.4;
- macOS 26 or newer;
- `GeneralizedMap` 0.1.0 or newer, resolved through Swift Package Manager.

Open `SailingGMap.xcodeproj` and run the `SailingGMap` scheme, or build from
Terminal:

```sh
xcodebuild \
  -project SailingGMap.xcodeproj \
  -scheme SailingGMap \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The Xcode project uses the versioned package at
`https://github.com/SinanKarasu/GeneralizedMap.git`, with an
`upToNextMajorVersion(from: "0.1.0")` requirement.

## Origins and further directions

The starting point was a long-standing hunch: alternating tacks under a wind
constraint should become simpler after flipping alternate strips. Reflection
unfoldings explain the geometry; generalized maps give the seams and their
changes a durable combinatorial representation.

Useful references:

- G. Damiand and P. Lienhardt, *Combinatorial Maps: Efficient Data Structures
  for Computer Graphics and Image Processing*, CRC Press, 2014.
- H. Masur and S. Tabachnikov, "Rational Billiards and Flat Structures," in
  *Handbook of Dynamical Systems*, volume 1A.
- A. Zorich, "Flat Surfaces," in *Frontiers in Number Theory, Physics and
  Geometry I*.

Natural next experiments include optimizing the progress field itself,
relaxing discrete tack control to a continuous field, choosing a separate
tacking angle per band, tearing alpha(2) seams open around obstacles, and
using a measured polar diagram instead of a single fixed angle.

## License

`SailingGMap` is available under the MIT License. See [LICENSE](LICENSE).
