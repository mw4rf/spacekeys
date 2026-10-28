import AppKit

var checks = 0
func check(_ condition: @autoclosure () throws -> Bool, _ message: String) {
    checks += 1
    guard (try? condition()) == true else { fatalError(message) }
}

let display = DisplaySpaces(identifier: "Main", current: 1, order: [
    Desktop(id: 5, kind: 0), Desktop(id: 900, kind: 4), Desktop(id: 1, kind: 0), Desktop(id: 4, kind: 0)
])
check(try display.destination(number: 1).id == 5, "Desktop positions must not be confused with internal IDs")
check(try display.destination(number: 2).id == 1, "Fullscreen Space must not consume an ordinary desktop number")
check(try display.steps(to: 5) == -2, "Route must count intervening fullscreen Spaces")
check(try display.steps(to: 4) == 1, "Route to the right")
check(try display.steps(to: 1) == 0, "Already on destination")
for invalid in [0, -1, 4, Int.max] {
    do { _ = try display.destination(number: invalid); fatalError("Accepted invalid desktop") }
    catch { checks += 1 }
}
do { _ = try display.steps(to: 77); fatalError("Accepted vanished Space") }
catch { checks += 1 }
check(DisplaySpaces.decode([["Display Identifier": "Main"]]).isEmpty, "Incomplete server data must not invent a Space")
check(DockGesture.fixed(1) == 65536, "Fixed point conversion")
check(DockGesture.fixed(-1) == -65536, "Negative fixed point conversion")
check(DockGesture.fixed(Double.leastNonzeroMagnitude) == 1, "Do not round a tiny direction to zero")
check(DockGesture.fixed(1e20) == Int32.max, "Velocity clamp")
check(DockGesture.fixed(-1e20) == Int32.min, "Negative velocity clamp")
check(DockGesture.postingRight(true, naturalScrolling: false) == false, "Honor natural scrolling inversion")
check(DockGesture.postingRight(false, naturalScrolling: true) == false, "Honor natural scrolling")
for phase in [Int64(1), 2, 4] {
    let payload = DockGesture.payload(phase: phase, progress: 1, velocity: 18000, timestamp: 123)
    check(payload.count == 96, "IOHID payload has exact packed layout, without Swift struct padding")
    check(payload[24] == 2, "Payload contains two events")
    check(payload[28] == 40 && payload[32] == 23, "Fluid gesture offsets")
    check(payload[68] == 28 && payload[72] == 9, "Velocity event offsets")
    check(payload[39] == UInt8(phase), "Phase in gesture options")
}
for steps in [1, 9, 10] {
    let events = try DockGesture.events(right: true, steps: steps)
    check(events.count == 3, "Every swipe contains all three phases")
    for event in events {
        check(event.getIntegerValueField(CGEventField(rawValue: 55)!) == 30, "Dock-control event type survives serialization")
        check(event.getIntegerValueField(CGEventField(rawValue: 110)!) == 23, "Gesture event type survives serialization")
        check(abs(event.getDoubleValueField(CGEventField(rawValue: 129)!)) == 2000 * Double(steps), "Scale velocity for long routes")
    }
}
print("PASS: \(checks) core checks. No desktop switch or window move was performed.")
