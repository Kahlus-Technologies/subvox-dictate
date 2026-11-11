import AVFoundation
import CoreAudio
import CoreMotion
import Foundation
import os.log

/// Subvox data capture: every dictation also becomes a labelled Subvox session.
///
/// While the app runs, AirPods head-motion streams into a short ring buffer. When a dictation
/// finishes transcribing, `saveSession` writes the Subvox session format
/// (`~/Documents/Subvox/Sessions/<stamp>-dictation/`): motion.csv, audio.wav, words.json, meta.json.
/// motion.csv `t` and words.json start/end share one clock: seconds since the first audio sample.
final class SubvoxCapture: @unchecked Sendable {
  static let shared = SubvoxCapture()
  static let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appending(path: "Subvox/Sessions", directoryHint: .isDirectory)

  struct Word: Codable { let text: String; let start: Double; let end: Double }

  private let log = Logger(subsystem: "com.kahlus.subvox.dictate", category: "Subvox")
  private let lock = NSLock()
  private let manager = CMHeadphoneMotionManager()
  private let queue = OperationQueue()
  private var samples: [CMDeviceMotion] = []  // ponytail: 2 min array ring, trimmed in bulk; fine at 50 Hz
  private var audioStart: [URL: TimeInterval] = [:]  // capture file -> host seconds of its first sample
  private var words: [URL: [Word]] = [:]
  private(set) var sessionsSaved = 0
  private(set) var lastSampleUptime: TimeInterval = 0

  var motionStreaming: Bool { ProcessInfo.processInfo.systemUptime - lastSampleUptime < 2 }

  func start() {
    guard manager.isDeviceMotionAvailable else { return log.error("Headphone motion unavailable") }
    queue.maxConcurrentOperationCount = 1
    manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
      guard let self, let motion else {
        if let error { self?.log.error("Motion error: \(error.localizedDescription)") }
        return
      }
      lock.withLock {
        self.samples.append(motion)
        self.lastSampleUptime = motion.timestamp
        if self.samples.count > 7_000 { self.samples.removeFirst(self.samples.count - 6_000) }
      }
    }
    log.notice("Headphone motion started")
  }

  /// Called by the capture engine with the host time of the first sample written to `url`.
  func noteAudioStart(_ url: URL, hostSeconds: TimeInterval) {
    lock.withLock { audioStart[url] = hostSeconds }
  }

  /// Called by the transcriber with word timings in seconds from the start of `url`.
  func noteWords(_ url: URL, _ list: [Word]) {
    lock.withLock { words[url] = list }
  }

  /// Copies the clip and writes the session. Runs off the main thread; failures only log.
  func saveSession(audioURL: URL, text: String, model: String, sourceApp: String?) {
    let (start, wordList, motion) = lock.withLock { () -> (TimeInterval?, [Word]?, [CMDeviceMotion]) in
      defer { audioStart[audioURL] = nil; words[audioURL] = nil }
      return (audioStart[audioURL], words[audioURL], samples)
    }
    guard let start else { return log.notice("No audio start time for \(audioURL.lastPathComponent, privacy: .public); not saving") }
    let duration = (try? AVAudioFile(forReading: audioURL)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
    let clip = motion.filter { $0.timestamp >= start - 1 && $0.timestamp <= start + duration + 1 }

    let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
      .replacingOccurrences(of: ":", with: "").replacingOccurrences(of: ".", with: "-")
    let dir = Self.root.appending(path: "\(stamp)-dictation", directoryHint: .isDirectory)
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: audioURL, to: dir.appending(path: "audio.wav"))
      var csv = "t,ax,ay,az,rx,ry,rz,pitch,roll,yaw,gx,gy,gz,qw,qx,qy,qz\n"
      for m in clip {
        let q = m.attitude.quaternion
        csv += [m.timestamp - start, m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z,
                m.rotationRate.x, m.rotationRate.y, m.rotationRate.z, m.attitude.pitch, m.attitude.roll, m.attitude.yaw,
                m.gravity.x, m.gravity.y, m.gravity.z, q.w, q.x, q.y, q.z]
          .map { String(format: "%.6f", $0) }.joined(separator: ",") + "\n"
      }
      try csv.write(to: dir.appending(path: "motion.csv"), atomically: true, encoding: .utf8)
      let wordsJSON: [String: Any] = [
        "text": text,
        "words": (wordList ?? []).map { ["text": $0.text, "start": $0.start, "end": $0.end] },
        "clock": "start/end are on the motion.csv t clock",
        "source": model,
      ]
      try JSONSerialization.data(withJSONObject: wordsJSON, options: [.prettyPrinted]).write(to: dir.appending(path: "words.json"))
      let meta: [String: Any] = [
        "condition": "Dictation",
        "speaker": NSFullUserName(),
        "startedAt": Date(timeIntervalSinceNow: -(ProcessInfo.processInfo.systemUptime - start)).ISO8601Format(),
        "startUptime": start,
        "durationSeconds": duration,
        "motionSamples": clip.count,
        "audioDevice": Self.defaultInputName() ?? NSNull(),
        "audioSampleRate": 16_000,
        "audioStartOffsetSeconds": 0,
        "sourceApp": sourceApp ?? NSNull(),
        "transcriptionModel": model,
        "note": "Recorded by Subvox Dictate. Motion t, words, and audio share one clock: seconds since the first audio sample.",
      ]
      try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys]).write(to: dir.appending(path: "meta.json"))
      lock.withLock { sessionsSaved += 1 }
      log.notice("Saved Subvox session \(dir.lastPathComponent, privacy: .public) motion=\(clip.count, privacy: .public) words=\(wordList?.count ?? -1, privacy: .public)")
    } catch {
      log.error("Failed to save Subvox session: \(error.localizedDescription, privacy: .public)")
    }
  }

  static func defaultInputName() -> String? {
    var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
    var name: Unmanaged<CFString>?
    size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    addr.mSelector = kAudioDevicePropertyDeviceNameCFString
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr, let name else { return nil }
    return name.takeRetainedValue() as String
  }

  /// The built-in microphone, used when the user picked no microphone. Using the AirPods mic would switch
  /// them into the low-quality headset (HFP) profile mid-dictation.
  static func builtInMicrophone() -> AudioDeviceID? {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return nil }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return nil }
    return ids.first { id in
      var transport: UInt32 = 0, tsize = UInt32(MemoryLayout<UInt32>.size)
      var taddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
      guard AudioObjectGetPropertyData(id, &taddr, 0, nil, &tsize, &transport) == noErr, transport == kAudioDeviceTransportTypeBuiltIn else { return false }
      var saddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
      var ssize: UInt32 = 0
      return AudioObjectGetPropertyDataSize(id, &saddr, 0, nil, &ssize) == noErr && ssize > 0
    }
  }
}
