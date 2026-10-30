import 'package:flutter/material.dart';

/// Source du son assigné à l'une des 16 cases du sampleur.
enum PadSoundSource {
  none,
  microphone,
  file,
  synthPreset,
}

extension PadSoundSourceX on PadSoundSource {
  String get labelFr {
    switch (this) {
      case PadSoundSource.none:
        return 'Vide';
      case PadSoundSource.microphone:
        return 'Micro';
      case PadSoundSource.file:
        return 'Fichier WAV';
      case PadSoundSource.synthPreset:
        return 'Studio Synth';
    }
  }

  IconData get icon {
    switch (this) {
      case PadSoundSource.none:
        return Icons.add_circle_outline_rounded;
      case PadSoundSource.microphone:
        return Icons.mic_rounded;
      case PadSoundSource.file:
        return Icons.audio_file_rounded;
      case PadSoundSource.synthPreset:
        return Icons.graphic_eq_rounded;
    }
  }
}

/// Mode de déclenchement d'une case lors d'appuis répétés.
enum PadTriggerMode {
  /// Coupe la lecture précédente de ce pad et relance immédiatement dès 0 ms.
  retrigger,

  /// Superpose chaque appui (polyphonique) jusqu'à la fin de l'échantillon.
  oneShot,

  /// Active ou arrête la lecture en boucle continue.
  loop,
}

extension PadTriggerModeX on PadTriggerMode {
  String get shortBadge {
    switch (this) {
      case PadTriggerMode.retrigger:
        return 'CUT';
      case PadTriggerMode.oneShot:
        return 'POLY';
      case PadTriggerMode.loop:
        return 'LOOP';
    }
  }

  String get titleFr {
    switch (this) {
      case PadTriggerMode.retrigger:
        return 'Cut (Redéclencher propre)';
      case PadTriggerMode.oneShot:
        return 'Poly (Superposer les appuis)';
      case PadTriggerMode.loop:
        return 'Loop (Boucle continue)';
    }
  }

  String get descriptionFr {
    switch (this) {
      case PadTriggerMode.retrigger:
        return 'Chaque appui relance immédiatement le son depuis le début sans empilement.';
      case PadTriggerMode.oneShot:
        return 'Chaque appui ajoute une voix simultanée jusqu’à la fin du son.';
      case PadTriggerMode.loop:
        return 'Un appui lance la boucle en continu, un second appui l’arrête.';
    }
  }
}

/// Les 16 instruments synthétisés du Kit Studio 808 intégré.
enum SynthPresetKind {
  kick808,
  snarePunch,
  clapStudio,
  closedHat,
  openHat,
  tomLow,
  tomMid,
  rimshot,
  cowbell,
  crashCymbal,
  subBass,
  acidBass,
  minorChord,
  majorStab,
  laserZap,
  riserFx,
}

extension SynthPresetKindX on SynthPresetKind {
  String get defaultLabel {
    switch (this) {
      case SynthPresetKind.kick808:
        return 'KICK 808';
      case SynthPresetKind.snarePunch:
        return 'SNARE';
      case SynthPresetKind.clapStudio:
        return 'CLAP';
      case SynthPresetKind.closedHat:
        return 'HAT CLSD';
      case SynthPresetKind.openHat:
        return 'HAT OPEN';
      case SynthPresetKind.tomLow:
        return 'TOM LOW';
      case SynthPresetKind.tomMid:
        return 'TOM MID';
      case SynthPresetKind.rimshot:
        return 'RIMSHOT';
      case SynthPresetKind.cowbell:
        return 'COWBELL';
      case SynthPresetKind.crashCymbal:
        return 'CRASH';
      case SynthPresetKind.subBass:
        return 'SUB BASS';
      case SynthPresetKind.acidBass:
        return 'ACID 303';
      case SynthPresetKind.minorChord:
        return 'CHORD MIN';
      case SynthPresetKind.majorStab:
        return 'STAB MAJ';
      case SynthPresetKind.laserZap:
        return 'LASER FX';
      case SynthPresetKind.riserFx:
        return 'SIREN FX';
    }
  }

  int get defaultChokeGroup {
    switch (this) {
      case SynthPresetKind.closedHat:
      case SynthPresetKind.openHat:
        return 1;
      default:
        return 0;
    }
  }
}

/// Palette de 16 couleurs néon haute visibilité pour la grille 4x4.
const List<Color> kPadNeonPalette = <Color>[
  Color(0xFFEF4444), // 01 Rouge Punch
  Color(0xFFF97316), // 02 Orange Ambre
  Color(0xFFEAB308), // 03 Jaune Solaire
  Color(0xFF84CC16), // 04 Citron Vert
  Color(0xFF10B981), // 05 Émeraude
  Color(0xFF14B8A6), // 06 Turquoise
  Color(0xFF06B6D4), // 07 Cyan Électrique
  Color(0xFF3B82F6), // 08 Bleu Azur
  Color(0xFF6366F1), // 09 Indigo
  Color(0xFF8B5CF6), // 10 Violet
  Color(0xFFD946EF), // 11 Magenta
  Color(0xFFEC4899), // 12 Rose Néon
  Color(0xFFF43F5E), // 13 Corail
  Color(0xFFFB923C), // 14 Or Cuivré
  Color(0xFF38BDF8), // 15 Ciel Polaire
  Color(0xFFA855F7), // 16 Pourpre Astral
];

/// Représente l'une des 16 cases (0..15) de la grille 4x4 du sampleur.
@immutable
class SamplerPad {
  const SamplerPad({
    required this.id,
    required this.label,
    required this.colorIndex,
    required this.source,
    this.filePath,
    this.activePlaybackPath,
    this.originalFileName,
    this.synthPreset,
    this.durationMs = 0,
    this.waveformPeaks = const <double>[],
    this.triggerMode = PadTriggerMode.retrigger,
    this.volume = 1.0,
    this.pitch = 1.0,
    this.trimStart = 0.0,
    this.trimEnd = 1.0,
    this.autoTrimSilence = true,
    this.normalizeOnRecord = true,
    this.chokeGroup = 0,
    this.triggerCount = 0,
  });

  final int id;
  final String label;
  final int colorIndex;
  final PadSoundSource source;
  final String? filePath;
  final String? activePlaybackPath;
  final String? originalFileName;
  final SynthPresetKind? synthPreset;
  final int durationMs;
  final List<double> waveformPeaks;
  final PadTriggerMode triggerMode;
  final double volume;
  final double pitch;
  final double trimStart;
  final double trimEnd;
  final bool autoTrimSilence;
  final bool normalizeOnRecord;
  final int chokeGroup;
  final int triggerCount;

  bool get hasSound =>
      source != PadSoundSource.none &&
      ((activePlaybackPath != null && activePlaybackPath!.isNotEmpty) ||
          (filePath != null && filePath!.isNotEmpty) ||
          synthPreset != null);

  String? get resolvedPlayPath => activePlaybackPath ?? filePath;

  Color get color => kPadNeonPalette[colorIndex % kPadNeonPalette.length];

  String get padNumberLabel => 'PAD ${(id + 1).toString().padLeft(2, '0')}';

  int get effectiveDurationMs {
    if (durationMs <= 0) return 0;
    final span = (trimEnd - trimStart).clamp(0.05, 1.0);
    return (durationMs * span / pitch.clamp(0.5, 2.0)).round();
  }

  SamplerPad copyWith({
    String? label,
    int? colorIndex,
    PadSoundSource? source,
    String? filePath,
    bool clearFilePath = false,
    String? activePlaybackPath,
    bool clearActivePlaybackPath = false,
    String? originalFileName,
    bool clearOriginalFileName = false,
    SynthPresetKind? synthPreset,
    bool clearSynthPreset = false,
    int? durationMs,
    List<double>? waveformPeaks,
    PadTriggerMode? triggerMode,
    double? volume,
    double? pitch,
    double? trimStart,
    double? trimEnd,
    bool? autoTrimSilence,
    bool? normalizeOnRecord,
    int? chokeGroup,
    int? triggerCount,
  }) {
    return SamplerPad(
      id: id,
      label: label ?? this.label,
      colorIndex: colorIndex ?? this.colorIndex,
      source: source ?? this.source,
      filePath: clearFilePath ? null : (filePath ?? this.filePath),
      activePlaybackPath: clearActivePlaybackPath
          ? null
          : (activePlaybackPath ?? this.activePlaybackPath),
      originalFileName: clearOriginalFileName
          ? null
          : (originalFileName ?? this.originalFileName),
      synthPreset: clearSynthPreset ? null : (synthPreset ?? this.synthPreset),
      durationMs: durationMs ?? this.durationMs,
      waveformPeaks: waveformPeaks ?? this.waveformPeaks,
      triggerMode: triggerMode ?? this.triggerMode,
      volume: volume ?? this.volume,
      pitch: pitch ?? this.pitch,
      trimStart: trimStart ?? this.trimStart,
      trimEnd: trimEnd ?? this.trimEnd,
      autoTrimSilence: autoTrimSilence ?? this.autoTrimSilence,
      normalizeOnRecord: normalizeOnRecord ?? this.normalizeOnRecord,
      chokeGroup: chokeGroup ?? this.chokeGroup,
      triggerCount: triggerCount ?? this.triggerCount,
    );
  }

  SamplerPad cleared() {
    return SamplerPad(
      id: id,
      label: 'VIDE ${(id + 1).toString().padLeft(2, '0')}',
      colorIndex: id % kPadNeonPalette.length,
      source: PadSoundSource.none,
      triggerMode: PadTriggerMode.retrigger,
      volume: 1.0,
      pitch: 1.0,
      trimStart: 0.0,
      trimEnd: 1.0,
      autoTrimSilence: true,
      normalizeOnRecord: true,
      chokeGroup: 0,
      triggerCount: 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'label': label,
      'colorIndex': colorIndex,
      'source': source.name,
      'filePath': filePath,
      'activePlaybackPath': activePlaybackPath,
      'originalFileName': originalFileName,
      'synthPreset': synthPreset?.name,
      'durationMs': durationMs,
      'waveformPeaks': waveformPeaks,
      'triggerMode': triggerMode.name,
      'volume': volume,
      'pitch': pitch,
      'trimStart': trimStart,
      'trimEnd': trimEnd,
      'autoTrimSilence': autoTrimSilence,
      'normalizeOnRecord': normalizeOnRecord,
      'chokeGroup': chokeGroup,
      'triggerCount': triggerCount,
    };
  }

  factory SamplerPad.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as num?)?.toInt() ?? 0;
    final sourceStr = json['source'] as String? ?? 'none';
    final source = PadSoundSource.values.firstWhere(
      (PadSoundSource e) => e.name == sourceStr,
      orElse: () => PadSoundSource.none,
    );
    final modeStr = json['triggerMode'] as String? ?? 'retrigger';
    final triggerMode = PadTriggerMode.values.firstWhere(
      (PadTriggerMode e) => e.name == modeStr,
      orElse: () => PadTriggerMode.retrigger,
    );
    final presetStr = json['synthPreset'] as String?;
    SynthPresetKind? preset;
    if (presetStr != null) {
      for (final candidate in SynthPresetKind.values) {
        if (candidate.name == presetStr) {
          preset = candidate;
          break;
        }
      }
    }
    final rawPeaks = json['waveformPeaks'] as List<dynamic>? ?? const <dynamic>[];
    final peaks = rawPeaks
        .map((dynamic v) => (v as num).toDouble().clamp(0.0, 1.0))
        .toList(growable: false);

    return SamplerPad(
      id: id,
      label: json['label'] as String? ?? 'PAD ${(id + 1).toString().padLeft(2, '0')}',
      colorIndex: (json['colorIndex'] as num?)?.toInt() ?? (id % kPadNeonPalette.length),
      source: source,
      filePath: json['filePath'] as String?,
      activePlaybackPath: json['activePlaybackPath'] as String?,
      originalFileName: json['originalFileName'] as String?,
      synthPreset: preset,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      waveformPeaks: peaks,
      triggerMode: triggerMode,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      pitch: (json['pitch'] as num?)?.toDouble() ?? 1.0,
      trimStart: (json['trimStart'] as num?)?.toDouble() ?? 0.0,
      trimEnd: (json['trimEnd'] as num?)?.toDouble() ?? 1.0,
      autoTrimSilence: json['autoTrimSilence'] as bool? ?? true,
      normalizeOnRecord: json['normalizeOnRecord'] as bool? ?? true,
      chokeGroup: (json['chokeGroup'] as num?)?.toInt() ?? 0,
      triggerCount: (json['triggerCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Banque de 16 cases (grille 4x4).
@immutable
class SamplerBank {
  const SamplerBank({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.pads,
  }) : assert(pads.length == 16, 'Une banque doit contenir exactement 16 cases (4x4).');

  final String id;
  final String name;
  final String subtitle;
  final List<SamplerPad> pads;

  bool get isStudioBank => id == 'D';

  int get assignedCount => pads.where((SamplerPad p) => p.hasSound).length;

  SamplerBank copyWithPad(SamplerPad updatedPad) {
    final nextPads = List<SamplerPad>.generate(
      16,
      (int index) => index == updatedPad.id ? updatedPad : pads[index],
      growable: false,
    );
    return SamplerBank(
      id: id,
      name: name,
      subtitle: subtitle,
      pads: nextPads,
    );
  }

  SamplerBank copyWith({
    String? name,
    String? subtitle,
    List<SamplerPad>? pads,
  }) {
    return SamplerBank(
      id: id,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      pads: pads ?? this.pads,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'subtitle': subtitle,
      'pads': pads.map((SamplerPad p) => p.toJson()).toList(growable: false),
    };
  }

  factory SamplerBank.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? 'A';
    final name = json['name'] as String? ?? 'Banque $id';
    final subtitle = json['subtitle'] as String? ?? 'Grille 4x4';
    final rawPads = json['pads'] as List<dynamic>? ?? const <dynamic>[];
    final parsedPads = <SamplerPad>[];
    for (var i = 0; i < 16; i++) {
      if (i < rawPads.length && rawPads[i] is Map<String, dynamic>) {
        parsedPads.add(SamplerPad.fromJson(rawPads[i] as Map<String, dynamic>));
      } else {
        parsedPads.add(
          SamplerPad(
            id: i,
            label: 'VIDE ${(i + 1).toString().padLeft(2, '0')}',
            colorIndex: i,
            source: PadSoundSource.none,
          ),
        );
      }
    }
    return SamplerBank(
      id: id,
      name: name,
      subtitle: subtitle,
      pads: parsedPads,
    );
  }

  /// Banque D pré-chargée avec les 16 sons du Kit Studio 808.
  factory SamplerBank.createStudio808Bank({
    required List<List<double>> defaultWaveforms,
    required List<int> defaultDurationsMs,
    String id = 'D',
    String name = 'BANQUE D',
    String subtitle = 'Banque Studio 808 (16 Sons)',
  }) {
    const presets = SynthPresetKind.values;
    final pads = List<SamplerPad>.generate(16, (int index) {
      final preset = presets[index];
      return SamplerPad(
        id: index,
        label: preset.defaultLabel,
        colorIndex: index,
        source: PadSoundSource.synthPreset,
        synthPreset: preset,
        durationMs: index < defaultDurationsMs.length ? defaultDurationsMs[index] : 320,
        waveformPeaks: index < defaultWaveforms.length
            ? defaultWaveforms[index]
            : const <double>[0.9, 0.7, 0.5, 0.3, 0.15, 0.08],
        triggerMode: index >= 10 ? PadTriggerMode.retrigger : PadTriggerMode.oneShot,
        chokeGroup: preset.defaultChokeGroup,
      );
    }, growable: false);

    return SamplerBank(
      id: id,
      name: name,
      subtitle: subtitle,
      pads: pads,
    );
  }

  /// Banque vierge de 16 pads prête pour l'enregistrement Micro ou l'import WAV.
  factory SamplerBank.createEmptyBank({
    required String id,
    required String name,
    required String subtitle,
  }) {
    final pads = List<SamplerPad>.generate(
      16,
      (int index) => SamplerPad(
        id: index,
        label: 'VIDE ${(index + 1).toString().padLeft(2, '0')}',
        colorIndex: index,
        source: PadSoundSource.none,
      ),
      growable: false,
    );
    return SamplerBank(
      id: id,
      name: name,
      subtitle: subtitle,
      pads: pads,
    );
  }
}

/// Événement horodaté d'un appui sur un pad dans le séquenceur/looper live.
@immutable
class RecordedLoopEvent {
  const RecordedLoopEvent({
    required this.padId,
    required this.offsetMs,
  });

  final int padId;
  final int offsetMs;
}
