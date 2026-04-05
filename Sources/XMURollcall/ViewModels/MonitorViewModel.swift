import SwiftUI
import Foundation

/// Connection status of the monitor.
enum ConnectionStatus: Equatable, Sendable {
    case connected
    case disconnected
    case connecting

    var text: String {
        switch self {
        case .connected:    return "connected"
        case .disconnected: return "disconnected"
        case .connecting:   return "trying to connect..."
        }
    }

    var color: Color {
        switch self {
        case .connected:    return .green
        case .disconnected: return .red
        case .connecting:   return .yellow
        }
    }
}

/// View model for the Monitor view that handles polling and rollcall answering.
@MainActor
@Observable
final class MonitorViewModel {
    // Display state
    var currentTime: String = ""
    var runningTime: String = "00:00:00"
    var status: ConnectionStatus = .connecting
    var records: [RollcallRecord] = []
    var isPolling: Bool = false

    // Account info
    private(set) var account: Account
    private var cookiesJSON: String = ""

    // Internal state
    private var startDate: Date = Date()
    private var clockTimer: Timer?
    private var pollTimer: Timer?
    private var knownRollcallIDs: Set<Int> = []
    private let bridge = PythonBridge.shared

    init(account: Account) {
        self.account = account
        self.cookiesJSON = account.cookiesJSON ?? ""
    }

    /// Start the monitoring session: login if needed, then begin polling.
    func start() {
        startDate = Date()
        isPolling = true
        status = .connecting
        startClockTimer()

        Task {
            await ensureLoggedIn()
            startPollTimer()
        }
    }

    /// Stop polling but keep the session alive.
    func stop() {
        isPolling = false
        pollTimer?.invalidate()
        pollTimer = nil
        status = .disconnected
    }

    /// Resume polling after a stop.
    func resume() {
        isPolling = true
        status = .connecting
        startPollTimer()
    }

    /// Fully clean up timers when leaving the monitor view.
    func cleanup() {
        stop()
        clockTimer?.invalidate()
        clockTimer = nil
    }

    // MARK: - Private: Login

    private func ensureLoggedIn() async {
        // Try cached cookies first
        if !cookiesJSON.isEmpty {
            let verification = await bridge.verifyCookies(cookiesJSON: cookiesJSON)
            if verification.valid {
                status = .connected
                return
            }
        }

        // Try loading from config cache
        if let cached = await bridge.loadCookies(accountID: account.id) {
            let verification = await bridge.verifyCookies(cookiesJSON: cached)
            if verification.valid {
                cookiesJSON = cached
                status = .connected
                return
            }
        }

        // Re-login
        do {
            let result = try await bridge.login(username: account.username, password: account.password)
            if result.success {
                cookiesJSON = result.cookies
                await bridge.saveCookies(accountID: account.id, cookiesJSON: cookiesJSON)
                status = .connected
            } else {
                status = .disconnected
            }
        } catch {
            status = .disconnected
        }
    }

    // MARK: - Private: Clock Timer

    private func startClockTimer() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        // Update immediately
        currentTime = formatter.string(from: Date())
        updateRunningTime()

        clockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = formatter.string(from: Date())
                self.updateRunningTime()
            }
        }
    }

    private func updateRunningTime() {
        let elapsed = Int(Date().timeIntervalSince(startDate))
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        runningTime = String(format: "%02d:%02d:%02d", h, m, s)
    }

    // MARK: - Private: Poll Timer

    private func startPollTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPolling else { return }
                await self.performPoll()
            }
        }
        // Also fire immediately
        Task {
            await performPoll()
        }
    }

    private func performPoll() async {
        guard isPolling, !cookiesJSON.isEmpty else { return }

        do {
            let rollcalls = try await bridge.pollRollcalls(cookiesJSON: cookiesJSON)

            if status != .connected {
                status = .connected
            }

            // Process any new rollcalls
            for rc in rollcalls where !knownRollcallIDs.contains(rc.rollcallID) && !rc.isExpired {
                knownRollcallIDs.insert(rc.rollcallID)
                await handleNewRollcall(rc)
            }

        } catch {
            // Check if session expired
            let errorMsg = error.localizedDescription
            if errorMsg.contains("expired") || errorMsg.contains("401") {
                status = .connecting
                await ensureLoggedIn()
                if status == .connected {
                    return // Will retry on next timer tick
                }
            }
            status = .disconnected
        }
    }

    // MARK: - Private: Rollcall Handling

    private func handleNewRollcall(_ data: RollcallData) async {
        // Add a record in "trying" state
        let record = RollcallRecord(
            id: "\(data.rollcallID)",
            time: Date(),
            courseName: data.courseTitle,
            rollcallType: data.type,
            result: data.type == .qrcode ? .qrcode : .trying
        )
        records.insert(record, at: 0)

        guard data.type != .qrcode else { return }

        // Already answered check
        if data.status == "on_call_fine" {
            updateRecordResult(id: record.id, result: .success("Already answered"))
            return
        }

        // Attempt to answer
        do {
            let result = try await bridge.handleRollcall(cookiesJSON: cookiesJSON, rollcallData: data)
            if result.success {
                updateRecordResult(id: record.id, result: .success(result.result))
            } else {
                updateRecordResult(id: record.id, result: .failed(""))
            }
        } catch {
            // First failure — retry once
            updateRecordResult(id: record.id, result: .retrying)
            do {
                let result = try await bridge.handleRollcall(cookiesJSON: cookiesJSON, rollcallData: data)
                if result.success {
                    updateRecordResult(id: record.id, result: .success(result.result))
                } else {
                    updateRecordResult(id: record.id, result: .failed(error.localizedDescription))
                }
            } catch {
                updateRecordResult(id: record.id, result: .failed(error.localizedDescription))
            }
        }
    }

    private func updateRecordResult(id: String, result: RollcallResult) {
        if let idx = records.firstIndex(where: { $0.id == id }) {
            records[idx].result = result
        }
    }
}
