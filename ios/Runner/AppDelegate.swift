import AVFoundation
import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate, AVAudioPlayerDelegate {
  private let channelName = "cloud.orbital8.personnal_sampler/audio"
  private let sampleRate: Double = 44100.0

  private var audioChannel: FlutterMethodChannel?
  private var padAudioDataMap: [Int: Data] = [:]
  private var padFilePathMap: [Int: String] = [:]
  private var activePlayers: [Int: [AVAudioPlayer]] = [:]
  private var loopingPads: Set<Int> = []
  private var padChokeGroups: [Int: Int] = [:]

  private var audioRecorder: AVAudioRecorder?
  private var recordingFileURL: URL?
  private var recordingPadId: Int = 0
  private var isRecordingMic: Bool = false

  private var pendingPickResult: FlutterResult?
  private var pendingPickPadId: Int = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let registrar = self.registrar(forPlugin: "LifeSamplerAudioPlugin") {
      setupAudioChannel(messenger: registrar.messenger())
    } else if let controller = window?.rootViewController as? FlutterViewController {
      setupAudioChannel(messenger: controller.binaryMessenger)
    }

    configureAudioSession(forRecording: false)
    return launched
  }

  private func setupAudioChannel(messenger: FlutterBinaryMessenger) {
    guard audioChannel == nil else { return }
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call: call, result: result)
    }
    audioChannel = channel
  }

  private func configureAudioSession(forRecording: Bool) {
    let session = AVAudioSession.sharedInstance()
    do {
      if forRecording {
        try session.setCategory(
          .playAndRecord,
          mode: .default,
          options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
      } else {
        try session.setCategory(
          .playAndRecord,
          mode: .default,
          options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        )
      }
      try session.setActive(true)
    } catch {
      try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try? session.setActive(true)
    }
  }

  private func documentsDirectoryURL() -> URL {
    let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    let docURL = urls.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let samplesURL = docURL.appendingPathComponent("samples", isDirectory: true)
    if !FileManager.default.fileExists(atPath: samplesURL.path) {
      try? FileManager.default.createDirectory(at: samplesURL, withIntermediateDirectories: true)
    }
    return docURL
  }

  private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]

    switch call.method {
    case "getStorageDir":
      let docURL = documentsDirectoryURL()
      result(docURL.path)

    case "preloadPadSound":
      let padId = args["padId"] as? Int ?? 0
      let filePath = args["filePath"] as? String ?? ""
      if filePath.isEmpty || !FileManager.default.fileExists(atPath: filePath) {
        result(false)
        return
      }
      preloadPad(padId: padId, filePath: filePath)
      result(true)

    case "triggerPad":
      let padId = args["padId"] as? Int ?? 0
      let filePath = args["filePath"] as? String ?? ""
      let volume = Float(args["volume"] as? Double ?? 1.0)
      let pitch = Float(args["pitch"] as? Double ?? 1.0)
      let mode = args["mode"] as? String ?? "retrigger"
      let chokeGroup = args["chokeGroup"] as? Int ?? 0

      if filePath.isEmpty || !FileManager.default.fileExists(atPath: filePath) {
        result(["playing": false, "looping": false, "error": "FILE_NOT_FOUND"])
        return
      }

      let outcome = triggerPadInternal(
        padId: padId,
        filePath: filePath,
        volume: volume,
        pitch: pitch,
        mode: mode,
        chokeGroup: chokeGroup
      )
      result(outcome)

    case "stopPad":
      let padId = args["padId"] as? Int ?? 0
      stopPadStreams(padId: padId)
      result(true)

    case "stopAllPads":
      stopAllActiveSounds()
      result(true)

    case "startMicRecording":
      let padId = args["padId"] as? Int ?? 0
      AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
        DispatchQueue.main.async {
          guard let self = self else { return }
          if !granted {
            result(
              FlutterError(
                code: "PERMISSION_DENIED",
                message: "Permission microphone refusée sur iPhone (Réglages > Confidentialité > Micro).",
                details: nil
              )
            )
            return
          }
          if self.startMicRecordingInternal(padId: padId) {
            result(["started": true])
          } else {
            result(
              FlutterError(
                code: "MIC_INIT_FAILED",
                message: "Impossible d'initialiser l'enregistrement microphone sur iOS.",
                details: nil
              )
            )
          }
        }
      }

    case "getMicAmplitude":
      result(getCurrentMicAmplitude())

    case "stopMicRecording":
      if let recorded = stopMicRecordingInternal() {
        result(recorded)
      } else {
        result(
          FlutterError(
            code: "MIC_STOP_FAILED",
            message: "Impossible de finaliser l'enregistrement microphone iOS.",
            details: nil
          )
        )
      }

    case "pickAudioFile":
      let padId = args["padId"] as? Int ?? 0
      presentAudioFilePicker(padId: padId, result: result)

    case "exportPadWav":
      guard let typedBytes = args["bytes"] as? FlutterStandardTypedData else {
        result(
          FlutterError(
            code: "INVALID_ARGS",
            message: "Octets WAV manquants pour l'export iOS.",
            details: nil
          )
        )
        return
      }
      let fileName = args["fileName"] as? String ?? "lifesampler_pad.wav"
      do {
        let savedLocation = try exportWavToDocuments(data: typedBytes.data, fileName: fileName)
        result(savedLocation)
      } catch {
        result(
          FlutterError(
            code: "EXPORT_FAILED",
            message: error.localizedDescription,
            details: nil
          )
        )
      }

    case "setEditImmersiveMode":
      DispatchQueue.main.async { [weak self] in
        self?.window?.rootViewController?.setNeedsUpdateOfHomeIndicatorAutoHidden()
      }
      result(true)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func preloadPad(padId: Int, filePath: String) {
    if padFilePathMap[padId] == filePath, padAudioDataMap[padId] != nil {
      return
    }
    let url = URL(fileURLWithPath: filePath)
    if let data = try? Data(contentsOf: url), !data.isEmpty {
      padAudioDataMap[padId] = data
      padFilePathMap[padId] = filePath
    }
  }

  private func triggerPadInternal(
    padId: Int,
    filePath: String,
    volume: Float,
    pitch: Float,
    mode: String,
    chokeGroup: Int
  ) -> [String: Any] {
    if chokeGroup > 0 {
      padChokeGroups[padId] = chokeGroup
      for (otherPadId, group) in padChokeGroups where group == chokeGroup && otherPadId != padId {
        stopPadStreams(padId: otherPadId)
      }
    } else {
      padChokeGroups.removeValue(forKey: padId)
    }

    if mode == "loop" {
      if loopingPads.contains(padId) {
        stopPadStreams(padId: padId)
        return ["playing": false, "looping": false]
      }
      stopPadStreams(padId: padId)
      loopingPads.insert(padId)
      playSample(padId: padId, filePath: filePath, volume: volume, pitch: pitch, isLoop: true)
      return ["playing": true, "looping": true]
    }

    if mode == "retrigger" {
      stopPadStreams(padId: padId)
    }

    playSample(padId: padId, filePath: filePath, volume: volume, pitch: pitch, isLoop: false)
    return ["playing": true, "looping": false]
  }

  private func playSample(
    padId: Int,
    filePath: String,
    volume: Float,
    pitch: Float,
    isLoop: Bool
  ) {
    let clampedVol = max(0.0, min(1.5, volume))
    let clampedRate = max(0.5, min(2.0, pitch))

    if padFilePathMap[padId] != filePath || padAudioDataMap[padId] == nil {
      preloadPad(padId: padId, filePath: filePath)
    }

    do {
      let player: AVAudioPlayer
      if let cachedData = padAudioDataMap[padId] {
        player = try AVAudioPlayer(data: cachedData)
      } else {
        player = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: filePath))
      }

      player.delegate = self
      player.enableRate = true
      player.rate = clampedRate
      player.volume = min(1.0, clampedVol)
      player.numberOfLoops = isLoop ? -1 : 0
      player.prepareToPlay()

      var list = activePlayers[padId] ?? []
      // Limit simultaneous polyphonic voices per pad to 8 for stability
      if list.count >= 8, let oldest = list.first {
        oldest.stop()
        list.removeFirst()
      }
      list.append(player)
      activePlayers[padId] = list

      player.play()
    } catch {
      // Fallback: re-activate audio session and retry once
      configureAudioSession(forRecording: isRecordingMic)
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    for (padId, players) in activePlayers {
      if let idx = players.firstIndex(of: player) {
        var updated = players
        updated.remove(at: idx)
        activePlayers[padId] = updated
        if updated.isEmpty {
          loopingPads.remove(padId)
        }
        break
      }
    }
  }

  private func stopPadStreams(padId: Int) {
    loopingPads.remove(padId)
    if let players = activePlayers.removeValue(forKey: padId) {
      for player in players {
        if player.isPlaying {
          player.stop()
        }
      }
    }
  }

  private func stopAllActiveSounds() {
    loopingPads.removeAll()
    let allPadIds = Array(activePlayers.keys)
    for padId in allPadIds {
      stopPadStreams(padId: padId)
    }
  }

  private func startMicRecordingInternal(padId: Int) -> Bool {
    if isRecordingMic {
      _ = stopMicRecordingInternal()
    }

    configureAudioSession(forRecording: true)

    let samplesDir = documentsDirectoryURL().appendingPathComponent("samples", isDirectory: true)
    let timestamp = Int(Date().timeIntervalSince1970 * 1000)
    let outURL = samplesDir.appendingPathComponent("mic_pad_\(padId)_\(timestamp).wav")

    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatLinearPCM),
      AVSampleRateKey: sampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsFloatKey: false,
      AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    do {
      let recorder = try AVAudioRecorder(url: outURL, settings: settings)
      recorder.isMeteringEnabled = true
      guard recorder.prepareToRecord(), recorder.record() else {
        return false
      }
      audioRecorder = recorder
      recordingFileURL = outURL
      recordingPadId = padId
      isRecordingMic = true
      return true
    } catch {
      return false
    }
  }

  private func getCurrentMicAmplitude() -> Double {
    guard isRecordingMic, let recorder = audioRecorder else {
      return 0.0
    }
    recorder.updateMeters()
    let peakDb = Double(recorder.peakPower(forChannel: 0))
    let clampedDb = max(-55.0, min(0.0, peakDb))
    return (clampedDb + 55.0) / 55.0
  }

  private func stopMicRecordingInternal() -> [String: Any]? {
    isRecordingMic = false
    audioRecorder?.stop()
    audioRecorder = nil

    configureAudioSession(forRecording: false)

    guard let outURL = recordingFileURL,
          let wavData = try? Data(contentsOf: outURL),
          wavData.count > 44 else {
      return nil
    }

    let pcmBytesCount = max(0, wavData.count - 44)
    let totalSamples = Double(pcmBytesCount) / 2.0
    let durationMs = Int((totalSamples / sampleRate) * 1000.0)

    preloadPad(padId: recordingPadId, filePath: outURL.path)

    return [
      "path": outURL.path,
      "bytes": FlutterStandardTypedData(bytes: wavData),
      "durationMs": durationMs,
      "sampleRate": Int(sampleRate),
    ]
  }

  private func presentAudioFilePicker(padId: Int, result: @escaping FlutterResult) {
    if pendingPickResult != nil {
      result(
        FlutterError(
          code: "ALREADY_PICKING",
          message: "Sélecteur de fichiers déjà ouvert.",
          details: nil
        )
      )
      return
    }

    guard let presenter = topViewController() else {
      result(nil)
      return
    }

    pendingPickResult = result
    pendingPickPadId = padId

    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.audio], asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let res = pendingPickResult else { return }
    pendingPickResult = nil

    guard let selectedURL = urls.first else {
      res(nil)
      return
    }

    let scoped = selectedURL.startAccessingSecurityScopedResource()
    defer {
      if scoped {
        selectedURL.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let data = try Data(contentsOf: selectedURL)
      let displayName = selectedURL.lastPathComponent.isEmpty ? "sample_import.wav" : selectedURL.lastPathComponent
      let safeName = displayName.replacingOccurrences(
        of: "[^a-zA-Z0-9._-]",
        with: "_",
        options: .regularExpression
      )
      let samplesDir = documentsDirectoryURL().appendingPathComponent("samples", isDirectory: true)
      let timestamp = Int(Date().timeIntervalSince1970 * 1000)
      let outURL = samplesDir.appendingPathComponent("import_pad_\(pendingPickPadId)_\(timestamp)_\(safeName)")

      try data.write(to: outURL, options: .atomic)
      preloadPad(padId: pendingPickPadId, filePath: outURL.path)

      res([
        "path": outURL.path,
        "fileName": displayName,
        "bytes": FlutterStandardTypedData(bytes: data),
        "sizeBytes": data.count,
      ])
    } catch {
      res(
        FlutterError(
          code: "IMPORT_FAILED",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let res = pendingPickResult {
      pendingPickResult = nil
      res(nil)
    }
  }

  private func exportWavToDocuments(data: Data, fileName: String) throws -> String {
    let cleanName = fileName.lowercased().hasSuffix(".wav") ? fileName : "\(fileName).wav"
    let exportDir = documentsDirectoryURL().appendingPathComponent("LifeSampler", isDirectory: true)
    if !FileManager.default.fileExists(atPath: exportDir.path) {
      try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)
    }
    let outURL = exportDir.appendingPathComponent(cleanName)
    try data.write(to: outURL, options: .atomic)

    DispatchQueue.main.async { [weak self] in
      guard let presenter = self?.topViewController(), presenter.presentedViewController == nil else {
        return
      }
      let activityVC = UIActivityViewController(activityItems: [outURL], applicationActivities: nil)
      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(
          x: presenter.view.bounds.midX,
          y: presenter.view.bounds.maxY - 60,
          width: 1,
          height: 1
        )
      }
      presenter.present(activityVC, animated: true)
    }

    return "Fichiers > Sur mon iPhone > LifeSampler/\(cleanName)"
  }

  private func topViewController() -> UIViewController? {
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
