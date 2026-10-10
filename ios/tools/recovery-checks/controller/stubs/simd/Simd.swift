import Foundation
public typealias simd_float2 = SIMD2<Float>
public typealias simd_float3 = SIMD3<Float>
public typealias simd_float4 = SIMD4<Float>
public struct simd_float4x4: Codable, Sendable {
    public var columns: (simd_float4, simd_float4, simd_float4, simd_float4)
    public init(_ c0: simd_float4, _ c1: simd_float4, _ c2: simd_float4, _ c3: simd_float4) { columns = (c0, c1, c2, c3) }
    public init(columns: (simd_float4, simd_float4, simd_float4, simd_float4)) { self.columns = columns }
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        columns = (try c.decode(simd_float4.self), try c.decode(simd_float4.self), try c.decode(simd_float4.self), try c.decode(simd_float4.self))
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(columns.0); try c.encode(columns.1); try c.encode(columns.2); try c.encode(columns.3)
    }
}
