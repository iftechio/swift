import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif
import Logger

// MARK: - DangerRunner

final class DangerRunner {
    let logger: Logger
    let dsl: DangerDSL
    var results = DangerResults()
    static var shared: DangerRunner!

    init(dslJSONArg: String, outputJSONPath: String) {
        let isVerbose = CommandLine.arguments.contains("--verbose")
            || (ProcessInfo.processInfo.environment["DEBUG"] != nil)
        let isSilent = CommandLine.arguments.contains("--silent")
        logger = Logger(isVerbose: isVerbose, isSilent: isSilent)
        logger.debug("Ran with: \(CommandLine.arguments.joined(separator: " "))")

        let cliLength = CommandLine.arguments.count

        guard cliLength - 2 > 0 else {
            logger.logError("To execute Danger run danger-swift ci, " +
                "danger-swift pr or danger-swift local on your terminal")
            exit(1)
        }

        do {
            guard let data = dslJSONArg.data(using: .utf8) else {
                exit(1)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(DateFormatter.defaultDateFormatter)
            logger.debug("Decoding the DSL into Swift types")
            dsl = try decoder.decode(DSL.self, from: data).danger
        } catch {
            logger.logError("Failed to parse JSON:", error)
            exit(1)
        }

        logger.debug("Setting up to dump results")
        dumpResultsAtExit(self, path: outputJSONPath)
    }
}

// MARK: - Public Functions

// swiftlint:disable:next identifier_name
public func Danger(dslJSONArg: String, outputJSONPath: String) -> DangerDSL {
    DangerRunner.shared = DangerRunner(dslJSONArg: dslJSONArg, outputJSONPath: outputJSONPath)
    return DangerRunner.shared!.dsl
}

// MARK: - Private Functions

private var dumpInfo: (danger: DangerRunner, path: String)?

private func dumpResultsAtExit(_ runner: DangerRunner, path: String) {
    func dump() {
        guard let dumpInfo = dumpInfo else { return }
        dumpInfo.danger.logger.debug("Sending results back to Danger")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(dumpInfo.danger.results)

            if !FileManager.default.createFile(atPath: dumpInfo.path,
                                               contents: data,
                                               attributes: nil) {
                dumpInfo.danger.logger.logError("Could not create a temporary file " +
                    "for the Dangerfile DSL at: \(dumpInfo.path)")
                exit(0)
            }

        } catch {
            dumpInfo.danger.logger.logError("Failed to generate result JSON:", error)
            exit(1)
        }
    }
    dumpInfo = (runner, path)
    atexit(dump)
}
