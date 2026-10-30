import 'dart:math' as math;
import 'dart:typed_data';

import '../models/sampler_models.dart';

/// Résultat d'analyse ou de synthèse d'un échantillon audio WAV.
class WavAnalysisResult {
  const WavAnalysisResult({
    required this.wavBytes,
    required this.durationMs,
    required this.waveformPeaks,
    required this.sampleRate,
  });

  final Uint8List wavBytes;
  final int durationMs;
  final List<double> waveformPeaks;
  final int sampleRate;
}

/// Service pur Dart de synthèse studio 16 pads, d'analyse de forme d'onde (Waveform),
/// d'Auto-Trim du silence microphone, de normalisation crête et de découpe WAV.
class WavDspService {
  const WavDspService._();

  static const int defaultSampleRate = 44100;
  static const int defaultPeakCount = 32;

  /// Génère un fichier WAV PCM 16-bit mono pour l'un des 16 instruments du Kit Studio 808.
  static WavAnalysisResult generatePresetWav(
    SynthPresetKind preset, {
    int sampleRate = defaultSampleRate,
  }) {
    final rng = math.Random(preset.index * 9973 + 42);
    final durationSec = _presetDurationSeconds(preset);
    final numSamples = (durationSec * sampleRate).round();
    final samples = Float64List(numSamples);

    var phase1 = 0.0;
    var phase2 = 0.0;
    var phase3 = 0.0;

    for (var i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final progress = i / math.max(1, numSamples - 1);
      var sample = 0.0;

      switch (preset) {
        case SynthPresetKind.kick808:
          final freq = 52.0 + 135.0 * math.exp(-t * 34.0);
          phase1 += 2.0 * math.pi * freq / sampleRate;
          final env = math.exp(-t * 5.2);
          final click = math.exp(-t * 180.0) * 0.35;
          sample = (math.sin(phase1) * env + click) * 0.95;

        case SynthPresetKind.snarePunch:
          final bodyFreq = 185.0 + 90.0 * math.exp(-t * 40.0);
          phase1 += 2.0 * math.pi * bodyFreq / sampleRate;
          final body = math.sin(phase1) * math.exp(-t * 18.0) * 0.55;
          final noise = (rng.nextDouble() * 2.0 - 1.0) * math.exp(-t * 11.5) * 0.75;
          sample = body + noise;

        case SynthPresetKind.clapStudio:
          final noise = rng.nextDouble() * 2.0 - 1.0;
          double env;
          if (t < 0.011) {
            env = math.exp(-t * 160.0);
          } else if (t < 0.022) {
            env = math.exp(-(t - 0.011) * 160.0);
          } else if (t < 0.033) {
            env = math.exp(-(t - 0.022) * 160.0);
          } else {
            env = math.exp(-(t - 0.033) * 13.0) * 0.85;
          }
          sample = noise * env * 0.9;

        case SynthPresetKind.closedHat:
          final n = rng.nextDouble() * 2.0 - 1.0;
          phase1 += 2.0 * math.pi * 6420.0 / sampleRate;
          phase2 += 2.0 * math.pi * 8910.0 / sampleRate;
          final metal = (math.sin(phase1) + math.sin(phase2)) * 0.3 + n * 0.7;
          sample = metal * math.exp(-t * 42.0) * 0.85;

        case SynthPresetKind.openHat:
          final n = rng.nextDouble() * 2.0 - 1.0;
          phase1 += 2.0 * math.pi * 6150.0 / sampleRate;
          phase2 += 2.0 * math.pi * 8430.0 / sampleRate;
          final metal = (math.sin(phase1) + math.sin(phase2)) * 0.35 + n * 0.65;
          sample = metal * math.exp(-t * 7.5) * 0.82;

        case SynthPresetKind.tomLow:
          final freq = 92.0 + 68.0 * math.exp(-t * 20.0);
          phase1 += 2.0 * math.pi * freq / sampleRate;
          sample = math.sin(phase1) * math.exp(-t * 7.5) * 0.92;

        case SynthPresetKind.tomMid:
          final freq = 138.0 + 82.0 * math.exp(-t * 24.0);
          phase1 += 2.0 * math.pi * freq / sampleRate;
          sample = math.sin(phase1) * math.exp(-t * 8.5) * 0.92;

        case SynthPresetKind.rimshot:
          phase1 += 2.0 * math.pi * 480.0 / sampleRate;
          phase2 += 2.0 * math.pi * 1650.0 / sampleRate;
          final env = math.exp(-t * 55.0);
          sample = (math.sin(phase1) * 0.6 + math.sin(phase2) * 0.6) * env;

        case SynthPresetKind.cowbell:
          phase1 += 2.0 * math.pi * 540.0 / sampleRate;
          phase2 += 2.0 * math.pi * 800.0 / sampleRate;
          final sq1 = math.sin(phase1) >= 0 ? 0.5 : -0.5;
          final sq2 = math.sin(phase2) >= 0 ? 0.5 : -0.5;
          sample = (sq1 + sq2) * math.exp(-t * 14.0) * 0.8;

        case SynthPresetKind.crashCymbal:
          final n = rng.nextDouble() * 2.0 - 1.0;
          phase1 += 2.0 * math.pi * 4320.0 / sampleRate;
          phase2 += 2.0 * math.pi * 7190.0 / sampleRate;
          sample = (n * 0.72 + (math.sin(phase1) + math.sin(phase2)) * 0.28) *
              math.exp(-t * 3.8) *
              0.85;

        case SynthPresetKind.subBass:
          final freq = 46.25 + 30.0 * math.exp(-t * 18.0);
          phase1 += 2.0 * math.pi * freq / sampleRate;
          final raw = math.sin(phase1) + 0.35 * math.sin(phase1 * 2.0);
          sample = raw.clamp(-0.95, 0.95) * math.exp(-t * 3.0) * 0.9;

        case SynthPresetKind.acidBass:
          const freq = 110.0;
          phase1 += 2.0 * math.pi * freq / sampleRate;
          final saw = 2.0 * ((phase1 / (2.0 * math.pi)) % 1.0) - 1.0;
          final mod = math.sin(phase1 * 3.0) * math.exp(-t * 14.0);
          sample = (saw * 0.6 + mod * 0.5) * math.exp(-t * 6.5) * 0.85;

        case SynthPresetKind.minorChord:
          // Accord de La mineur (A3 - C4 - E4)
          phase1 += 2.0 * math.pi * 220.0 / sampleRate;
          phase2 += 2.0 * math.pi * 261.63 / sampleRate;
          phase3 += 2.0 * math.pi * 329.63 / sampleRate;
          final chord =
              (math.sin(phase1) + math.sin(phase2) + math.sin(phase3)) / 3.0;
          sample = chord * math.exp(-t * 4.2) * 0.9;

        case SynthPresetKind.majorStab:
          // Accord de Do majeur (C4 - E4 - G4)
          phase1 += 2.0 * math.pi * 261.63 / sampleRate;
          phase2 += 2.0 * math.pi * 329.63 / sampleRate;
          phase3 += 2.0 * math.pi * 392.00 / sampleRate;
          final chord = (math.sin(phase1) +
                  math.sin(phase2) +
                  math.sin(phase3) +
                  0.3 * math.sin(phase1 * 2.0)) /
              3.3;
          sample = chord * math.exp(-t * 7.0) * 0.92;

        case SynthPresetKind.laserZap:
          final freq = 1800.0 * math.exp(-t * 12.0) + 90.0;
          phase1 += 2.0 * math.pi * freq / sampleRate;
          sample = math.sin(phase1) * (1.0 - progress * 0.85) * 0.88;

        case SynthPresetKind.riserFx:
          final freq = 240.0 + 980.0 * progress * progress +
              45.0 * math.sin(t * 28.0);
          phase1 += 2.0 * math.pi * freq / sampleRate;
          final env = math.sin(progress * math.pi);
          sample = math.sin(phase1) * env * 0.82;
      }

      samples[i] = sample.clamp(-1.0, 1.0);
    }

    _applyAntiClickFade(samples, sampleRate);
    final pcm16 = _floatSamplesToInt16List(samples);
    final wavBytes = encodePcm16MonoToWav(pcm16, sampleRate: sampleRate);
    final peaks = _computePeaksFromInt16(pcm16, buckets: defaultPeakCount);
    final durationMs = ((numSamples / sampleRate) * 1000.0).round();

    return WavAnalysisResult(
      wavBytes: wavBytes,
      durationMs: durationMs,
      waveformPeaks: peaks,
      sampleRate: sampleRate,
    );
  }

  /// Génère un clic de métronome court (accentué sur le temps 1).
  static Uint8List generateMetronomeClickWav({
    required bool isDownbeat,
    int sampleRate = defaultSampleRate,
  }) {
    final numSamples = (0.045 * sampleRate).round();
    final samples = Float64List(numSamples);
    final freq = isDownbeat ? 1320.0 : 880.0;
    var phase = 0.0;
    for (var i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      phase += 2.0 * math.pi * freq / sampleRate;
      samples[i] = math.sin(phase) * math.exp(-t * 68.0) * 0.85;
    }
    _applyAntiClickFade(samples, sampleRate);
    return encodePcm16MonoToWav(
      _floatSamplesToInt16List(samples),
      sampleRate: sampleRate,
    );
  }

  /// Traite un enregistrement micro WAV :
  /// 1. Coupe automatiquement le silence initial et final (`autoTrimSilence`) pour supprimer
  ///    tout délai au déclenchement ;
  /// 2. Normalise le volume crête (`normalize`) pour garantir un niveau puissant ;
  /// 3. Applique un fondu anti-clic de 3 ms.
  static WavAnalysisResult processRecordedMicWav(
    Uint8List rawWavBytes, {
    bool autoTrimSilence = true,
    bool normalize = true,
  }) {
    final parsed = _parseWavPcm16Mono(rawWavBytes);
    var samples = parsed.samples;
    final sampleRate = parsed.sampleRate;

    if (samples.isEmpty) {
      return generatePresetWav(SynthPresetKind.kick808, sampleRate: sampleRate);
    }

    if (autoTrimSilence) {
      var maxAbs = 0;
      for (var i = 0; i < samples.length; i++) {
        final v = samples[i].abs();
        if (v > maxAbs) maxAbs = v;
      }
      if (maxAbs > 400) {
        // Seuil adaptatif : 4.5% du pic ou 550 (en PCM 16-bit)
        final threshold = math.max(550, (maxAbs * 0.045).round());
        var firstActive = 0;
        for (var i = 0; i < samples.length; i++) {
          if (samples[i].abs() >= threshold) {
            firstActive = i;
            break;
          }
        }
        var lastActive = samples.length - 1;
        for (var i = samples.length - 1; i >= firstActive; i--) {
          if (samples[i].abs() >= (threshold * 0.6).round()) {
            lastActive = i;
            break;
          }
        }
        // Conserver 5 ms de pré-attaque et 35 ms de relâchement naturel
        final preRoll = (sampleRate * 0.005).round();
        final postRoll = (sampleRate * 0.035).round();
        final startIdx = math.max(0, firstActive - preRoll);
        final endIdx = math.min(samples.length, lastActive + postRoll);
        if (endIdx - startIdx >= (sampleRate * 0.04).round()) {
          samples = Int16List.fromList(samples.sublist(startIdx, endIdx));
        }
      }
    }

    if (normalize && samples.isNotEmpty) {
      var maxAbs = 0;
      for (var i = 0; i < samples.length; i++) {
        final v = samples[i].abs();
        if (v > maxAbs) maxAbs = v;
      }
      if (maxAbs > 250 && maxAbs < 30000) {
        final gain = (30146.0 / maxAbs).clamp(1.0, 10.0);
        final normalized = Int16List(samples.length);
        for (var i = 0; i < samples.length; i++) {
          normalized[i] = (samples[i] * gain).round().clamp(-32768, 32767);
        }
        samples = normalized;
      }
    }

    _applyAntiClickFadeInt16(samples, sampleRate);

    final outWav = encodePcm16MonoToWav(samples, sampleRate: sampleRate);
    final durationMs = ((samples.length / sampleRate) * 1000.0).round();
    final peaks = _computePeaksFromInt16(samples, buckets: defaultPeakCount);

    return WavAnalysisResult(
      wavBytes: outWav,
      durationMs: math.max(40, durationMs),
      waveformPeaks: peaks,
      sampleRate: sampleRate,
    );
  }

  /// Analyse les octets d'un fichier audio importé (WAV ou format compressé MP3/M4A/OGG).
  static WavAnalysisResult analyzeAudioBytes(
    Uint8List bytes, {
    int buckets = defaultPeakCount,
  }) {
    if (_looksLikeWav(bytes)) {
      final parsed = _parseWavPcm16Mono(bytes);
      if (parsed.samples.isNotEmpty) {
        final durationMs =
            ((parsed.samples.length / parsed.sampleRate) * 1000.0).round();
        final peaks =
            _computePeaksFromInt16(parsed.samples, buckets: buckets);
        return WavAnalysisResult(
          wavBytes: encodePcm16MonoToWav(
            parsed.samples,
            sampleRate: parsed.sampleRate,
          ),
          durationMs: math.max(40, durationMs),
          waveformPeaks: peaks,
          sampleRate: parsed.sampleRate,
        );
      }
    }

    // Pour un fichier audio compressé (MP3/OGG/M4A), estimation de l'enveloppe et de la durée
    final estimatedDurationMs = math.max(250, (bytes.length / 16.0).round().clamp(250, 30000));
    final peaks = List<double>.generate(buckets, (int b) {
      if (bytes.isEmpty) return 0.35;
      final start = (b * bytes.length) ~/ buckets;
      final end = math.min(bytes.length, ((b + 1) * bytes.length) ~/ buckets);
      if (end <= start) return 0.35;
      var sum = 0.0;
      final step = math.max(1, (end - start) ~/ 32);
      var count = 0;
      for (var i = start; i < end; i += step) {
        sum += ((bytes[i] - 128).abs()) / 128.0;
        count++;
      }
      final avg = count > 0 ? (sum / count) : 0.4;
      return (0.2 + avg * 0.75).clamp(0.12, 1.0);
    }, growable: false);

    return WavAnalysisResult(
      wavBytes: bytes,
      durationMs: estimatedDurationMs,
      waveformPeaks: peaks,
      sampleRate: defaultSampleRate,
    );
  }

  /// Découpe un fichier WAV entre `trimStart` (0.0..0.95) et `trimEnd` (0.05..1.0)
  /// avec un fondu anti-clic de 3 ms.
  static Uint8List? sliceWavBytes(
    Uint8List sourceBytes, {
    required double trimStart,
    required double trimEnd,
  }) {
    if (!_looksLikeWav(sourceBytes)) {
      return null;
    }
    final parsed = _parseWavPcm16Mono(sourceBytes);
    if (parsed.samples.isEmpty) {
      return null;
    }
    final safeStart = trimStart.clamp(0.0, 0.95);
    final safeEnd = trimEnd.clamp(safeStart + 0.05, 1.0);
    final total = parsed.samples.length;
    final startIdx = (total * safeStart).floor().clamp(0, total - 1);
    final endIdx = (total * safeEnd).ceil().clamp(startIdx + 1, total);

    final sliced = Int16List.fromList(parsed.samples.sublist(startIdx, endIdx));
    _applyAntiClickFadeInt16(sliced, parsed.sampleRate);
    return encodePcm16MonoToWav(sliced, sampleRate: parsed.sampleRate);
  }

  /// Encode une liste d'échantillons PCM 16-bit signés mono en fichier RIFF/WAVE standard (44 octets d'en-tête).
  static Uint8List encodePcm16MonoToWav(
    Int16List samples, {
    int sampleRate = defaultSampleRate,
  }) {
    final dataByteLength = samples.length * 2;
    final totalDataLen = dataByteLength + 36;
    final byteRate = sampleRate * 2;
    final buffer = ByteData(44 + dataByteLength);

    // "RIFF"
    buffer.setUint8(0, 0x52);
    buffer.setUint8(1, 0x49);
    buffer.setUint8(2, 0x46);
    buffer.setUint8(3, 0x46);
    buffer.setUint32(4, totalDataLen, Endian.little);
    // "WAVE"
    buffer.setUint8(8, 0x57);
    buffer.setUint8(9, 0x41);
    buffer.setUint8(10, 0x56);
    buffer.setUint8(11, 0x45);
    // "fmt "
    buffer.setUint8(12, 0x66);
    buffer.setUint8(13, 0x6D);
    buffer.setUint8(14, 0x74);
    buffer.setUint8(15, 0x20);
    buffer.setUint32(16, 16, Endian.little); // Subchunk1Size (PCM)
    buffer.setUint16(20, 1, Endian.little); // AudioFormat = 1 (PCM)
    buffer.setUint16(22, 1, Endian.little); // NumChannels = 1
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, byteRate, Endian.little);
    buffer.setUint16(32, 2, Endian.little); // BlockAlign
    buffer.setUint16(34, 16, Endian.little); // BitsPerSample
    // "data"
    buffer.setUint8(36, 0x64);
    buffer.setUint8(37, 0x61);
    buffer.setUint8(38, 0x74);
    buffer.setUint8(39, 0x61);
    buffer.setUint32(40, dataByteLength, Endian.little);

    for (var i = 0; i < samples.length; i++) {
      buffer.setInt16(44 + i * 2, samples[i], Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  static bool _looksLikeWav(Uint8List bytes) {
    if (bytes.length < 44) return false;
    return bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[2] == 0x46 && // F
        bytes[3] == 0x46 && // F
        bytes[8] == 0x57 && // W
        bytes[9] == 0x41 && // A
        bytes[10] == 0x56 && // V
        bytes[11] == 0x45; // E
  }

  static _ParsedWav _parseWavPcm16Mono(Uint8List bytes) {
    if (!_looksLikeWav(bytes)) {
      return _ParsedWav(samples: Int16List(0), sampleRate: defaultSampleRate);
    }
    final bd = ByteData.sublistView(bytes);
    var offset = 12;
    var numChannels = 1;
    var sampleRate = defaultSampleRate;
    var bitsPerSample = 16;
    var audioFormat = 1;
    var dataOffset = -1;
    var dataSize = 0;

    while (offset + 8 <= bytes.length) {
      final c0 = bytes[offset];
      final c1 = bytes[offset + 1];
      final c2 = bytes[offset + 2];
      final c3 = bytes[offset + 3];
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      final chunkDataStart = offset + 8;

      // "fmt "
      if (c0 == 0x66 && c1 == 0x6D && c2 == 0x74 && c3 == 0x20) {
        if (chunkDataStart + 16 <= bytes.length) {
          audioFormat = bd.getUint16(chunkDataStart, Endian.little);
          numChannels = math.max(1, bd.getUint16(chunkDataStart + 2, Endian.little));
          sampleRate = math.max(8000, bd.getUint32(chunkDataStart + 4, Endian.little));
          bitsPerSample = bd.getUint16(chunkDataStart + 14, Endian.little);
        }
      } else if (c0 == 0x64 && c1 == 0x61 && c2 == 0x74 && c3 == 0x61) {
        // "data"
        dataOffset = chunkDataStart;
        dataSize = math.min(chunkSize, bytes.length - chunkDataStart);
        break;
      }

      final paddedSize = chunkSize + (chunkSize.isOdd ? 1 : 0);
      offset = chunkDataStart + paddedSize;
    }

    if (dataOffset < 0 || dataSize <= 0) {
      dataOffset = 44;
      dataSize = math.max(0, bytes.length - 44);
    }

    final bytesPerSample = math.max(1, bitsPerSample ~/ 8);
    final frameSize = bytesPerSample * numChannels;
    final frameCount = dataSize ~/ frameSize;
    final out = Int16List(frameCount);

    for (var i = 0; i < frameCount; i++) {
      final framePos = dataOffset + i * frameSize;
      if (framePos + bytesPerSample > bytes.length) break;
      int sample16;
      if (bitsPerSample == 16) {
        sample16 = bd.getInt16(framePos, Endian.little);
      } else if (bitsPerSample == 8) {
        final u8 = bd.getUint8(framePos);
        sample16 = ((u8 - 128) * 256).clamp(-32768, 32767);
      } else if (bitsPerSample == 24 && framePos + 3 <= bytes.length) {
        final b1 = bytes[framePos + 1];
        final b2 = bytes[framePos + 2];
        final s = (b2 << 8) | b1;
        sample16 = s >= 0x8000 ? s - 0x10000 : s;
      } else if (bitsPerSample == 32 && audioFormat == 3 && framePos + 4 <= bytes.length) {
        final f = bd.getFloat32(framePos, Endian.little);
        sample16 = (f * 32767.0).round().clamp(-32768, 32767);
      } else if (bitsPerSample == 32 && framePos + 4 <= bytes.length) {
        sample16 = (bd.getInt32(framePos, Endian.little) >> 16).clamp(-32768, 32767);
      } else {
        sample16 = 0;
      }
      out[i] = sample16;
    }

    return _ParsedWav(samples: out, sampleRate: sampleRate);
  }

  static List<double> _computePeaksFromInt16(
    Int16List samples, {
    int buckets = defaultPeakCount,
  }) {
    if (samples.isEmpty) {
      return List<double>.filled(buckets, 0.1, growable: false);
    }
    var globalMax = 1;
    for (var i = 0; i < samples.length; i++) {
      final absV = samples[i].abs();
      if (absV > globalMax) globalMax = absV;
    }

    return List<double>.generate(buckets, (int b) {
      final start = (b * samples.length) ~/ buckets;
      final end = math.min(
        samples.length,
        math.max(start + 1, ((b + 1) * samples.length) ~/ buckets),
      );
      var localMax = 0;
      for (var i = start; i < end; i++) {
        final v = samples[i].abs();
        if (v > localMax) localMax = v;
      }
      return (localMax / globalMax).clamp(0.05, 1.0);
    }, growable: false);
  }

  static Int16List _floatSamplesToInt16List(Float64List samples) {
    final out = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      out[i] = (samples[i].clamp(-1.0, 1.0) * 32767.0).round().clamp(-32768, 32767);
    }
    return out;
  }

  static void _applyAntiClickFade(Float64List samples, int sampleRate) {
    final fadeSamples = math.min(samples.length ~/ 4, (sampleRate * 0.003).round());
    for (var i = 0; i < fadeSamples; i++) {
      final gain = i / math.max(1, fadeSamples);
      samples[i] *= gain;
      samples[samples.length - 1 - i] *= gain;
    }
  }

  static void _applyAntiClickFadeInt16(Int16List samples, int sampleRate) {
    final fadeSamples = math.min(samples.length ~/ 4, (sampleRate * 0.003).round());
    for (var i = 0; i < fadeSamples; i++) {
      final gain = i / math.max(1, fadeSamples);
      samples[i] = (samples[i] * gain).round();
      final tailIdx = samples.length - 1 - i;
      samples[tailIdx] = (samples[tailIdx] * gain).round();
    }
  }

  static double _presetDurationSeconds(SynthPresetKind preset) {
    switch (preset) {
      case SynthPresetKind.kick808:
        return 0.42;
      case SynthPresetKind.snarePunch:
        return 0.26;
      case SynthPresetKind.clapStudio:
        return 0.28;
      case SynthPresetKind.closedHat:
        return 0.11;
      case SynthPresetKind.openHat:
        return 0.38;
      case SynthPresetKind.tomLow:
        return 0.34;
      case SynthPresetKind.tomMid:
        return 0.30;
      case SynthPresetKind.rimshot:
        return 0.10;
      case SynthPresetKind.cowbell:
        return 0.22;
      case SynthPresetKind.crashCymbal:
        return 0.65;
      case SynthPresetKind.subBass:
        return 0.55;
      case SynthPresetKind.acidBass:
        return 0.36;
      case SynthPresetKind.minorChord:
        return 0.52;
      case SynthPresetKind.majorStab:
        return 0.35;
      case SynthPresetKind.laserZap:
        return 0.32;
      case SynthPresetKind.riserFx:
        return 0.60;
    }
  }
}

class _ParsedWav {
  const _ParsedWav({
    required this.samples,
    required this.sampleRate,
  });

  final Int16List samples;
  final int sampleRate;
}
