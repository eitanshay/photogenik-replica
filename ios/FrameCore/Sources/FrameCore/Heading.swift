import Foundation

/// Compass direction the lens points, from a device-attitude rotation matrix in a
/// "x = north, z = up" reference frame (so y = west).
///
/// Rotation matrices can be published as reference-to-device or device-to-reference. Rather than
/// trusting one convention, `LensHeading` checks which reading of the matrix reproduces the measured
/// gravity vector and uses that one.
public enum LensHeading {
    /// m is row-major: m[0] = (m11, m12, m13) and so on.
    public static func heading(m: [[Double]], gravity g: (x: Double, y: Double, z: Double), side: CameraSide) -> Double? {
        guard m.count == 3, m.allSatisfy({ $0.count == 3 }) else { return nil }
        let row3 = (m[2][0], m[2][1], m[2][2])
        let col3 = (m[0][2], m[1][2], m[2][2])
        // If the matrix maps reference to device, gravity in device = -(third column) and the device z axis
        // in the reference frame is the third row. Otherwise the roles swap.
        let errCol = abs(g.x + col3.0) + abs(g.y + col3.1)
        let errRow = abs(g.x + row3.0) + abs(g.y + row3.1)
        let devZ = errCol <= errRow ? row3 : col3
        // Rear lens looks along -z, the selfie lens along +z.
        let s: Double = side == .back ? -1 : 1
        let north = devZ.0 * s
        let west = devZ.1 * s
        let horizontal = (north * north + west * west).squareRoot()
        guard horizontal > 0.2 else { return nil } // pointing at the floor or the sky
        var h = MathX.deg(atan2(-west, north))
        if h < 0 { h += 360 }
        return h
    }
}
