import 'dart:js_interop';
import 'dart:typed_data';

@JS('LifeSamplerWebBridge.preloadPad')
external void _jsPreloadPad(int padId, JSUint8Array wavBytes);

@JS('LifeSamplerWebBridge.triggerPad')
external bool _jsTriggerPad(
  int padId,
  JSUint8Array wavBytes,
  double volume,
  double pitch,
  String mode,
  int chokeGroup,
);

@JS('LifeSamplerWebBridge.stopPad')
external void _jsStopPad(int padId);

@JS('LifeSamplerWebBridge.stopAllPads')
external void _jsStopAllPads();

@JS('LifeSamplerWebBridge.startMicRecording')
external JSPromise<JSBoolean> _jsStartMicRecording(int padId);

@JS('LifeSamplerWebBridge.getMicAmplitude')
external double _jsGetMicAmplitude();

@JS('LifeSamplerWebBridge.stopMicRecording')
external JSPromise<JSUint8Array?> _jsStopMicRecording();

@JS('LifeSamplerWebBridge.pickAudioFile')
external JSPromise<JSObject?> _jsPickAudioFile(int padId);

@JS('LifeSamplerWebBridge.getPickedFileName')
external String _jsGetPickedFileName(JSObject pickedObj);

@JS('LifeSamplerWebBridge.getPickedFileBytes')
external JSUint8Array _jsGetPickedFileBytes(JSObject pickedObj);

@JS('LifeSamplerWebBridge.exportPadWav')
external String _jsExportPadWav(JSUint8Array wavBytes, String fileName);

@JS('LifeSamplerWebBridge.saveBanksJson')
external void _jsSaveBanksJson(String jsonStr);

@JS('LifeSamplerWebBridge.loadBanksJson')
external String? _jsLoadBanksJson();

/// Résultat d'un fichier audio sélectionné sur le Web (PWA iOS Safari).
class PickedWebAudioFile {
  const PickedWebAudioFile({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

/// Pont Web Audio API + MediaRecorder + Export WAV pour iOS Safari (PWA iPhone) et navigateurs mobiles.
class WebAudioBridge {
  const WebAudioBridge._();

  static void preloadPad(int padId, Uint8List wavBytes) {
    try {
      _jsPreloadPad(padId, wavBytes.toJS);
    } catch (_) {}
  }

  static bool triggerPad({
    required int padId,
    required Uint8List wavBytes,
    required double volume,
    required double pitch,
    required String mode,
    required int chokeGroup,
  }) {
    try {
      return _jsTriggerPad(
        padId,
        wavBytes.toJS,
        volume,
        pitch,
        mode,
        chokeGroup,
      );
    } catch (_) {
      return mode == 'loop';
    }
  }

  static void stopPad(int padId) {
    try {
      _jsStopPad(padId);
    } catch (_) {}
  }

  static void stopAllPads() {
    try {
      _jsStopAllPads();
    } catch (_) {}
  }

  static Future<bool> startMicRecording(int padId) async {
    try {
      final res = await _jsStartMicRecording(padId).toDart;
      return res.toDart;
    } catch (_) {
      return false;
    }
  }

  static double getMicAmplitude() {
    try {
      return _jsGetMicAmplitude().clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  static Future<Uint8List?> stopMicRecording() async {
    try {
      final res = await _jsStopMicRecording().toDart;
      return res?.toDart;
    } catch (_) {
      return null;
    }
  }

  static Future<PickedWebAudioFile?> pickAudioFile(int padId) async {
    try {
      final picked = await _jsPickAudioFile(padId).toDart;
      if (picked == null) return null;
      final name = _jsGetPickedFileName(picked);
      final bytes = _jsGetPickedFileBytes(picked).toDart;
      if (bytes.isEmpty) return null;
      return PickedWebAudioFile(fileName: name, bytes: bytes);
    } catch (_) {
      return null;
    }
  }

  static String exportPadWav(Uint8List wavBytes, String fileName) {
    try {
      return _jsExportPadWav(wavBytes.toJS, fileName);
    } catch (_) {
      return fileName;
    }
  }

  static void saveBanksJson(String jsonStr) {
    try {
      _jsSaveBanksJson(jsonStr);
    } catch (_) {}
  }

  static String? loadBanksJson() {
    try {
      return _jsLoadBanksJson();
    } catch (_) {
      return null;
    }
  }
}
