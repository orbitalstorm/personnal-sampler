import 'dart:typed_data';

/// Résultat d'un fichier audio sélectionné sur le Web (PWA iOS Safari).
class PickedWebAudioFile {
  const PickedWebAudioFile({
    required this.fileName,
    required this.bytes,
  });

  final String fileName;
  final Uint8List bytes;
}

/// Stub non-Web (utilisé sur iOS natif, Android natif et lors des tests unitaires/widgets).
class WebAudioBridge {
  const WebAudioBridge._();

  static void preloadPad(int padId, Uint8List wavBytes) {}

  static bool triggerPad({
    required int padId,
    required Uint8List wavBytes,
    required double volume,
    required double pitch,
    required String mode,
    required int chokeGroup,
  }) =>
      false;

  static void stopPad(int padId) {}

  static void stopAllPads() {}

  static Future<bool> startMicRecording(int padId) async => false;

  static double getMicAmplitude() => 0.0;

  static Future<Uint8List?> stopMicRecording() async => null;

  static Future<PickedWebAudioFile?> pickAudioFile(int padId) async => null;

  static String exportPadWav(Uint8List wavBytes, String fileName) => fileName;

  static void saveBanksJson(String jsonStr) {}

  static String? loadBanksJson() => null;
}
