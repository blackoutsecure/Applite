import Foundation
import Darwin

@main
enum SingleInstanceTests {
    @MainActor
    static func main() throws {
        if CommandLine.arguments.count == 3 {
            let lock = try SingleInstanceLock(at: URL(fileURLWithPath: CommandLine.arguments[2]))
            if CommandLine.arguments[1] == "--exit-with-lock" {
                precondition(lock.isPrimary)
                _exit(0)
            }
            FileHandle.standardOutput.write(Data((lock.isPrimary ? "primary\n" : "secondary\n").utf8))
            if lock.isPrimary {
                withExtendedLifetime(lock) {
                    _ = FileHandle.standardInput.readDataToEndOfFile()
                }
            }
            return
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try! FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("instance.lock")

        var owner: SingleInstanceLock? = try SingleInstanceLock(at: url)
        precondition(owner!.isPrimary)
        let contender = try SingleInstanceLock(at: url)
        precondition(!contender.isPrimary)
        owner = nil
        let successor = try SingleInstanceLock(at: url)
        precondition(successor.isPrimary, "Closing the owner must release the lock without deleting its file")
        withExtendedLifetime((contender, successor)) {}

        let raceURL = root.appendingPathComponent("race.lock")
        let first = try startChild(mode: "--hold", url: raceURL)
        let second = try startChild(mode: "--hold", url: raceURL)
        let outcomes = [first, second].map {
            String(decoding: $0.output.fileHandleForReading.availableData, as: UTF8.self)
        }
        precondition(outcomes.filter { $0 == "primary\n" }.count == 1)
        precondition(outcomes.filter { $0 == "secondary\n" }.count == 1)
        for child in [first, second] {
            try child.input.fileHandleForWriting.close()
            child.process.waitUntilExit()
            precondition(child.process.terminationStatus == 0)
        }
        let afterRace = try SingleInstanceLock(at: raceURL)
        precondition(afterRace.isPrimary)

        let exitURL = root.appendingPathComponent("exit.lock")
        let exiting = try startChild(mode: "--exit-with-lock", url: exitURL)
        exiting.process.waitUntilExit()
        precondition(exiting.process.terminationStatus == 0)
        let afterExit = try SingleInstanceLock(at: exitURL)
        precondition(afterExit.isPrimary, "The OS must release the lock even without running deinit")

        let staleURL = root.appendingPathComponent("stale.lock")
        try Data("stale process data".utf8).write(to: staleURL)
        let stale = try SingleInstanceLock(at: staleURL)
        precondition(stale.isPrimary, "A leftover file must not block launch")

        do {
            _ = try SingleInstanceLock(at: root.appendingPathComponent("missing/instance.lock"))
            preconditionFailure("An inaccessible lock path must fail closed")
        } catch let error as NSError {
            precondition(error.domain == NSPOSIXErrorDomain)
        }

        let settings = SettingsNavigation()
        settings.selection = .brew
        var focusRequests = 0
        let focusSettings = {
            precondition(settings.selection == .uninstall, "Select Uninstall before opening or focusing Settings")
            focusRequests += 1
        }
        settings.showUninstall(openSettings: focusSettings)
        settings.showUninstall(openSettings: focusSettings)
        precondition(focusRequests == 2, "Repeated Uninstall requests must still focus the existing Settings window")
        settings.selection = .general
        settings.showUninstall(openSettings: focusSettings)
        precondition(focusRequests == 3)

        print("PASS: single-instance ownership, concurrent processes, release, abrupt exit, stale files, I/O errors, and repeated Uninstall routing")
    }

    private static func startChild(mode: String, url: URL) throws -> (process: Process, input: Pipe, output: Pipe) {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = [mode, url.path]
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        return (process, input, output)
    }
}
