import AppKit

struct Desktop: Equatable {
    let id: UInt64
    let kind: Int
}

struct DisplaySpaces {
    let identifier: String
    let current: UInt64
    let order: [Desktop]

    // User shortcuts address ordinary Desktops; fullscreen Spaces are counted only in the route.
    var desktops: [Desktop] { order.filter { $0.kind == 0 } }

    func destination(number: Int) throws -> Desktop {
        guard number > 0, number <= desktops.count else {
            throw Failure("Le bureau \(number) n’existe pas sur cet écran.")
        }
        return desktops[number - 1]
    }

    func steps(to target: UInt64) throws -> Int {
        guard let a = order.firstIndex(where: { $0.id == current }),
              let b = order.firstIndex(where: { $0.id == target }) else {
            throw Failure("La liste des bureaux a changé. Réessayez.")
        }
        return b - a
    }

    static func decode(_ entries: [[String: Any]]) -> [DisplaySpaces] {
        entries.compactMap { entry in
            guard let identifier = entry["Display Identifier"] as? String,
                  let active = entry["Current Space"] as? [String: Any],
                  let current = (active["ManagedSpaceID"] as? NSNumber)?.uint64Value,
                  let raw = entry["Spaces"] as? [[String: Any]] else { return nil }
            let spaces = raw.compactMap { value -> Desktop? in
                guard let id = (value["ManagedSpaceID"] as? NSNumber)?.uint64Value,
                      let type = value["type"] as? Int else { return nil }
                return Desktop(id: id, kind: type)
            }
            guard !spaces.isEmpty else { return nil }
            return DisplaySpaces(identifier: identifier, current: current, order: spaces)
        }
    }
}

struct Failure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Payload format documented by joshuarli/iss (0BSD) and gechr/WhichSpace (MIT).
/// The serialized CGEvent trailer is required by macOS 27. No real swipe is intercepted.
enum DockGesture {
    static func fixed(_ value: Double) -> Int32 {
        let scaled = value * 65_536
        if scaled >= Double(Int32.max) { return .max }
        if scaled <= Double(Int32.min) { return .min }
        let integer = Int32(scaled)
        return integer == 0 && value != 0 ? (value > 0 ? 1 : -1) : integer
    }

    private static func put<T: FixedWidthInteger>(_ value: T, in bytes: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { bytes.append(contentsOf: $0) }
    }

    static func payload(phase: Int64, progress: Double, velocity: Double, timestamp: UInt64) -> Data {
        var bytes = Data()
        put(timestamp, in: &bytes)
        put(UInt64(0), in: &bytes)
        put(UInt32(0), in: &bytes)
        put(UInt32(0), in: &bytes)
        put(UInt32(2), in: &bytes)
        // 40-byte fluid touch gesture, followed by a 28-byte velocity child.
        put(UInt32(40), in: &bytes)
        put(UInt32(23), in: &bytes)
        put(UInt32(phase & 255) << 24, in: &bytes)
        put(UInt32(0), in: &bytes)
        put(fixed(0.1), in: &bytes)
        put(Int32(0), in: &bytes)
        put(Int32(0), in: &bytes)
        put(UInt32(0), in: &bytes)
        put(UInt16(1), in: &bytes)
        put(UInt16(3), in: &bytes)
        put(fixed(-progress), in: &bytes)
        put(UInt32(28), in: &bytes)
        put(UInt32(9), in: &bytes)
        put(UInt32(0), in: &bytes)
        put(UInt32(1), in: &bytes)
        put(fixed(-velocity), in: &bytes)
        put(Int32(0), in: &bytes)
        put(Int32(0), in: &bytes)
        return bytes
    }

    static func postingRight(_ requested: Bool, naturalScrolling: Bool) -> Bool {
        naturalScrolling ? requested : !requested
    }

    /// Prepares all phases before posting, so a serialization failure cannot leave a half gesture.
    static func events(right: Bool, steps: Int) throws -> [CGEvent] {
        guard steps > 0, steps <= 64 else { throw Failure("Trajet de bureaux invalide.") }
        let natural = (UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool) ?? true
        let direction = postingRight(right, naturalScrolling: natural)
        let progress = direction ? 1.0 : -1.0
        let velocity = (direction ? 1.0 : -1.0) * 2000 * Double(steps)
        return try [Int64(1), 2, 4].map { phase in
            guard let event = CGEvent(source: nil) else { throw Failure("Impossible de créer le geste.") }
            func integer(_ field: UInt32, _ value: Int64) {
                event.setIntegerValueField(CGEventField(rawValue: field)!, value: value)
            }
            func decimal(_ field: UInt32, _ value: Double) {
                event.setDoubleValueField(CGEventField(rawValue: field)!, value: value)
            }
            event.flags = []
            integer(55, 30)
            integer(110, 23)
            integer(132, phase)
            integer(123, 1)
            integer(134, phase)
            decimal(124, progress)
            decimal(125, 0.1)
            decimal(129, velocity)
            decimal(130, 0)
            decimal(138, 3)
            decimal(169, Double(mach_absolute_time()))
            guard var serialized = event.data as Data?, serialized.starts(with: [0, 0, 0, 2]) else {
                throw Failure("Format de geste macOS non reconnu.")
            }
            let payload = payload(phase: phase, progress: progress, velocity: velocity,
                                  timestamp: event.timestamp == 0 ? mach_absolute_time() : event.timestamp)
            serialized.append(contentsOf: [0, UInt8(payload.count), 0x10, 0x6d]) // Field 4205, big endian.
            serialized.append(payload)
            guard let complete = CGEvent(withDataAllocator: kCFAllocatorDefault, data: serialized as CFData) else {
                throw Failure("macOS a refusé le geste sérialisé.")
            }
            return complete
        }
    }
}
