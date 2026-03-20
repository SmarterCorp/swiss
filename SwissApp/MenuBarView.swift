import SwiftUI

struct MenuBarView: View {
    var onOpenSettings: () -> Void = {}
    @StateObject private var viewModel = MenuBarViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Swiss").font(.headline)
                Spacer()
                Text("v1.4").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // System section
            VStack(alignment: .leading, spacing: 6) {
                systemRow("Battery", viewModel.system.battery)
                systemRow("Network", viewModel.system.network)
                systemRow("Disk", viewModel.system.disk)
                systemRow("Sleep", viewModel.system.sleep)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Services
            VStack(alignment: .leading, spacing: 6) {
                Text("Services").font(.caption).foregroundColor(.secondary)
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                ], spacing: 4) {
                    ForEach(viewModel.services, id: \.name) { service in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(service.running ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text(service.name)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Quick actions
            VStack(spacing: 2) {
                actionButton("Open RSS", icon: "newspaper.fill") {
                    Task { await CLIBridge.run(["rss"]) }
                }
                actionButton("Clean System", icon: "trash.fill") {
                    Task {
                        let script = "tell application \"Terminal\" to do script \"/usr/local/bin/swiss clean\""
                        let p = Process()
                        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                        p.arguments = ["-e", script]
                        try? p.run()
                    }
                }
                actionButton("Update All", icon: "arrow.triangle.2.circlepath") {
                    Task {
                        let script = "tell application \"Terminal\" to do script \"/usr/local/bin/swiss maintain\""
                        let p = Process()
                        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                        p.arguments = ["-e", script]
                        try? p.run()
                    }
                }
            }
            .padding(.vertical, 6)

            Divider()

            // Footer
            HStack {
                Button("Settings...") {
                    onOpenSettings()
                }
                .buttonStyle(.plain)
                .font(.caption)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 360)
        .task {
            await viewModel.refresh()
        }
    }

    private func systemRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(1)
            Spacer()
        }
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

@MainActor
class MenuBarViewModel: ObservableObject {
    @Published var system = CLIBridge.SystemInfo(battery: "...", network: "...", displays: "...", disk: "...", sleep: "...")
    @Published var services: [CLIBridge.ServiceInfo] = []

    func refresh() async {
        let data = await CLIBridge.dashboard()
        system = data.system
        services = data.services
    }
}
