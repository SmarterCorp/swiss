import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ServicesSettingsView()
                .tabItem { Label("Services", systemImage: "gearshape.2") }

            FeedsSettingsView()
                .tabItem { Label("Feeds", systemImage: "newspaper") }

            PromptsSettingsView()
                .tabItem { Label("Prompts", systemImage: "text.cursor") }

            CleanupSettingsView()
                .tabItem { Label("Cleanup", systemImage: "trash") }

            SleepSettingsView()
                .tabItem { Label("Sleep", systemImage: "moon") }
        }
        .frame(width: 500, height: 400)
    }
}

// MARK: - Services

struct ServicesSettingsView: View {
    @StateObject private var vm = ServicesViewModel()

    var body: some View {
        VStack(alignment: .leading) {
            Text("Services").font(.title2).padding(.bottom, 4)
            List(vm.services, id: \.name) { service in
                HStack {
                    Circle()
                        .fill(service.running ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 10, height: 10)
                    Text(service.name)
                    Spacer()
                    Text(service.running ? "Running" : "Stopped")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .task { await vm.refresh() }
    }
}

@MainActor
class ServicesViewModel: ObservableObject {
    @Published var services: [CLIBridge.ServiceInfo] = []

    func refresh() async {
        let data = await CLIBridge.dashboard()
        services = data.services
    }
}

// MARK: - Feeds

struct FeedsSettingsView: View {
    @State private var feeds = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("RSS Feeds & Twitter").font(.title2).padding(.bottom, 4)
            Text(feeds.isEmpty ? "Loading..." : feeds)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .padding()
        .task {
            let output = await CLIBridge.run(["twitter", "list"])
            feeds = output.isEmpty ? "No feeds configured." : output
        }
    }
}

// MARK: - Prompts

struct PromptsSettingsView: View {
    @State private var prompts = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Text Expansions").font(.title2).padding(.bottom, 4)
            Text(prompts.isEmpty ? "Loading..." : prompts)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .padding()
        .task {
            prompts = await CLIBridge.run(["prompt", "list"])
        }
    }
}

// MARK: - Cleanup

struct CleanupSettingsView: View {
    @State private var scanResult = ""
    @State private var scanning = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("System Cleanup").font(.title2).padding(.bottom, 4)
            if scanning {
                ProgressView("Scanning...")
            } else if scanResult.isEmpty {
                Button("Scan Now") {
                    scanning = true
                    Task {
                        scanResult = await CLIBridge.run(["clean", "--dry-run"])
                        scanning = false
                    }
                }
            } else {
                ScrollView {
                    Text(scanResult)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer()
        }
        .padding()
    }
}

// MARK: - Sleep

struct SleepSettingsView: View {
    @State private var sleepStatus = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Sleep Control").font(.title2).padding(.bottom, 4)
            Text(sleepStatus.isEmpty ? "Loading..." : sleepStatus)
                .font(.system(.body, design: .monospaced))
            Spacer()
        }
        .padding()
        .task {
            sleepStatus = await CLIBridge.run(["sleep", "status"])
        }
    }
}
