import SwiftUI

/// Settings section: opt in to sharing, choose audio, see progress, delete shared data.
struct SubvoxSharingSectionView: View {
  @ObservedObject var sharing = SubvoxSharing.shared
  @State private var confirmDelete = false

  var body: some View {
    Section {
      Text(SubvoxSharing.consentText)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Toggle("Share my dictation data (motion + transcripts)", isOn: $sharing.enabled)
      Toggle("Include audio", isOn: $sharing.includeAudio)
        .disabled(!sharing.enabled)
      HStack {
        Text("\(sharing.uploadedCount) dictations shared")
        if !sharing.status.isEmpty { Text("· \(sharing.status)").foregroundStyle(.secondary) }
        Spacer()
        Button("Delete my shared data", role: .destructive) { confirmDelete = true }
      }
      .font(.callout)
    } header: {
      Text("Help build silent speech")
    } footer: {
      Text("Off by default. Everything stays on this Mac until you turn sharing on.")
    }
    .confirmationDialog("Delete everything shared from this Mac?", isPresented: $confirmDelete) {
      Button("Delete shared data", role: .destructive) { sharing.deleteSharedData() }
    } message: {
      Text("This erases all uploaded dictations on our server and turns sharing off. Your local copies stay.")
    }
  }
}
