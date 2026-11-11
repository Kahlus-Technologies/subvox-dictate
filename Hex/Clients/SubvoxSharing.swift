import Foundation
import os.log

/// Opt-in sharing of Subvox sessions with the Kahlus research backend (Convex). No accounts: a random
/// install ID groups one person's sessions. Nothing is uploaded until the user agrees in Settings.
///
/// Each saved session is zipped (motion.csv, words.json, meta.json, plus audio.wav only if the user chose
/// to share audio) and sent in two steps: get a one-time upload URL, POST the zip, then register it.
/// Pending sessions are just session folders without an `.uploaded` marker, so a failed or interrupted
/// upload is retried on the next save or launch. Nothing is lost if the Mac sleeps or the app quits.
@MainActor
final class SubvoxSharing: ObservableObject {
  static let shared = SubvoxSharing()
  static let consentVersion = 1
  /// Production deployment; SUBVOX_BACKEND overrides it for testing against the dev deployment.
  nonisolated static let backend = URL(string: ProcessInfo.processInfo.environment["SUBVOX_BACKEND"]
    ?? "https://honorable-manatee-356.convex.cloud")!
  /// Shown in Settings; bump `consentVersion` (here and in backend/convex/uploads.ts) when it changes.
  static let consentText = """
    Help build silent speech. If you opt in, Subvox Dictate uploads each dictation's AirPods head motion, \
    its transcript with word timings, and basic details (length, microphone, which app you dictated into) \
    to Kahlus Technologies, to train a model that reads speech from jaw movement. Audio is uploaded only if \
    you also turn on "Include audio". Data is linked to a random ID on this Mac, not your name or email. \
    You can stop sharing at any time, and "Delete my shared data" erases everything uploaded from this Mac.
    """

  private let defaults = UserDefaults.standard
  private let log = Logger(subsystem: "com.kahlus.subvox.dictate", category: "Sharing")
  private var uploading = false

  @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "subvox.share.enabled"); if enabled { register() } } }
  @Published var includeAudio: Bool { didSet { defaults.set(includeAudio, forKey: "subvox.share.audio"); if enabled { register() } } }
  @Published private(set) var status = ""
  @Published private(set) var uploadedCount = 0

  let installId: String

  private init() {
    if let id = defaults.string(forKey: "subvox.installId") { installId = id } else {
      installId = UUID().uuidString.lowercased()
      defaults.set(installId, forKey: "subvox.installId")
    }
    let agreedVersion = defaults.integer(forKey: "subvox.share.consentVersion")
    enabled = defaults.bool(forKey: "subvox.share.enabled") && agreedVersion == Self.consentVersion
    includeAudio = defaults.bool(forKey: "subvox.share.audio")
    uploadedCount = Self.sessionDirs().filter { Self.isUploaded($0) }.count
  }

  /// Record consent on the server, then flush anything pending.
  private func register() {
    defaults.set(Self.consentVersion, forKey: "subvox.share.consentVersion")
    let args: [String: Any] = ["installId": installId, "consentVersion": Self.consentVersion, "shareAudio": includeAudio,
                               "appVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"]
    Task {
      do {
        _ = try await Self.call("mutation", "uploads:consent", args)
        status = "Sharing on"
        uploadPending()
      } catch { status = "Couldn't reach server: \(error.localizedDescription)" }
    }
  }

  /// Upload every finished session not yet sent. Safe to call often; runs one pass at a time.
  func uploadPending() {
    guard enabled, !uploading else { return }
    uploading = true
    let audio = includeAudio, id = installId
    Task.detached(priority: .utility) {
      var sent = 0, failed = 0
      for dir in Self.sessionDirs() where !Self.isUploaded(dir) {
        do { try await Self.upload(dir, installId: id, includeAudio: audio); sent += 1 } catch {
          failed += 1
          Logger(subsystem: "com.kahlus.subvox.dictate", category: "Sharing")
            .error("Upload failed for \(dir.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
          if "\(error)".contains("consent") || "\(error)".contains("limit") { break }  // retrying won't help now
        }
      }
      let (s, f) = (sent, failed)
      await MainActor.run {
        self.uploading = false
        self.uploadedCount = Self.sessionDirs().filter { Self.isUploaded($0) }.count
        if s + f > 0 { self.status = f == 0 ? "Uploaded \(s) new" : "Uploaded \(s), \(f) will retry later" }
      }
    }
  }

  /// Erase everything uploaded from this Mac and turn sharing off. Local sessions stay on disk.
  func deleteSharedData() {
    Task {
      do {
        let r = try await Self.call("mutation", "uploads:deleteMyData", ["installId": installId])
        enabled = false
        for dir in Self.sessionDirs() { try? FileManager.default.removeItem(at: dir.appending(path: ".uploaded")) }
        uploadedCount = 0
        status = "Deleted \((r as? [String: Any])?["deletedSessions"] ?? 0) shared sessions from the server"
      } catch { status = "Delete failed, try again: \(error.localizedDescription)" }
    }
  }

  // MARK: - Work (off the main actor)

  nonisolated static func sessionDirs() -> [URL] {
    let fm = FileManager.default
    let all = (try? fm.contentsOfDirectory(at: SubvoxCapture.root, includingPropertiesForKeys: nil)) ?? []
    // Only finished Dictate sessions: meta.json is written last, so its presence means the folder is complete.
    return all.filter { $0.lastPathComponent.hasSuffix("-dictation") && fm.fileExists(atPath: $0.appending(path: "meta.json").path) }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  nonisolated static func isUploaded(_ dir: URL) -> Bool {
    FileManager.default.fileExists(atPath: dir.appending(path: ".uploaded").path)
  }

  nonisolated static func upload(_ dir: URL, installId: String, includeAudio: Bool) async throws {
    let meta = (try? JSONSerialization.jsonObject(with: Data(contentsOf: dir.appending(path: "meta.json")))) as? [String: Any] ?? [:]
    let words = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: dir.appending(path: "words.json")))) as? [String: Any])?["words"] as? [Any]
    var files = ["motion.csv", "words.json", "meta.json", "words.app.json", "phones.json"]
    if includeAudio { files.append("audio.wav") }
    let zip = try zipFiles(in: dir, names: files.filter { FileManager.default.fileExists(atPath: dir.appending(path: $0).path) })
    defer { try? FileManager.default.removeItem(at: zip) }

    let uploadURL = try await call("mutation", "uploads:uploadUrl", ["installId": installId]) as? String
    guard let uploadURL, let url = URL(string: uploadURL) else { throw SharingError.server("no upload URL") }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/zip", forHTTPHeaderField: "Content-Type")
    let (body, resp) = try await URLSession.shared.upload(for: req, fromFile: zip)
    guard (resp as? HTTPURLResponse)?.statusCode == 200,
          let storageId = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["storageId"] as? String
    else { throw SharingError.server("upload rejected") }

    _ = try await call("mutation", "uploads:finishUpload", [
      "installId": installId, "sessionName": dir.lastPathComponent, "storageId": storageId,
      "durationSeconds": meta["durationSeconds"] as? Double ?? 0, "motionSamples": meta["motionSamples"] as? Int ?? 0,
      "words": words?.count ?? 0, "hasAudio": includeAudio,
    ])
    try Data().write(to: dir.appending(path: ".uploaded"))
  }

  /// Zip with the system `ditto` (no dependency); returns a temp file.
  nonisolated static func zipFiles(in dir: URL, names: [String]) throws -> URL {
    let stage = FileManager.default.temporaryDirectory.appending(path: "subvox-up-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: stage) }
    for n in names { try FileManager.default.copyItem(at: dir.appending(path: n), to: stage.appending(path: n)) }
    let out = FileManager.default.temporaryDirectory.appending(path: "\(dir.lastPathComponent)-\(UUID().uuidString).zip")
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    p.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", stage.path, out.path]  // no ._ AppleDouble files
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { throw SharingError.server("zip failed") }
    return out
  }

  enum SharingError: Error, CustomStringConvertible {
    case server(String)
    var description: String { if case let .server(m) = self { return m }; return "" }
  }

  /// Convex HTTP API: POST /api/{mutation|query} {path, args}. Returns `value`, throws with ConvexError data.
  nonisolated static func call(_ kind: String, _ path: String, _ args: [String: Any]) async throws -> Any? {
    var req = URLRequest(url: backend.appending(path: "api/\(kind)"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try JSONSerialization.data(withJSONObject: ["path": path, "args": args, "format": "json"])
    req.timeoutInterval = 30
    let (data, _) = try await URLSession.shared.data(for: req)
    guard let r = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SharingError.server("bad response") }
    if r["status"] as? String == "success" { return r["value"] }
    throw SharingError.server("\(r["errorData"] ?? r["errorMessage"] ?? "error")")
  }
}
