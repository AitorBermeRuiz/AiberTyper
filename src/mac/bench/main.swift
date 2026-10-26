// Measures the real build/AiberTyper.app from outside: launches it with --bench, drives it through stdin
// (show, type a round, hide) and samples its CPU, RAM, wakeups, energy and GPU in each phase.
// Run src/mac/bench.sh. The app uses a temporary history and settings, never the user's.
import Foundation
import IOKit

struct Sample {
    var t: Double
    var cpu: Double // seconds of CPU time, user + system
    var ram: UInt64 // phys_footprint, the "Memory" column of Activity Monitor
    var ramPeak: UInt64
    var wakeups: UInt64
    var energy: UInt64 // nanojoules
    var gpu: UInt64 // nanoseconds of GPU time submitted by the app
    var serverGPU: UInt64 // the same for WindowServer, which composites the panel on screen
}

let timebase: Double = { var info = mach_timebase_info(); mach_timebase_info(&info); return Double(info.numer) / Double(info.denom) }()

/// GPU nanoseconds per process creator ("pid 1, name"), from the GPU driver's user clients (what `ioreg -c AGXDeviceUserClient` shows).
// shortcut: only Apple Silicon fills AppUsage; other GPUs show 0.
func gpuTimes() -> [String: UInt64] {
    // User clients are not registered services, so matching them finds nothing: walk the accelerator's subtree.
    let accelerator = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOAccelerator"))
    defer { IOObjectRelease(accelerator) }
    var iterator: io_iterator_t = 0
    guard IORegistryEntryCreateIterator(accelerator, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [:] }
    defer { IOObjectRelease(iterator) }
    var times: [String: UInt64] = [:]
    while case let client = IOIteratorNext(iterator), client != 0 {
        defer { IOObjectRelease(client) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(client, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any], let creator = dict["IOUserClientCreator"] as? String else { continue }
        let usage = dict["AppUsage"] as? [[String: Any]] ?? []
        times[creator, default: 0] += usage.reduce(0) { $0 + (($1["accumulatedGPUTime"] as? NSNumber)?.uint64Value ?? 0) }
    }
    return times
}

func sample(_ pid: pid_t, start: Date) -> Sample {
    var info = rusage_info_v6()
    let status = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) } }
    precondition(status == 0, "proc_pid_rusage failed: is the app still running?")
    let gpu = gpuTimes()
    // CPU times come in Mach ticks, not nanoseconds, on Apple Silicon.
    return Sample(t: Date().timeIntervalSince(start), cpu: Double(info.ri_user_time + info.ri_system_time) * timebase / 1e9,
                  ram: info.ri_phys_footprint, ramPeak: info.ri_lifetime_max_phys_footprint,
                  wakeups: info.ri_interrupt_wkups + info.ri_pkg_idle_wkups, energy: info.ri_energy_nj,
                  gpu: gpu["pid \(pid), AiberTyper"] ?? 0, serverGPU: gpu.first { $0.key.hasSuffix(", WindowServer") }?.value ?? 0)
}

let appPath = CommandLine.arguments[1]
let app = Process()
app.executableURL = URL(fileURLWithPath: appPath)
app.arguments = ["--bench"]
let input = Pipe(), output = Pipe()
app.standardInput = input
app.standardOutput = output

/// Lines the app answers, read on a background thread so sampling never blocks.
final class Replies: @unchecked Sendable {
    private var lines: [String] = []
    private let lock = NSLock()
    func push(_ line: String) { lock.withLock { lines.append(line) } }
    func pop() -> String? { lock.withLock { lines.isEmpty ? nil : lines.removeFirst() } }
}
let replies = Replies()
Thread.detachNewThread {
    var buffer = Data()
    while case let chunk = output.fileHandleForReading.availableData, !chunk.isEmpty {
        buffer += chunk
        while let newline = buffer.firstIndex(of: 10) {
            replies.push(String(decoding: buffer[..<newline], as: UTF8.self))
            buffer = buffer[(newline + 1)...]
        }
    }
}

struct Phase { var name: String; var samples: [Sample] }
var phases: [Phase] = []
var notes: [String] = []
// The user's own history, which the run must leave exactly as it was.
let userHistory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AiberTyper/history.json")
let historyBefore = try? Data(contentsOf: userHistory)
let start = Date()
try app.run()
var last = sample(app.processIdentifier, start: start)

/// Samples every 0.5 s until `seconds` pass, or until the app answers when `seconds` is nil. Returns the answer.
@discardableResult
func phase(_ name: String, send command: String? = nil, seconds: Double? = nil) -> String? {
    if let command { input.fileHandleForWriting.write(Data((command + "\n").utf8)) }
    var samples = [last], reply: String?
    let begin = Date()
    while true {
        if seconds == nil, let line = replies.pop() { reply = line; break }
        if let seconds, Date().timeIntervalSince(begin) >= seconds { break }
        precondition(Date().timeIntervalSince(begin) < 300, "\(name): the app did not answer in 5 minutes")
        Thread.sleep(forTimeInterval: 0.5)
        samples.append(sample(app.processIdentifier, start: start))
    }
    last = sample(app.processIdentifier, start: start)
    samples.append(last)
    phases.append(Phase(name: name, samples: samples))
    return reply
}

let ready = phase("launch (until ready)") ?? ""
precondition(ready.hasPrefix("ready "), "the app did not start in bench mode: \(ready)")
let benchDir = String(ready.dropFirst("ready ".count))
phase("idle, panel hidden", seconds: 10)
phase("open panel", send: "show")
phase("panel open, not typing", seconds: 5)
let typed = phase("typing a round at 80 wpm", send: "type 80") ?? ""
// The keystrokes go through the panel's hidden field: an unfinished round means they never reached it, and accuracy
// under 100 means other keys did (someone typed in the panel during the run).
precondition(typed.contains("accuracy=100 finished=true"), "the round was not typed cleanly, run again without touching the panel: \(typed)")
notes.append("round: \(typed)")
phase("results on screen", seconds: 5)
phase("hide", send: "hide")
phase("idle, hidden after a round", seconds: 10)
input.fileHandleForWriting.closeFile()
app.waitUntilExit()
precondition((try? Data(contentsOf: userHistory)) == historyBefore, "\(userHistory.path) changed during the run (did you finish a round in your own AiberTyper?)")
precondition(!FileManager.default.fileExists(atPath: benchDir), "the app left its temporary history in \(benchDir)")

func mb(_ bytes: UInt64) -> String { String(format: "%.1f", Double(bytes) / 1_048_576) }

// Budgets: the run fails when the app gets heavier than this. A baseline on an M2 is about 0.05% CPU and 2 wakeups/s idle,
// 9% CPU typing and 30 MB. Idle covers the steady phases only: the first one still holds the launch settling down.
let idlePhases: Set = ["panel open, not typing", "results on screen", "idle, hidden after a round"]
let idleCPU = 1.0, idleWakeups = 5.0, typingCPU = 20.0, ramMB = 50.0
var over: [String] = []

let header = ["phase", "s", "CPU avg %", "CPU peak %", "RAM MB", "RAM peak MB", "wakeups/s", "energy mW", "GPU app ms", "WindowServer GPU ms"]
var rows: [[String]] = []
for p in phases {
    let first = p.samples.first!, end = p.samples.last!
    let seconds = max(end.t - first.t, 0.001)
    let peak = zip(p.samples, p.samples.dropFirst()).map { ($1.cpu - $0.cpu) / max($1.t - $0.t, 0.001) }.max() ?? 0
    let cpu = (end.cpu - first.cpu) / seconds * 100, wakeups = Double(end.wakeups - first.wakeups) / seconds
    if idlePhases.contains(p.name), cpu > idleCPU { over.append(String(format: "%@: CPU %.2f%% > %.1f%%", p.name, cpu, idleCPU)) }
    if idlePhases.contains(p.name), wakeups > idleWakeups { over.append(String(format: "%@: %.1f wakeups/s > %.0f", p.name, wakeups, idleWakeups)) }
    if p.name.hasPrefix("typing"), cpu > typingCPU { over.append(String(format: "%@: CPU %.2f%% > %.0f%%", p.name, cpu, typingCPU)) }
    if Double(end.ramPeak) / 1_048_576 > ramMB { over.append("\(p.name): RAM peak \(mb(end.ramPeak)) MB > \(Int(ramMB)) MB") }
    rows.append([p.name, String(format: "%.1f", seconds), String(format: "%.2f", cpu), String(format: "%.1f", peak * 100),
                 mb(end.ram), mb(end.ramPeak), String(format: "%.1f", wakeups),
                 String(format: "%.1f", Double(end.energy - first.energy) / seconds / 1e6),
                 // GPU totals add up live clients, so they drop when one closes: clamp instead of trapping on the subtraction.
                 String(format: "%.1f", max(Double(end.gpu) - Double(first.gpu), 0) / 1e6),
                 String(format: "%.1f", max(Double(end.serverGPU) - Double(first.serverGPU), 0) / 1e6)])
}
print("| " + header.joined(separator: " | ") + " |")
print("|" + header.map { _ in "---" }.joined(separator: "|") + "|")
for row in rows { print("| " + row.joined(separator: " | ") + " |") }
print("")
for note in notes { print("- " + note) }
print("- your history was not touched; the run's temporary history was deleted.")
print("- WindowServer GPU is the whole screen in that phase (every app), not AiberTyper alone.")
print("")
if over.isEmpty {
    print("within budget: idle CPU ≤ \(idleCPU)%, idle wakeups ≤ \(Int(idleWakeups))/s, typing CPU ≤ \(Int(typingCPU))%, RAM peak ≤ \(Int(ramMB)) MB")
} else {
    print("OVER BUDGET:")
    for line in over { print("- " + line) }
    exit(1)
}
