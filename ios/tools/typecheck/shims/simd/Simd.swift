// SHIM of Apple's `simd` module (the vector/matrix types ARKit, RoomPlan and RealityKit use). The Swift
// standard library already has SIMD2/3/4<Scalar>; Apple's `simd` module adds the `simd_float3` typealiases and
// the matrix types. Only what the app and the other shims touch is declared here.
// Every declaration carries a `// doc:` tag naming the Apple documentation page it was copied from; see
// ../README.md (docs/verify_shims.py re-checks them).
@_exported import Foundation

// doc: simd/simd_float2
public typealias simd_float2 = SIMD2<Float>
// doc: simd/simd_float3
public typealias simd_float3 = SIMD3<Float>
// doc: simd/simd_float4
public typealias simd_float4 = SIMD4<Float>

// doc: simd/simd_float4x4
public struct simd_float4x4 {
    // doc: simd/simd_float4x4/columns
    public var columns: (simd_float4, simd_float4, simd_float4, simd_float4)
    // doc: simd/simd_float4x4/init(columns:)
    public init(columns: (simd_float4, simd_float4, simd_float4, simd_float4)) { self.columns = columns }
    // doc: simd/simd_float4x4/init(_:)-50sjs
    public init(_ columns: [SIMD4<Float>]) { self.columns = (columns[0], columns[1], columns[2], columns[3]) }
    // doc: simd/simd_float4x4/init(diagonal:)
    public init(diagonal: SIMD4<Float>) {
        columns = (simd_float4(diagonal.x, 0, 0, 0), simd_float4(0, diagonal.y, 0, 0),
                   simd_float4(0, 0, diagonal.z, 0), simd_float4(0, 0, 0, diagonal.w))
    }
    // doc: simd/simd_float4x4/inverse
    public var inverse: simd_float4x4 { fatalError() }
    // doc: simd/simd_float4x4/*(_:_:)-9bvh7
    public static func * (lhs: simd_float4x4, rhs: SIMD4<Float>) -> SIMD4<Float> { fatalError() }
    // doc: simd/simd_float4x4/*(_:_:)-6yrrr
    public static func * (lhs: simd_float4x4, rhs: float4x4) -> float4x4 { fatalError() }
}
// doc: simd/float4x4
public typealias float4x4 = simd_float4x4
// doc: simd/matrix_float4x4
public typealias matrix_float4x4 = simd_float4x4
// doc: simd/matrix_identity_float4x4
public let matrix_identity_float4x4: simd_float4x4 = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
