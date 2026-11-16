import Foundation
import Apply
import Model

/// PCOptopusHelper — privileged allowlist for pmset only.
/// Usage:
///   PCOptopusHelper set-pmset --flag -c --key sleep --value 30 [--kill-switch]
/// Exit codes: 0 ok, 2 kill switch, 3 refused key, 4 failure

@main
enum PCOptopusHelperMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            fputs("usage: PCOptopusHelper set-pmset --flag -c|--b --key KEY --value N [--kill-switch]\n", stderr)
            exit(4)
        }

        if command == "set-pmset" {
            let parsed = parseFlags(Array(args.dropFirst()))
            if parsed["kill-switch"] == "true" {
                fputs("kill switch engaged\n", stderr)
                exit(2)
            }
            guard let flag = parsed["flag"],
                  let key = parsed["key"],
                  let valueString = parsed["value"],
                  let value = Int(valueString) else {
                fputs("missing flag/key/value\n", stderr)
                exit(4)
            }
            switch PmsetAllowlist.validate(key: key, powerSource: flag, value: value) {
            case .failure(let error):
                fputs("\(error.localizedDescription)\n", stderr)
                exit(3)
            case .success(let validated):
                do {
                    let runner = ProcessRunner()
                    _ = try runner.run("/usr/bin/pmset", arguments: [
                        validated.flag, validated.key, String(validated.value)
                    ])
                    print("ok \(validated.flag) \(validated.key) \(validated.value)")
                    exit(0)
                } catch {
                    fputs("\(error.localizedDescription)\n", stderr)
                    exit(4)
                }
            }
        }

        fputs("unknown command \(command)\n", stderr)
        exit(4)
    }

    static func parseFlags(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg == "--kill-switch" {
                result["kill-switch"] = "true"
                i += 1
                continue
            }
            if arg.hasPrefix("--"), i + 1 < args.count {
                let key = String(arg.dropFirst(2))
                result[key] = args[i + 1]
                i += 2
                continue
            }
            i += 1
        }
        return result
    }
}
