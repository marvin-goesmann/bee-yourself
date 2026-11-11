import AppKit

let arguments = CommandLine.arguments

if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
    let minute = arguments.firstIndex(of: "--minute").flatMap { Double(arguments[$0 + 1]) } ?? 30
    let scene = arguments.firstIndex(of: "--scene").map { arguments[$0 + 1] } ?? "meadow"
    Snapshot.write(to: arguments[index + 1], minute: minute, scene: scene)
    exit(0)
}

if let index = arguments.firstIndex(of: "--icon"), index + 1 < arguments.count {
    AppIcon.writeIconset(to: arguments[index + 1])
    exit(0)
}

if let index = arguments.firstIndex(of: "--record"), index + 1 < arguments.count {
    MainActor.assumeIsolated { Recorder.run(to: arguments[index + 1]) }
    exit(0)
}

if arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

if arguments.contains("--bench") {
    Snapshot.bench()
    exit(0)
}

if arguments.contains("--calibrate") {
    Snapshot.calibrate()
    exit(0)
}

if let index = arguments.firstIndex(of: "--time-scale"), index + 1 < arguments.count {
    Clock.timeScale = Double(arguments[index + 1]) ?? 1
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
