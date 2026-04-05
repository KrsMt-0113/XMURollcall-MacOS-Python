import Foundation
import PythonKit

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
/// All Python calls run on a background thread to avoid blocking the UI.
final class PythonBridge: @unchecked Sendable {
    static let shared = PythonBridge()

    private var loginModule: PythonObject?
    private var monitorModule: PythonObject?
    private var configModule: PythonObject?
    private let scriptPaths: [String]
    private var pythonEnvironmentReady = false

    /// Serial queue for all Python operations (Python GIL is not thread-safe).
    private let pythonQueue = DispatchQueue(label: "com.xmu.rollcall.python", qos: .userInitiated)

    private init() {
        scriptPaths = Self.resolveScriptPaths()
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

    /// Initialize Python runtime state on the dedicated queue thread exactly once.
    private func preparePythonEnvironmentIfNeeded() throws {
        guard !pythonEnvironmentReady else { return }

        let sys = Python.import("sys")
        for path in scriptPaths {
            sys.path.insert(0, PythonObject(path))
        }

        pythonEnvironmentReady = true
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

    /// Build a detailed import failure message for diagnostics.
    private func moduleImportErrorMessage(_ moduleName: String) -> String {
        let pathEntries: [String]
        if let sys = try? Python.attemptImport("sys") {
            pathEntries = Array(sys.path).map { String($0) ?? "<unprintable>" }
        } else {
            pathEntries = ["<unavailable>"]
        }
        return [
            "Unable to import Python module '\(moduleName)'.",
            "Resolved script paths: \(scriptPaths)",
            "sys.path: \(pathEntries)"
        ].joined(separator: " ")
    }

    private func requireConfigModule() throws -> PythonObject {
        try preparePythonEnvironmentIfNeeded()
        if let module = configModule {
            return module
        }
        do {
            let module = try Python.attemptImport("xmu_config")
            configModule = module
            return module
        } catch {
            throw PythonBridgeError.initializationFailed("\(moduleImportErrorMessage("xmu_config")) Python error: \(error)")
        }
    }

    private func requireLoginModule() throws -> PythonObject {
        try preparePythonEnvironmentIfNeeded()
        if let module = loginModule {
            return module
        }
        do {
            let module = try Python.attemptImport("xmu_login")
            loginModule = module
            return module
        } catch {
            throw PythonBridgeError.initializationFailed("\(moduleImportErrorMessage("xmu_login")) Python error: \(error)")
        }
    }

    private func requireMonitorModule() throws -> PythonObject {
        try preparePythonEnvironmentIfNeeded()
        if let module = monitorModule {
            return module
        }
        do {
            let module = try Python.attemptImport("xmu_monitor")
            monitorModule = module
            return module
        } catch {
            throw PythonBridgeError.initializationFailed("\(moduleImportErrorMessage("xmu_monitor")) Python error: \(error)")
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
        let resultJSON: String = try await runOnPythonQueueThrowing {
            let module = try self.requireLoginModule()
            let pyResult = module.login(username, password)
            return String(pyResult) ?? "{}"
        }

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
        let resultJSON: String
        do {
            resultJSON = try await runOnPythonQueueThrowing {
                let module = try self.requireLoginModule()
                let pyResult = module.verify_cookies(cookiesJSON)
                return String(pyResult) ?? "{}"
            }
        } catch {
            return (false, "")
        }

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
        let resultJSON: String = try await runOnPythonQueueThrowing {
            let module = try self.requireMonitorModule()
            let pyResult = module.poll_rollcalls(cookiesJSON)
            return String(pyResult) ?? "{}"
        }

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

        let resultJSON: String = try await runOnPythonQueueThrowing {
            let module = try self.requireMonitorModule()
            let pyResult = module.handle_rollcall(cookiesJSON, rollcallJSON)
            return String(pyResult) ?? "{}"
        }

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
        let resultJSON: String = try await runOnPythonQueueThrowing {
            let module = try self.requireConfigModule()
            let pyResult = module.save_account(nickname, username, password, colorHex)
            return String(pyResult) ?? "{}"
        }

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
        let resultJSON: String
        do {
            resultJSON = try await runOnPythonQueueThrowing {
                let module = try self.requireConfigModule()
                let pyResult = module.load_accounts()
                return String(pyResult) ?? "{}"
            }
        } catch {
            return []
        }

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
        let resultJSON: String = try await runOnPythonQueueThrowing {
            let module = try self.requireConfigModule()
            let pyResult = module.delete_account(accountID)
            return String(pyResult) ?? "{}"
        }

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
        _ = try? await runOnPythonQueueThrowing {
            let module = try self.requireConfigModule()
            let _ = module.save_cookies(accountID, cookiesJSON)
            return ()
        }
    }

    /// Load cached cookies for an account.
    func loadCookies(accountID: String) async -> String? {
        let resultJSON: String
        do {
            resultJSON = try await runOnPythonQueueThrowing {
                let module = try self.requireConfigModule()
                let pyResult = module.load_cookies(accountID)
                return String(pyResult) ?? "{}"
            }
        } catch {
            return nil
        }

        guard let dict = parseJSON(resultJSON),
              let success = dict["success"] as? Bool, success,
              let cookies = dict["cookies"] as? String
        else { return nil }

        return cookies
    }
}
