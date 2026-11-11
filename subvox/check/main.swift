// Standalone check for Hex/Clients/SubvoxCapture.swift (the Hex test host won't launch ad-hoc signed).
// Run: subvox/check_capture.sh
import AVFoundation
import Foundation

func check(_ ok: Bool, _ what: String, line: Int = #line) {
  if !ok { print("FAIL line \(line): \(what)"); exit(1) }
  print("ok  \(what)")
}

let tmp = FileManager.default.temporaryDirectory.appending(path: "subvox-check-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }
SubvoxCapture.root = tmp.appending(path: "Sessions")

// 2 s of 16 kHz audio, like a capture file.
let wav = tmp.appending(path: "clip.wav")
let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
do {  // scope closes the writer so the header has the final length, as when Hex finishes a recording
  let file = try! AVAudioFile(forWriting: wav, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32_000)!
  buffer.frameLength = 32_000
  try! file.write(from: buffer)
}

// Motion at 50 Hz from host t=95 to 110; audio starts at host t=100.
let capture = SubvoxCapture()
for i in 0..<750 { capture.append(.init(t: 95 + Double(i) / 50, values: (0..<16).map(Double.init))) }
capture.noteAudioStart(wav, hostSeconds: 100)
capture.noteWords(wav, [.init(text: "hello", start: 0.5, end: 0.9)])
let dir = capture.saveSession(audioURL: wav, text: "hello", model: "test", sourceApp: "Notes")!

let rows = try! String(contentsOf: dir.appending(path: "motion.csv"), encoding: .utf8)
  .split(separator: "\n").dropFirst().map { $0.split(separator: ",").map { Double($0)! } }
check(rows.count == 201, "motion window is audio +/- 1 s (201 rows at 50 Hz), got \(rows.count)")
check(abs(rows.first![0] + 1) < 1e-6 && abs(rows.last![0] - 3) < 1e-6, "motion t is on the audio clock (-1 ... 3)")
check(rows[0].count == 17 && Array(rows[0][1...]) == (0..<16).map(Double.init), "17 columns, values preserved")
let words = try! JSONSerialization.jsonObject(with: Data(contentsOf: dir.appending(path: "words.json"))) as! [String: Any]
let w = (words["words"] as! [[String: Any]])[0]
check(w["text"] as? String == "hello" && w["start"] as? Double == 0.5, "word timing written unchanged")
let meta = try! JSONSerialization.jsonObject(with: Data(contentsOf: dir.appending(path: "meta.json"))) as! [String: Any]
check(abs(meta["durationSeconds"] as! Double - 2) < 1e-6 && meta["motionSamples"] as? Int == 201, "meta duration + sample count")
check(FileManager.default.fileExists(atPath: dir.appending(path: "audio.wav").path), "audio copied")
check(capture.saveSession(audioURL: wav, text: "x", model: "t", sourceApp: nil) == nil, "per-clip state consumed, no double save")

let other = tmp.appending(path: "nostart.wav")
try! FileManager.default.copyItem(at: wav, to: other)
check(capture.saveSession(audioURL: other, text: "x", model: "t", sourceApp: nil) == nil, "no audio start time -> nothing saved")

let ring = SubvoxCapture()
for i in 0..<20_000 { ring.append(.init(t: Double(i) / 50, values: [])) }
check((6_000...7_000).contains(ring.bufferedSamples), "ring buffer bounded (\(ring.bufferedSamples))")
print("all checks passed")
