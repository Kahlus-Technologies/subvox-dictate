// Live check of SubvoxSharing.upload against the dev backend with a real saved session.
// Run: subvox/check_sharing.sh <session dir>
import Foundation

func check(_ ok: Bool, _ what: String) { print(ok ? "ok  \(what)" : "FAIL \(what)"); if !ok { exit(1) } }

let src = URL(fileURLWithPath: CommandLine.arguments[1])
let tmp = FileManager.default.temporaryDirectory.appending(path: "subvox-share-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }
SubvoxCapture.root = tmp
let dir = tmp.appending(path: src.lastPathComponent)
try! FileManager.default.copyItem(at: src, to: dir)
check(SubvoxSharing.sessionDirs().count == 1, "finished session found")

let id = UUID().uuidString.lowercased()
let sem = DispatchSemaphore(value: 0)
Task {
  do {
    do { try await SubvoxSharing.upload(dir, installId: id, includeAudio: false); check(false, "refused without consent") }
    catch { check("\(error)".contains("consent"), "upload refused without consent (\(error))") }
    _ = try await SubvoxSharing.call("mutation", "uploads:consent", ["installId": id, "consentVersion": 1, "shareAudio": false, "appVersion": "check"])
    try await SubvoxSharing.upload(dir, installId: id, includeAudio: false)
    check(SubvoxSharing.isUploaded(dir), "uploaded + marked .uploaded")
    let stats = try await SubvoxSharing.call("query", "uploads:myStats", ["installId": id]) as! [String: Any]
    check((stats["sessions"] as? Double) == 1, "server has 1 session \(stats)")
    do { try await SubvoxSharing.upload(dir, installId: id, includeAudio: true); check(false, "audio refused") }
    catch { check("\(error)".contains("audio"), "audio refused when not consented (\(error))") }
    let del = try await SubvoxSharing.call("mutation", "uploads:deleteMyData", ["installId": id]) as! [String: Any]
    check((del["deletedSessions"] as? Double) == 1, "delete my data removed it")

    // With audio consent: audio.wav goes up, and the zip has no macOS ._ metadata files.
    let id2 = UUID().uuidString.lowercased()
    _ = try await SubvoxSharing.call("mutation", "uploads:consent", ["installId": id2, "consentVersion": 1, "shareAudio": true, "appVersion": "check"])
    try? FileManager.default.removeItem(at: dir.appending(path: ".uploaded"))
    try await SubvoxSharing.upload(dir, installId: id2, includeAudio: true)
    let zip = try SubvoxSharing.zipFiles(in: dir, names: ["words.json", "audio.wav"])
    let list = Process(); let pipe = Pipe()
    list.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo"); list.arguments = ["-1", zip.path]; list.standardOutput = pipe
    try list.run(); list.waitUntilExit()
    let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
    check(names.sorted() == ["audio.wav", "words.json"], "zip holds exactly the chosen files \(names)")
    let stats2 = try await SubvoxSharing.call("query", "uploads:myStats", ["installId": id2]) as! [String: Any]
    check((stats2["sessions"] as? Double) == 1, "audio session accepted with audio consent")
    _ = try await SubvoxSharing.call("mutation", "uploads:deleteMyData", ["installId": id2])
  } catch { check(false, "unexpected \(error)") }
  sem.signal()
}
sem.wait()
print("all sharing checks passed")
