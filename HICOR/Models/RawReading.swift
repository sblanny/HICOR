import Foundation

struct RawReading: Codable, Identifiable, Equatable {
    var id: UUID
    var sph: Double
    var cyl: Double
    var ax: Int
    var eye: Eye
    var sourcePhotoIndex: Int
    var lowConfidence: Bool = false

    init(
        id: UUID,
        sph: Double,
        cyl: Double,
        ax: Int,
        eye: Eye,
        sourcePhotoIndex: Int,
        lowConfidence: Bool = false
    ) {
        self.id = id
        self.sph = sph
        self.cyl = cyl
        self.ax = ax
        self.eye = eye
        self.sourcePhotoIndex = sourcePhotoIndex
        self.lowConfidence = lowConfidence
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
    }
}
