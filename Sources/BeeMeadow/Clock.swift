import Foundation

enum Clock {
    static let cycleMinutes = 75.0
    static let dayMinutes = 60.0

    static var fixedMinute: Double?
    static var timeScale = 1.0
    static var offset: TimeInterval = 0
    static let wakeMinute = 5.0

    static func minute(at date: Date) -> Double {
        if let fixedMinute { return fixedMinute }
        let minutes = (date.timeIntervalSince1970 + offset) * timeScale / 60
        return minutes.truncatingRemainder(dividingBy: cycleMinutes)
    }

    static func canSleep(_ m: Double) -> Bool { m >= 50 || m < wakeMinute - 2 }

    static func secondsUntilMorning(from m: Double) -> TimeInterval {
        let minutes = (wakeMinute - m + cycleMinutes).truncatingRemainder(dividingBy: cycleMinutes)
        return minutes * 60 / timeScale
    }

    static func activity(_ m: Double) -> Double {
        smooth(4, 9, m) * (1 - smooth(49, 55, m))
    }

    static func smooth(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }

    struct Keyframe {
        let minute: Double
        let sky: [RGB]
        let tint: RGB
    }

    struct Light {
        let sky: [RGB]
        let tint: RGB
        var darkness: Double { smooth(0.75, 0.45, tint.luminance) }
    }

    private static func key(_ m: Double, _ sky: [String], _ tint: String) -> Keyframe {
        Keyframe(minute: m, sky: sky.map(RGB.init), tint: RGB(tint))
    }

    private static let preDawn = (["#2a2d55", "#3d3f6c", "#5a5480", "#7a6790"], "#7576a6")
    private static let night = (["#1d1f3a", "#25284a", "#2e3157", "#373a62"], "#5a6292")

    static let keyframes: [Keyframe] = [
        key(0, preDawn.0, preDawn.1),
        key(3, ["#5b6fa3", "#9a8fb5", "#e3a9a2", "#f6c79a"], "#e6c2b6"),
        key(8, ["#8fc3e0", "#a9d2e6", "#c7e2ea", "#e6efe2"], "#f7f5ee"),
        key(25, ["#86c1e6", "#a3d0ec", "#c2e0ef", "#dcecef"], "#ffffff"),
        key(42, ["#f0bf86", "#f5d3a1", "#f9e4bf", "#fbefd6"], "#ffe8c6"),
        key(52, ["#6e6a9a", "#c0789a", "#ee9a7f", "#f8c88a"], "#f0b49c"),
        key(57, ["#3e3b5e", "#5a4f78", "#86668a", "#b8808f"], "#9a8cb2"),
        key(61, night.0, night.1),
        key(72, night.0, night.1),
        key(75, preDawn.0, preDawn.1),
    ]

    static func light(at m: Double) -> Light {
        var i = 0
        while i < keyframes.count - 2 && m >= keyframes[i + 1].minute { i += 1 }
        let a = keyframes[i], b = keyframes[i + 1]
        let t = smooth(0, 1, (m - a.minute) / (b.minute - a.minute))
        return Light(
            sky: zip(a.sky, b.sky).map { $0.mixed(with: $1, t) },
            tint: a.tint.mixed(with: b.tint, t)
        )
    }
}
