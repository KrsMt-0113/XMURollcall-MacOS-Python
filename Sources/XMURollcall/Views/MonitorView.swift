import SwiftUI

/// The main monitoring view showing live status, rollcall records, and controls.
struct MonitorView: View {
    @Environment(AppViewModel.self) private var appViewModel
    @State private var viewModel: MonitorViewModel

    init(account: Account) {
        _viewModel = State(initialValue: MonitorViewModel(account: account))
    }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 16) {
                // Top: Status panel
                statusPanel
                    .padding(.top, 16)

                // Middle: Records table
                recordsTable

                // Bottom: Control buttons
                controlButtons
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            viewModel.start()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Status Panel

    private var statusPanel: some View {
        VStack(spacing: 10) {
            HStack {
                Text("XMU Rollcall Monitor")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
            }

            Divider()
                .opacity(0.3)

            // Current Time
            statusRow(
                label: "Current Time",
                value: viewModel.currentTime,
                valueFont: .system(size: 14, weight: .medium, design: .monospaced)
            )

            // Running Time
            statusRow(
                label: "Running Time",
                value: viewModel.runningTime,
                valueFont: .system(size: 14, weight: .medium, design: .monospaced)
            )

            // Status
            HStack {
                Text("Status")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.status.color)
                        .frame(width: 8, height: 8)
                    Text(viewModel.status.text)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(viewModel.status.color)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func statusRow(label: String, value: String, valueFont: Font) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(valueFont)
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Records Table

    private var recordsTable: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                tableHeaderCell("Time", width: 70, alignment: .leading)
                tableHeaderCell("Course", width: nil, alignment: .leading)
                tableHeaderCell("Type", width: 70, alignment: .center)
                tableHeaderCell("Result", width: 100, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
                .opacity(0.3)

            // Scrollable records
            ScrollView {
                LazyVStack(spacing: 0) {
                    if viewModel.records.isEmpty {
                        emptyStateRow
                    } else {
                        ForEach(viewModel.records) { record in
                            recordRow(record)
                            Divider()
                                .opacity(0.15)
                        }
                    }
                }
            }
            .frame(minHeight: 120)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private func tableHeaderCell(_ text: String, width: CGFloat?, alignment: Alignment) -> some View {
        Group {
            if let width {
                Text(text)
                    .frame(width: width, alignment: alignment)
            } else {
                Text(text)
                    .frame(maxWidth: .infinity, alignment: alignment)
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.secondary)
    }

    private var emptyStateRow: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("Monitoring for rollcalls...")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 32)
            Spacer()
        }
    }

    private func recordRow(_ record: RollcallRecord) -> some View {
        HStack(spacing: 0) {
            // Time
            Text(record.timeString)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 70, alignment: .leading)

            // Course name
            Text(record.courseName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Type
            Text(record.rollcallType.displayName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .center)

            // Result
            resultCell(record.result)
                .frame(width: 100, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func resultCell(_ result: RollcallResult) -> some View {
        switch result {
        case .trying:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text(result.displayText)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(result.color)
            }
        default:
            Text(result.displayText)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(result.color)
                .lineLimit(1)
        }
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: 16) {
            // Start / Stop toggle button
            Button {
                if viewModel.isPolling {
                    viewModel.stop()
                } else {
                    viewModel.resume()
                }
            } label: {
                Text(viewModel.isPolling ? "stop" : "start")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular.tint(viewModel.isPolling ? .red : .green).interactive(),
                in: .capsule
            )

            // Quit button
            Button {
                viewModel.cleanup()
                appViewModel.navigate(to: .accountSelection)
            } label: {
                Text("quit")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular.tint(.black.opacity(0.6)).interactive(),
                in: .capsule
            )
            .disabled(viewModel.isPolling)
            .opacity(viewModel.isPolling ? 0.4 : 1.0)
        }
    }
}
