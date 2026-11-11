import ComposableArchitecture
import Inject
import SwiftUI
import Sparkle

struct AboutView: View {
    @ObserveInjection var inject
    @Bindable var store: StoreOf<SettingsFeature>
    @State var viewModel = CheckForUpdatesViewModel.shared
    @State private var showingChangelog = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                    Link("Releases", destination: URL(string: "https://github.com/Kahlus-Technologies/subvox-dictate/releases")!)
                }
                HStack {
                    Label("Changelog", systemImage: "doc.text")
                    Spacer()
                    Button("Show Changelog") {
                        showingChangelog.toggle()
                    }
                    .buttonStyle(.bordered)
                    .sheet(isPresented: $showingChangelog, onDismiss: {
                        showingChangelog = false
                    }) {
                        ChangelogView()
                    }
                }
                HStack {
                    Label("Subvox Dictate is open source", systemImage: "apple.terminal.on.rectangle")
                    Spacer()
                    Link("Visit our GitHub", destination: URL(string: "https://github.com/Kahlus-Technologies/subvox-dictate")!)
                }
                HStack {
                    Label("Built on Hex by Kit Langton (MIT)", systemImage: "heart")
                    Spacer()
                    Link("Hex on GitHub", destination: URL(string: "https://github.com/kitlangton/Hex")!)
                }
            }
        }
        .formStyle(.grouped)
        .enableInjection()
    }
}
