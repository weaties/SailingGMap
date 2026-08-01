//
//  SailingGMapTopology.swift
//  SailingGMap
//
//  Adapter from Sailing's strip model to the GeneralizedMap package.
//

import GeneralizedMap

/// Application data carried by an edge cell representing a seam between
/// adjacent sailing strips.
public struct SailingSeamMetadata: Equatable {
    public let index: Int
    public let isReflective: Bool
}

/// A 2-dimensional generalized-map representation of a `TackPath`.
///
/// Each strip is a quadrilateral face created by `GeneralizedMap.createRing`.
/// Neighboring right/left boundary edges are sewn through alpha(2). The
/// resulting 1-cell receives metadata describing whether crossing the seam
/// reverses the tack orientation.
public struct SailingGMapTopology {
    public typealias Map = GMap3_1_0

    public let map: Map
    public let seamRepresentatives: [DartIndex]

    public init(path: TackPath) {
        let map = Map(ndims: 3)
        let faces = path.strips.map { _ in QuadFace.create(in: map) }

        var seams: [(dart: DartIndex, metadata: SailingSeamMetadata)] = []
        if faces.count > 1 {
            seams.reserveCapacity(faces.count - 1)
            for index in 0..<(faces.count - 1) {
                let leftFace = faces[index]
                let rightFace = faces[index + 1]

                // Reversing the starting dart on the right face makes the
                // alpha(0)-orbits pair in opposite boundary orientation:
                // right.first <-> left.second and right.second <-> left.first.
                let representative = leftFace.right.first
                let opposite = rightFace.left.second
                precondition(
                    map.sew(representative, opposite, alpha: 2),
                    "Adjacent strip boundaries must be alpha(2)-sewable"
                )

                seams.append(
                    (
                        representative,
                        SailingSeamMetadata(
                            index: index,
                            isReflective:
                                path.strips[index].tack
                                != path.strips[index + 1].tack
                        )
                    ))
            }
        }

        let reserved = map.reserveAttributeContainer(
            dimension: 1,
            type: SailingSeamMetadata.self,
            onMerge: { lhs, rhs in
                SailingSeamMetadata(
                    index: min(lhs.index, rhs.index),
                    isReflective: lhs.isReflective || rhs.isReflective
                )
            },
            onSplit: { ($0, $0) }
        )
        precondition(reserved, "The map must reserve its edge metadata slot")

        for seam in seams {
            map.setAttribute(
                for: seam.dart,
                value: seam.metadata,
                dimension: 1
            )
        }

        self.map = map
        self.seamRepresentatives = seams.map(\.dart)
    }

    public var dartCount: Int {
        Array(map.allDarts()).count
    }

    public var vertexCount: Int {
        map.numberCells(dimension: 0)
    }

    public var edgeCount: Int {
        map.numberCells(dimension: 1)
    }

    public var faceCount: Int {
        map.numberCells(dimension: 2)
    }

    public var eulerCharacteristic: Int {
        vertexCount - edgeCount + faceCount
    }

    /// The previous Sailing prototype counted the two alpha(2) dart-pairs
    /// belonging to every reflective geometric seam. Preserve that UI metric.
    public var reflectiveAlpha2Edges: Int {
        seamRepresentatives.reduce(into: 0) { count, dart in
            let metadata: SailingSeamMetadata? = map.attribute(
                for: dart,
                dimension: 1
            )
            if metadata?.isReflective == true {
                count += 2
            }
        }
    }

    /// Checks the defining generalized-map relations using only public package
    /// operations: every alpha is an involution, and alpha(i)alpha(j) is an
    /// involution whenever the dimensions are non-adjacent.
    public var isValid: Bool {
        for dart in map.allDarts() {
            for dimension in 0..<map.ndims {
                let partner = map.getAlpha(of: dart, dimension: dimension)
                if map.getAlpha(of: partner, dimension: dimension) != dart {
                    return false
                }
            }

            for i in 0..<map.ndims {
                guard i + 2 < map.ndims else { continue }
                for j in (i + 2)..<map.ndims {
                    let aj = map.getAlpha(of: dart, dimension: j)
                    let aiaj = map.getAlpha(of: aj, dimension: i)
                    let ajaiaj = map.getAlpha(of: aiaj, dimension: j)
                    let result = map.getAlpha(of: ajaiaj, dimension: i)
                    if result != dart {
                        return false
                    }
                }
            }
        }
        return true
    }
}

private extension SailingGMapTopology {
    struct Edge {
        let first: DartIndex
        let second: DartIndex
    }

    struct QuadFace {
        let bottom: Edge
        let right: Edge
        let top: Edge
        let left: Edge

        static func create(in map: Map) -> QuadFace {
            // createRing returns four alpha(1)-linked vertex pairs. The
            // alpha(0)-linked boundary edges lie between consecutive pairs.
            let vertices = map.createRing(4)
            precondition(vertices.count == 4)

            return QuadFace(
                bottom: Edge(
                    first: vertices[3].1,
                    second: vertices[0].0
                ),
                right: Edge(
                    first: vertices[0].1,
                    second: vertices[1].0
                ),
                top: Edge(
                    first: vertices[1].1,
                    second: vertices[2].0
                ),
                left: Edge(
                    first: vertices[2].1,
                    second: vertices[3].0
                )
            )
        }
    }
}
