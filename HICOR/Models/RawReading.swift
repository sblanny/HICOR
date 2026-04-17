import Foundation

struct RawReading: Codable, Identifiable, Equatable {
    var id: UUID
    var sph: Double
    var cyl: Double
    var ax: Int
    var eye: Eye
    var sourcePhotoIndex: Int
    var lowConfidence: Bool = false
    // True when the machine printed SPH only (no CYL/AX) for this measurement —
    // valid data meaning "no astigmatism detected on this sample". Stored cyl/ax
    // are placeholders (0.0 / 0) and MUST NOT be fed into Phase 5 CYL/AX vector
    // averaging. SPH still contributes to the SPH average.
    var isSphOnly: Bool = false

    init(
        id: UUID,
        sph: Double,
        cyl: Double,
        ax: Int,
        eye: Eye,
        sourcePhotoIndex: Int,
        lowConfidence: Bool = false,
        isSphOnly: Bool = false
    ) {
        self.id = id
        self.sph = sph
        self.cyl = cyl
        self.ax = ax
        self.eye = eye
        self.sourcePhotoIndex = sourcePhotoIndex
        self.lowConfidence = lowConfidence
        self.isSphOnly = isSphOnly
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.sph = try c.decode(Double.self, forKey: .sph)
        self.cyl = try c.decode(Double.self, forKey: .cyl)
        self.ax = try c.decode(Int.self, forKey: .ax)
        self.eye = try c.decode(Eye.self, forKey: .eye)
        self.sourcePhotoIndex = try c.decode(Int.self, forKey: .sourcePhotoIndex)
        self.lowConfidence = try c.decodeIfPresent(Bool.self, forKey: .lowConfidence) ?? false
        self.isSphOnly = try c.decodeIfPresent(Bool.self, forKey: .isSphOnly) ?? false
    }
}
