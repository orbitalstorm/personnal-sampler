import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../models/sampler_models.dart';
import 'wav_dsp_service.dart';

/// Résultat d'un déclenchement de pad.
class TriggerResult {
  const TriggerResult({
    required this.playing,
    required this.looping,
  });

  final bool playing;
  final bool looping;
}

/// Moteur audio et persistance du sampleur 4x4 (16 pads).
/// Pont entre Flutter, le DSP WAV pur Dart et le moteur natif Android (SoundPool + AudioRecord + SAF).
class SamplerAudioEngine {
  SamplerAudioEngine({Directory? customStorageDir})
      : _customStorageDir = customStorageDir,
        _nativeChannelAvailable =
            Platform.isAndroid && customStorageDir == null;

  static const MethodChannel _channel =
      MethodChannel('cloud.orbital8.personnal_sampler/audio');

  final Directory? _customStorageDir;
  Directory? _storageDir;
  bool _nativeChannelAvailable;

  final Map<SynthPresetKind, WavAnalysisResult> _presetCache =
      <SynthPresetKind, WavAnalysisResult>{};
  final Map<SynthPresetKind, String> _presetFilePaths =
      <SynthPresetKind, String>{};

  String? _metroDownbeatPath;
  String? _metroUpbeatPath;

  DateTime? _fallbackMicStartTime;

  /// Construit immédiatement les 4 banques par défaut de manière synchrone
  /// afin que l'interface 4x4 s'affiche dès la 1re frame sans écran d'attente.
  List<SamplerBank> buildDefaultBanksSync() {
    final defaultWaveforms = <List<double>>[];
    final defaultDurations = <int>[];
    for (final preset in SynthPresetKind.values) {
      final cached = _presetCache[preset] ?? WavDspService.generatePresetWav(preset);
      _presetCache[preset] = cached;
      defaultWaveforms.add(cached.waveformPeaks);
      defaultDurations.add(cached.durationMs);
    }
    return _createDefaultBanks(
      defaultWaveforms: defaultWaveforms,
      defaultDurations: defaultDurations,
    );
  }

  /// Initialise le répertoire de stockage, génère les fichiers WAV du Kit Studio 808
  /// et charge les 4 banques sauvegardées (ou crée les banques par défaut).
  Future<List<SamplerBank>> initialize() async {
    final baseDir = await _resolveStorageDir();
    final samplesDir = Directory('${baseDir.path}/samples');
    if (!samplesDir.existsSync()) {
      samplesDir.createSync(recursive: true);
    }

    final defaultWaveforms = <List<double>>[];
    final defaultDurations = <int>[];

    for (final preset in SynthPresetKind.values) {
      final analysis = WavDspService.generatePresetWav(preset);
      _presetCache[preset] = analysis;
      defaultWaveforms.add(analysis.waveformPeaks);
      defaultDurations.add(analysis.durationMs);

      final presetFile = File('${samplesDir.path}/preset_${preset.index}_${preset.name}.wav');
      if (!presetFile.existsSync()) {
        presetFile.writeAsBytesSync(analysis.wavBytes, flush: true);
      }
      _presetFilePaths[preset] = presetFile.path;
    }

    // Sons du métronome
    final downFile = File('${samplesDir.path}/metro_down.wav');
    if (!downFile.existsSync()) {
      downFile.writeAsBytesSync(
        WavDspService.generateMetronomeClickWav(isDownbeat: true),
        flush: true,
      );
    }
    _metroDownbeatPath = downFile.path;

    final upFile = File('${samplesDir.path}/metro_up.wav');
    if (!upFile.existsSync()) {
      upFile.writeAsBytesSync(
        WavDspService.generateMetronomeClickWav(isDownbeat: false),
        flush: true,
      );
    }
    _metroUpbeatPath = upFile.path;

    final savedBanks = await _loadSavedBanks(
      defaultWaveforms: defaultWaveforms,
      defaultDurations: defaultDurations,
    );

    await preloadBank(savedBanks.first);
    return savedBanks;
  }

  /// Pré-charge les sons d'une banque dans le SoundPool natif Android.
  Future<void> preloadBank(SamplerBank bank) async {
    if (!_nativeChannelAvailable) return;
    for (final pad in bank.pads) {
      final path = resolvePlayablePath(pad);
      if (path != null && path.isNotEmpty) {
        try {
          await _channel.invokeMethod<dynamic>(
            'preloadPadSound',
            <String, dynamic>{
              'padId': pad.id,
              'filePath': path,
            },
          );
        } on MissingPluginException {
          _nativeChannelAvailable = false;
          return;
        } on PlatformException {
          // Ignoré si le canal natif n'est pas disponible
        }
      }
    }
  }

  /// Résout le chemin de fichier WAV jouable pour un pad.
  String? resolvePlayablePath(SamplerPad pad) {
    if (pad.activePlaybackPath != null &&
        pad.activePlaybackPath!.isNotEmpty &&
        File(pad.activePlaybackPath!).existsSync()) {
      return pad.activePlaybackPath;
    }
    if (pad.filePath != null &&
        pad.filePath!.isNotEmpty &&
        File(pad.filePath!).existsSync()) {
      return pad.filePath;
    }
    if (pad.source == PadSoundSource.synthPreset && pad.synthPreset != null) {
      return _presetFilePaths[pad.synthPreset!];
    }
    return null;
  }

  /// Déclenche immédiatement la lecture d'un pad.
  Future<TriggerResult> triggerPad(SamplerPad pad) async {
    if (!pad.hasSound) {
      return const TriggerResult(playing: false, looping: false);
    }

    final path = resolvePlayablePath(pad);
    try {
      unawaited(HapticFeedback.lightImpact());
    } catch (_) {}

    if (path == null || !_nativeChannelAvailable) {
      final isLoop = pad.triggerMode == PadTriggerMode.loop;
      return TriggerResult(playing: true, looping: isLoop);
    }

    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'triggerPad',
        <String, dynamic>{
          'padId': pad.id,
          'filePath': path,
          'volume': pad.volume,
          'pitch': pad.pitch,
          'mode': pad.triggerMode.name,
          'chokeGroup': pad.chokeGroup,
        },
      );
      if (res != null) {
        return TriggerResult(
          playing: res['playing'] as bool? ?? true,
          looping: res['looping'] as bool? ?? false,
        );
      }
    } on MissingPluginException {
      _nativeChannelAvailable = false;
    } on PlatformException {
      // Fallback
    }

    final isLoop = pad.triggerMode == PadTriggerMode.loop;
    return TriggerResult(playing: true, looping: isLoop);
  }

  /// Joue un clic de métronome.
  Future<void> triggerMetronomeClick({required bool isDownbeat}) async {
    if (!_nativeChannelAvailable) return;
    final path = isDownbeat ? _metroDownbeatPath : _metroUpbeatPath;
    if (path == null) return;
    try {
      await _channel.invokeMapMethod<String, dynamic>(
        'triggerPad',
        <String, dynamic>{
          'padId': isDownbeat ? 98 : 99,
          'filePath': path,
          'volume': isDownbeat ? 0.75 : 0.45,
          'pitch': 1.0,
          'mode': 'oneShot',
          'chokeGroup': 0,
        },
      );
    } on MissingPluginException {
      _nativeChannelAvailable = false;
    } on PlatformException {
      // Ignoré
    }
  }

  /// Arrête immédiatement un pad spécifique.
  Future<void> stopPad(int padId) async {
    if (!_nativeChannelAvailable) return;
    try {
      await _channel.invokeMethod<dynamic>(
        'stopPad',
        <String, dynamic>{'padId': padId},
      );
    } on MissingPluginException {
      _nativeChannelAvailable = false;
    } on PlatformException {
      // Ignoré
    }
  }

  /// Coupe immédiatement tous les sons et boucles en cours (Bouton STOP / Panic).
  Future<void> stopAllPads() async {
    if (!_nativeChannelAvailable) return;
    try {
      await _channel.invokeMethod<dynamic>('stopAllPads');
    } on MissingPluginException {
      _nativeChannelAvailable = false;
    } on PlatformException {
      // Ignoré
    }
  }

  /// Démarre l'enregistrement via le microphone du téléphone pour la case `padId`.
  Future<bool> startMicRecording(int padId) async {
    _fallbackMicStartTime = DateTime.now();
    if (!_nativeChannelAvailable) {
      return true;
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'startMicRecording',
        <String, dynamic>{'padId': padId},
      );
      if (res != null && res['started'] == true) {
        return true;
      }
    } on MissingPluginException {
      _nativeChannelAvailable = false;
      return true;
    } on PlatformException catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        rethrow;
      }
      return true;
    }
    return true;
  }

  /// Lit l'amplitude instantanée (0.0..1.0) du microphone pour animer le VU-mètre.
  Future<double> getMicAmplitude() async {
    if (_nativeChannelAvailable) {
      try {
        final val = await _channel.invokeMethod<double>('getMicAmplitude');
        if (val != null) {
          return val.clamp(0.0, 1.0);
        }
      } on MissingPluginException {
        _nativeChannelAvailable = false;
      } on PlatformException {
        // Ignoré
      }
    }
    final elapsedMs = _fallbackMicStartTime != null
        ? DateTime.now().difference(_fallbackMicStartTime!).inMilliseconds
        : 200;
    return (0.25 + 0.55 * math.sin(elapsedMs / 95.0).abs()).clamp(0.05, 0.95);
  }

  /// Arrête l'enregistrement micro, applique l'Auto-Trim du silence et la normalisation,
  /// sauvegarde le fichier `.wav` et retourne le `SamplerPad` mis à jour.
  Future<SamplerPad> stopMicRecording(
    SamplerPad pad, {
    required bool autoTrimSilence,
    required bool normalize,
    String? customLabel,
  }) async {
    Uint8List? rawWavBytes;
    String? nativePath;

    if (_nativeChannelAvailable) {
      try {
        final res =
            await _channel.invokeMapMethod<String, dynamic>('stopMicRecording');
        if (res != null) {
          nativePath = res['path'] as String?;
          final raw = res['bytes'];
          if (raw is Uint8List && raw.length > 44) {
            rawWavBytes = raw;
          }
        }
      } on MissingPluginException {
        _nativeChannelAvailable = false;
      } on PlatformException {
        // Fallback
      }
    }

    if (rawWavBytes == null || rawWavBytes.length <= 100) {
      rawWavBytes = _buildSyntheticMicTakeWav(pad.id);
    }

    final processed = WavDspService.processRecordedMicWav(
      rawWavBytes,
      autoTrimSilence: autoTrimSilence,
      normalize: normalize,
    );

    final baseDir = await _resolveStorageDir();
    final samplesDir = Directory('${baseDir.path}/samples');
    if (!samplesDir.existsSync()) {
      samplesDir.createSync(recursive: true);
    }

    final finalPath = nativePath ??
        '${samplesDir.path}/mic_pad_${pad.id}_${DateTime.now().millisecondsSinceEpoch}.wav';
    File(finalPath).writeAsBytesSync(processed.wavBytes, flush: true);

    final label = (customLabel != null && customLabel.trim().isNotEmpty)
        ? customLabel.trim().toUpperCase()
        : 'MICRO ${(pad.id + 1).toString().padLeft(2, '0')}';

    final updated = pad.copyWith(
      label: label,
      source: PadSoundSource.microphone,
      filePath: finalPath,
      activePlaybackPath: finalPath,
      originalFileName: 'micro_pad_${pad.id + 1}.wav',
      clearSynthPreset: true,
      durationMs: processed.durationMs,
      waveformPeaks: processed.waveformPeaks,
      trimStart: 0.0,
      trimEnd: 1.0,
      autoTrimSilence: autoTrimSilence,
      normalizeOnRecord: normalize,
    );

    if (_nativeChannelAvailable) {
      try {
        await _channel.invokeMethod<dynamic>(
          'preloadPadSound',
          <String, dynamic>{
            'padId': updated.id,
            'filePath': finalPath,
          },
        );
      } catch (_) {}
    }

    return updated;
  }

  /// Ouvre le sélecteur de fichiers de l'appareil pour importer un fichier WAV / audio sur `pad`.
  Future<SamplerPad?> pickAudioFileForPad(SamplerPad pad) async {
    if (!_nativeChannelAvailable) {
      final demo = WavDspService.generatePresetWav(
        SynthPresetKind.values[(pad.id + 4) % SynthPresetKind.values.length],
      );
      return importAudioBytesToPad(
        pad: pad,
        fileName: 'sample_pad_${pad.id + 1}.wav',
        bytes: demo.wavBytes,
      );
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'pickAudioFile',
        <String, dynamic>{'padId': pad.id},
      );
      if (res == null) {
        return null; // Annulé par l'utilisateur
      }
      final path = res['path'] as String?;
      final fileName = res['fileName'] as String? ?? 'sample.wav';
      final rawBytes = res['bytes'];

      if (path == null || path.isEmpty) {
        return null;
      }

      Uint8List bytes;
      if (rawBytes is Uint8List && rawBytes.isNotEmpty) {
        bytes = rawBytes;
      } else if (File(path).existsSync()) {
        bytes = File(path).readAsBytesSync();
      } else {
        return null;
      }

      return await importAudioBytesToPad(
        pad: pad,
        fileName: fileName,
        bytes: bytes,
        existingPath: path,
      );
    } on MissingPluginException {
      // En test widget sans sélecteur Android natif, génère un import WAV de démonstration
      final demo = WavDspService.generatePresetWav(
        SynthPresetKind.values[(pad.id + 4) % SynthPresetKind.values.length],
      );
      return importAudioBytesToPad(
        pad: pad,
        fileName: 'sample_pad_${pad.id + 1}.wav',
        bytes: demo.wavBytes,
      );
    }
  }

  /// Assigne directement des octets d'un fichier WAV/audio à un pad.
  Future<SamplerPad> importAudioBytesToPad({
    required SamplerPad pad,
    required String fileName,
    required Uint8List bytes,
    String? existingPath,
  }) async {
    final analysis = WavDspService.analyzeAudioBytes(bytes);
    final baseDir = await _resolveStorageDir();
    final samplesDir = Directory('${baseDir.path}/samples');
    if (!samplesDir.existsSync()) {
      samplesDir.createSync(recursive: true);
    }

    final savedPath = existingPath ??
        '${samplesDir.path}/import_pad_${pad.id}_${DateTime.now().millisecondsSinceEpoch}.wav';
    if (existingPath == null || !File(savedPath).existsSync()) {
      File(savedPath).writeAsBytesSync(analysis.wavBytes, flush: true);
    }

    final cleanLabel = _formatFileNameAsPadLabel(fileName, pad.id);

    final updated = pad.copyWith(
      label: cleanLabel,
      source: PadSoundSource.file,
      filePath: savedPath,
      activePlaybackPath: savedPath,
      originalFileName: fileName,
      clearSynthPreset: true,
      durationMs: analysis.durationMs,
      waveformPeaks: analysis.waveformPeaks,
      trimStart: 0.0,
      trimEnd: 1.0,
    );

    if (_nativeChannelAvailable) {
      try {
        await _channel.invokeMethod<dynamic>(
          'preloadPadSound',
          <String, dynamic>{
            'padId': updated.id,
            'filePath': savedPath,
          },
        );
      } catch (_) {}
    }

    return updated;
  }

  /// Assigne l'un des 16 instruments du Kit Studio 808 à la case `pad`.
  Future<SamplerPad> assignSynthPresetToPad(
    SamplerPad pad,
    SynthPresetKind preset,
  ) async {
    final analysis = _presetCache[preset] ?? WavDspService.generatePresetWav(preset);
    final presetPath = _presetFilePaths[preset];

    final updated = pad.copyWith(
      label: preset.defaultLabel,
      source: PadSoundSource.synthPreset,
      filePath: presetPath,
      activePlaybackPath: presetPath,
      originalFileName: '${preset.name}.wav',
      synthPreset: preset,
      durationMs: analysis.durationMs,
      waveformPeaks: analysis.waveformPeaks,
      trimStart: 0.0,
      trimEnd: 1.0,
      chokeGroup: preset.defaultChokeGroup,
    );

    if (presetPath != null) {
      try {
        await _channel.invokeMethod<dynamic>(
          'preloadPadSound',
          <String, dynamic>{
            'padId': updated.id,
            'filePath': presetPath,
          },
        );
      } catch (_) {}
    }

    return updated;
  }

  /// Recalcule le fichier WAV découpé lorsque l'utilisateur ajuste `trimStart` ou `trimEnd`.
  Future<SamplerPad> applyTrimToPad(
    SamplerPad pad, {
    required double trimStart,
    required double trimEnd,
  }) async {
    final safeStart = trimStart.clamp(0.0, 0.92);
    final safeEnd = trimEnd.clamp(safeStart + 0.05, 1.0);
    final sourcePath = pad.filePath ??
        (pad.synthPreset != null ? _presetFilePaths[pad.synthPreset!] : null);

    if (sourcePath == null || !File(sourcePath).existsSync()) {
      return pad.copyWith(trimStart: safeStart, trimEnd: safeEnd);
    }

    if (safeStart <= 0.005 && safeEnd >= 0.995) {
      final restored = pad.copyWith(
        trimStart: 0.0,
        trimEnd: 1.0,
        activePlaybackPath: sourcePath,
      );
      try {
        await _channel.invokeMethod<dynamic>(
          'preloadPadSound',
          <String, dynamic>{
            'padId': restored.id,
            'filePath': sourcePath,
          },
        );
      } catch (_) {}
      return restored;
    }

    final rawBytes = File(sourcePath).readAsBytesSync();
    final slicedBytes = WavDspService.sliceWavBytes(
      rawBytes,
      trimStart: safeStart,
      trimEnd: safeEnd,
    );

    if (slicedBytes == null) {
      return pad.copyWith(trimStart: safeStart, trimEnd: safeEnd);
    }

    final baseDir = await _resolveStorageDir();
    final trimmedPath =
        '${baseDir.path}/samples/trimmed_pad_${pad.id}_${DateTime.now().millisecondsSinceEpoch}.wav';
    File(trimmedPath).writeAsBytesSync(slicedBytes, flush: true);

    final updated = pad.copyWith(
      trimStart: safeStart,
      trimEnd: safeEnd,
      activePlaybackPath: trimmedPath,
    );

    try {
      await _channel.invokeMethod<dynamic>(
        'preloadPadSound',
        <String, dynamic>{
          'padId': updated.id,
          'filePath': trimmedPath,
        },
      );
    } catch (_) {}

    return updated;
  }

  /// Exporte l'échantillon WAV d'un pad dans le dossier `Music/LifeSampler/` du téléphone.
  Future<String> exportPadWavToDevice(SamplerPad pad) async {
    final path = resolvePlayablePath(pad);
    Uint8List bytes;
    if (path != null && File(path).existsSync()) {
      bytes = File(path).readAsBytesSync();
    } else {
      final fallback = WavDspService.generatePresetWav(
        pad.synthPreset ?? SynthPresetKind.kick808,
      );
      bytes = fallback.wavBytes;
    }

    final safeLabel = pad.label
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final fileName = 'lifesampler_${(pad.id + 1).toString().padLeft(2, '0')}_$safeLabel.wav';

    if (_nativeChannelAvailable) {
      try {
        final savedLocation = await _channel.invokeMethod<String>(
          'exportPadWav',
          <String, dynamic>{
            'bytes': bytes,
            'fileName': fileName,
          },
        );
        if (savedLocation != null && savedLocation.isNotEmpty) {
          return savedLocation;
        }
      } on MissingPluginException {
        _nativeChannelAvailable = false;
      } on PlatformException {
        // Fallback
      }
    }

    final baseDir = await _resolveStorageDir();
    final outFile = File('${baseDir.path}/$fileName');
    outFile.writeAsBytesSync(bytes, flush: true);
    return outFile.path;
  }

  /// Sauvegarde l'état des 4 banques sur le stockage persistant de l'application.
  Future<void> saveBanks(List<SamplerBank> banks) async {
    try {
      final baseDir = await _resolveStorageDir();
      final stateFile = File('${baseDir.path}/lifesampler_banks_v2.json');
      final payload = jsonEncode(<String, dynamic>{
        'version': 2,
        'banks': banks.map((SamplerBank b) => b.toJson()).toList(growable: false),
      });
      stateFile.writeAsStringSync(payload, flush: true);
    } catch (_) {}
  }

  Future<List<SamplerBank>> _loadSavedBanks({
    required List<List<double>> defaultWaveforms,
    required List<int> defaultDurations,
  }) async {
    final defaultBanks = _createDefaultBanks(
      defaultWaveforms: defaultWaveforms,
      defaultDurations: defaultDurations,
    );

    try {
      final baseDir = await _resolveStorageDir();
      final stateFile = File('${baseDir.path}/lifesampler_banks_v2.json');
      if (!stateFile.existsSync()) {
        return defaultBanks;
      }
      final raw = stateFile.readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final rawBanks = decoded['banks'] as List<dynamic>?;
      if (rawBanks == null || rawBanks.isEmpty) {
        return defaultBanks;
      }

      final loaded = <SamplerBank>[];
      for (final item in rawBanks) {
        if (item is Map<String, dynamic>) {
          var bank = SamplerBank.fromJson(item);
          // Ré-attacher les chemins de fichiers des presets synthétiques si nécessaire
          final hydratedPads = bank.pads.map((SamplerPad pad) {
            if (pad.source == PadSoundSource.synthPreset &&
                pad.synthPreset != null) {
              final presetPath = _presetFilePaths[pad.synthPreset!];
              final analysis = _presetCache[pad.synthPreset!];
              return pad.copyWith(
                filePath: pad.filePath ?? presetPath,
                activePlaybackPath: pad.activePlaybackPath ?? presetPath,
                waveformPeaks: pad.waveformPeaks.isEmpty && analysis != null
                    ? analysis.waveformPeaks
                    : pad.waveformPeaks,
                durationMs: pad.durationMs <= 0 && analysis != null
                    ? analysis.durationMs
                    : pad.durationMs,
              );
            }
            return pad;
          }).toList(growable: false);
          bank = bank.copyWith(pads: hydratedPads);
          loaded.add(bank);
        }
      }
      if (loaded.length == 4) {
        return loaded;
      }
    } catch (_) {}

    return defaultBanks;
  }

  List<SamplerBank> _createDefaultBanks({
    required List<List<double>> defaultWaveforms,
    required List<int> defaultDurations,
  }) {
    final bankD = SamplerBank.createStudio808Bank(
      defaultWaveforms: defaultWaveforms,
      defaultDurationsMs: defaultDurations,
      id: 'D',
      name: 'BANQUE D',
      subtitle: 'Banque Studio 808 (16 Sons)',
    );
    final hydratedPadsD = bankD.pads.map((SamplerPad p) {
      final presetPath = p.synthPreset != null ? _presetFilePaths[p.synthPreset!] : null;
      return p.copyWith(
        filePath: presetPath,
        activePlaybackPath: presetPath,
      );
    }).toList(growable: false);

    return <SamplerBank>[
      SamplerBank.createEmptyBank(
        id: 'A',
        name: 'BANQUE A',
        subtitle: 'Sons de la Vie 1 — Micro & Audio',
      ),
      SamplerBank.createEmptyBank(
        id: 'B',
        name: 'BANQUE B',
        subtitle: 'Sons de la Vie 2 — Fun & Rires',
      ),
      SamplerBank.createEmptyBank(
        id: 'C',
        name: 'BANQUE C',
        subtitle: 'Sons de la Vie 3 — Bruitages',
      ),
      bankD.copyWith(pads: hydratedPadsD),
    ];
  }

  Future<Directory> _resolveStorageDir() async {
    if (_storageDir != null) {
      return _storageDir!;
    }
    if (_customStorageDir != null) {
      _storageDir = _customStorageDir;
      return _storageDir!;
    }
    try {
      final path = await _channel.invokeMethod<String>('getStorageDir');
      if (path != null && path.isNotEmpty) {
        final dir = Directory(path);
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        _storageDir = dir;
        return dir;
      }
    } on MissingPluginException {
      // Fallback
    } on PlatformException {
      // Fallback
    }
    final fallback = Directory('${Directory.systemTemp.path}/pulsepad16_storage');
    if (!fallback.existsSync()) {
      fallback.createSync(recursive: true);
    }
    _storageDir = fallback;
    return fallback;
  }

  Uint8List _buildSyntheticMicTakeWav(int padId) {
    // Génère un enregistrement micro simulé réaliste (avec 120 ms de silence au début
    // pour démontrer et tester l'Auto-Trim du silence)
    const sampleRate = WavDspService.defaultSampleRate;
    final silenceSamples = (0.12 * sampleRate).round();
    final voiceSamples = (0.38 * sampleRate).round();
    final total = silenceSamples + voiceSamples;
    final pcm = Int16List(total);
    final baseFreq = 140.0 + (padId % 8) * 28.0;
    var phase = 0.0;

    for (var i = 0; i < voiceSamples; i++) {
      final t = i / sampleRate;
      final freq = baseFreq * (1.0 + 0.15 * math.sin(t * 16.0));
      phase += 2.0 * math.pi * freq / sampleRate;
      final env = math.sin((i / voiceSamples) * math.pi);
      final val = (math.sin(phase) * 0.65 + 0.25 * math.sin(phase * 2.0)) * env;
      pcm[silenceSamples + i] = (val * 18000).round().clamp(-32768, 32767);
    }
    return WavDspService.encodePcm16MonoToWav(pcm, sampleRate: sampleRate);
  }

  String _formatFileNameAsPadLabel(String fileName, int padId) {
    var base = fileName.split('/').last.split(r'\').last;
    final dotIdx = base.lastIndexOf('.');
    if (dotIdx > 0) {
      base = base.substring(0, dotIdx);
    }
    base = base
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toUpperCase();
    if (base.isEmpty) {
      return 'WAV ${(padId + 1).toString().padLeft(2, '0')}';
    }
    return base.length > 11 ? base.substring(0, 11).trim() : base;
  }
}
