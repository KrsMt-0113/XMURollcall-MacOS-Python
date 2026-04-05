import Foundation

/// Errors that can occur during Python bridge operations.
enum PythonBridgeError: Error, LocalizedError {
    case initializationFailed(String)
    case loginFailed(String)
    case monitorFailed(String)
    case verifyFailed(String)
    case configFailed(String)
    case jsonParsingFailed

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let msg): return "Python init failed: \(msg)"
        case .loginFailed(let msg):          return "Login failed: \(msg)"
        case .monitorFailed(let msg):        return "Monitor failed: \(msg)"
        case .verifyFailed(let msg):         return "Verify failed: \(msg)"
        case .configFailed(let msg):         return "Config failed: \(msg)"
        case .jsonParsingFailed:             return "JSON parsing failed"
        }
    }
}

/// Bridge between Swift UI layer and Python business logic scripts.
/// Python is executed in a child process to isolate interpreter crashes from the app.
final class PythonBridge: @unchecked Sendable {
    static let shared = PythonBridge()

    private let scriptPaths: [String]
    private let runnerScriptPath: String
    private let pythonExecutablePath: String

    /// Serial queue for child process execution.
    private let pythonQueue = DispatchQueue(label: "com.xmu.rollcall.python", qos: .userInitiated)

    private init() {
        scriptPaths = Self.resolveScriptPaths()
        runnerScriptPath = Self.resolveRunnerScriptPath(from: scriptPaths)
        pythonExecutablePath = Self.resolvePythonExecutablePath()
    }

    // MARK: - Private Helpers

    /// Run a throwing closure on the Python serial queue and return the result.
    private func runOnPythonQueueThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            pythonQueue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Build candidate `python_scripts` search paths for app and development runs.
    private static func resolveScriptPaths() -> [String] {
        var paths: [String] = []
        let fileManager = FileManager.default

        if let resourcePath = Bundle.main.resourcePath {
            paths.append(resourcePath + "/python_scripts")
        }

        if let executablePath = Bundle.main.executableURL?.deletingLastPathComponent().path {
            paths.append(executablePath + "/XMURollcall_XMURollcall.bundle/python_scripts")
        }

        // Keep stable ordering, de-duplicate, and only keep existing directories.
        var seen = Set<String>()
        return paths.filter { path in
            guard !seen.contains(path) else { return false }
            seen.insert(path)
            var isDir: ObjCBool = false
            return fileManager.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    private static func resolveRunnerScriptPath(from scriptPaths: [String]) -> String {
        for path in scriptPaths {
            let candidate = path + "/xmu_runner.py"
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return ""
    }

    private static func resolvePythonExecutablePath() -> String {
        if let override = ProcessInfo.processInfo.environment["XMU_ROLLCALL_PYTHON"],
           FileManager.default.isExecutableFile(atPath: override) {
            return override
        }

        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return ""
    }

    private func runPython(module: String, function: String, arguments: [String]) async throws -> String {
        guard !runnerScriptPath.isEmpty else {
            throw PythonBridgeError.initializationFailed(
                "Missing runner script xmu_runner.py. Resolved script paths: \(scriptPaths)"
            )
        }
        guard !pythonExecutablePath.isEmpty else {
            throw PythonBridgeError.initializationFailed(
                "No usable python3 executable found. Tried env XMU_ROLLCALL_PYTHON, /opt/homebrew/bin/python3, /usr/local/bin/python3, /usr/bin/python3"
            )
        }

        let argsJSONData = try JSONSerialization.data(withJSONObject: arguments, options: [])
        guard let argsJSON = String(data: argsJSONData, encoding: .utf8) else {
            throw PythonBridgeError.jsonParsingFailed
        }

        return try await runOnPythonQueueThrowing {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: self.pythonExecutablePath)
            process.arguments = [self.runnerScriptPath, module, function, argsJSON]

            // Ensure bundled scripts are importable by child Python.
            var env = ProcessInfo.processInfo.environment
            let joinedPaths = self.scriptPaths.joined(separator: ":")
            if let existing = env["PYTHONPATH"], !existing.isEmpty {
                env["PYTHONPATH"] = joinedPaths + ":" + existing
            } else {
                env["PYTHONPATH"] = joinedPaths
            }
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try process.run()
            process.waitUntilExit()

            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let err = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard process.terminationStatus == 0 else {
                throw PythonBridgeError.initializationFailed(
                    "Python process failed (status \(process.terminationStatus)). module=\(module), function=\(function), stderr=\(err)"
                )
            }

            if out.isEmpty {
                throw PythonBridgeError.initializationFailed(
                    "Python process returned empty output. module=\(module), function=\(function), stderr=\(err)"
                )
            }

            return out
        }
    }

    private func runPythonIgnoringErrors(module: String, function: String, arguments: [String], fallback: String) async -> String {
        do {
            return try await runPython(module: module, function: function, arguments: arguments)
        } catch {
            return fallback
        }
    }

    /// Parse a JSON string into a dictionary.
    private func parseJSON(_ jsonString: String) -> [String: Any]? {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return dict
    }

    // MARK: - Login

    /// Verify credentials by logging in to TronClass.
    /// Returns (success, cookiesJSON, displayName).
    func login(username: String, password: String) async throws -> (success: Bool, cookies: String, name: String) {
        let resultJSON = try await runPython(
            module: "xmu_login",
            function: "login",
            arguments: [username, password]
        )

        guard let dict = parseJSON(resultJSON) else {
            throw PythonBridgeError.jsonParsingFailed
        }

        let success = dict["success"] as? Bool ?? false
        if success {
            let cookies = dict["cookies"] as? String ?? ""
            let name = dict["name"] as? String ?? ""
            return (true, cookies, name)
        } else {
            let error = dict["error"] as? String ?? "Unknown error"
            throw PythonBridgeError.loginFailed(error)
        }
    }

    /// Verify if cached cookies are still valid.
    func verifyCookies(cookiesJSON: String) async -> (valid: Bool, name: String) {
        let resultJSON = await runPythonIgnoringErrors(
            module: "xmu_login",
            function: "verify_cookies",
            arguments: [cookiesJSON],
            fallback: "{}"
        )

        guard let dict = parseJSON(resultJSON) else {
            return (false, "")
        }

        let valid = dict["valid"] as? Bool ?? false
        let name = dict["name"] as? String ?? ""
        return (valid, name)
    }

    // MARK: - Monitor

    /// Single-shot poll for active rollcalls.
    func pollRollcalls(cookiesJSON: String) async throws -> [RollcallData] {
        let resultJSON = try await runPython(
            module: "xmu_monitor",
            function: "poll_rollcalls",
            arguments: [cookiesJSON]
        )

        guard let dict = parseJSON(resultJSON) else {
            throw PythonBridgeError.jsonParsingFailed
        }

        let success = dict["success"] as? Bool ?? false
        if !success {
            let error = dict["error"] as? String ?? "Unknown monitor error"
            throw PythonBridgeError.monitorFailed(error)
        }

        guard let rollcallsArray = dict["rollcalls"] as? [[String: Any]] else {
            return []
        }

        return rollcallsArray.map { rc in
            RollcallData(
                rollcallID: rc["rollcall_id"] as? Int ?? 0,
                courseTitle: rc["course_title"] as? String ?? "",
                createdByName: rc["created_by_name"] as? String ?? "",
                departmentName: rc["department_name"] as? String ?? "",
                isExpired: rc["is_expired"] as? Bool ?? false,
                isNumber: rc["is_number"] as? Bool ?? false,
                isRadar: rc["is_radar"] as? Bool ?? false,
                rollcallStatus: rc["rollcall_status"] as? String ?? "",
                scored: rc["scored"] as? Int ?? 0,
                status: rc["status"] as? String ?? ""
            )
        }
    }

    /// Handle a single rollcall (dispatch to number brute-force or radar triangulation).
    func handleRollcall(cookiesJSON: String, rollcallData: RollcallData) async throws -> (success: Bool, type: String, result: String) {
        let rollcallJSON = rollcallData.jsonString

        let resultJSON = try await runPython(
            module: "xmu_monitor",
            function: "handle_rollcall",
            arguments: [cookiesJSON, rollcallJSON]
        )

        guard let dict = parseJSON(resultJSON) else {
            throw PythonBridgeError.jsonParsingFailed
        }

        let success = dict["success"] as? Bool ?? false
        let type = dict["type"] as? String ?? "unknown"
        let result = dict["result"] as? String ?? ""

        if !success {
            let error = dict["error"] as? String ?? "Unknown error"
            throw PythonBridgeError.verifyFailed(error)
        }

        return (success, type, result)
    }

    // MARK: - Config

    /// Save a new account to persistent config.
    func saveAccount(nickname: String, username: String, password: String, colorHex: String) async throws -> String {
        let resultJSON = try await runPython(
            module: "xmu_config",
            function: "save_account",
            arguments: [nickname, username, password, colorHex]
        )

        guard let dict = parseJSON(resultJSON) else {
            throw PythonBridgeError.jsonParsingFailed
        }

        let success = dict["success"] as? Bool ?? false
        if success {
            return dict["account_id"] as? String ?? ""
        } else {
            let error = dict["error"] as? String ?? "Save failed"
            throw PythonBridgeError.configFailed(error)
        }
    }

    /// Load all saved accounts from config.
    func loadAccounts() async -> [Account] {
        let resultJSON = await runPythonIgnoringErrors(
            module: "xmu_config",
            function: "load_accounts",
            arguments: [],
            fallback: "{}"
        )

        guard let dict = parseJSON(resultJSON),
              let success = dict["success"] as? Bool, success,
              let accountsArray = dict["accounts"] as? [[String: Any]]
        else { return [] }

        return accountsArray.compactMap { acc in
            guard let id = acc["id"] as? String,
                  let nickname = acc["nickname"] as? String,
                  let username = acc["username"] as? String,
                  let password = acc["password"] as? String,
                  let colorHex = acc["color_hex"] as? String
            else { return nil }

            return Account(
                id: id,
                nickname: nickname,
                username: username,
                password: password,
                colorHex: colorHex
            )
        }
    }

    /// Delete an account by ID.
    func deleteAccount(accountID: String) async throws {
        let resultJSON = try await runPython(
            module: "xmu_config",
            function: "delete_account",
            arguments: [accountID]
        )

        guard let dict = parseJSON(resultJSON) else {
            throw PythonBridgeError.jsonParsingFailed
        }

        let success = dict["success"] as? Bool ?? false
        if !success {
            let error = dict["error"] as? String ?? "Delete failed"
            throw PythonBridgeError.configFailed(error)
        }
    }

    /// Save session cookies for an account.
    func saveCookies(accountID: String, cookiesJSON: String) async {
        _ = await runPythonIgnoringErrors(
            module: "xmu_config",
            function: "save_cookies",
            arguments: [accountID, cookiesJSON],
            fallback: "{}"
        )
    }

    /// Load cached cookies for an account.
    func loadCookies(accountID: String) async -> String? {
        let resultJSON = await runPythonIgnoringErrors(
            module: "xmu_config",
            function: "load_cookies",
            arguments: [accountID],
            fallback: "{}"
        )

        guard let dict = parseJSON(resultJSON),
              let success = dict["success"] as? Bool, success,
              let cookies = dict["cookies"] as? String
        else { return nil }

        return cookies
    }
}
