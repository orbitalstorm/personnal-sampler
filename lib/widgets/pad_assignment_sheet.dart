import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sampler_models.dart';
import '../services/sampler_audio_engine.dart';
import 'waveform_painter.dart';

/// Fenêtre modale d'assignation et d'édition complète d'une des 16 cases :
/// 1. Enregistrement direct avec le Microphone (avec VU-mètre, Auto-Trim du silence et Normalisation) ;
/// 2. Import d'un fichier WAV / Audio depuis l'appareil ;
/// 3. Sélection optionnelle parmi les 16 sons du Kit Studio 808 ;
/// 4. Réglages fins : Mode (Cut / Poly / Loop), Découpe Waveform (Trim Début/Fin), Volume, Pitch, Nom et Couleur.
class PadAssignmentSheet extends StatefulWidget {
  const PadAssignmentSheet({
    super.key,
    required this.initialPad,
    required this.audioEngine,
    required this.onPadUpdated,
    this.openInRecordFocus = true,
  });

  final SamplerPad initialPad;
  final SamplerAudioEngine audioEngine;
  final ValueChanged<SamplerPad> onPadUpdated;
  final bool openInRecordFocus;

  @override
  State<PadAssignmentSheet> createState() => _PadAssignmentSheetState();
}

class _PadAssignmentSheetState extends State<PadAssignmentSheet> {
  late SamplerPad _pad;
  late TextEditingController _labelController;

  bool _isRecordingMic = false;
  double _micAmplitude = 0.0;
  int _recordingElapsedMs = 0;
  Timer? _micPollTimer;
  DateTime? _micStartTime;

  bool _autoTrimSilence = true;
  bool _normalizeOnRecord = true;
  bool _isBusy = false;
  String? _statusBanner;
  bool _isStatusError = false;

  @override
  void initState() {
    super.initState();
    _pad = widget.initialPad;
    _autoTrimSilence = _pad.autoTrimSilence;
    _normalizeOnRecord = _pad.normalizeOnRecord;
    _labelController = TextEditingController(text: _pad.label);
  }

  @override
  void dispose() {
    _micPollTimer?.cancel();
    _labelController.dispose();
    super.dispose();
  }

  void _commitPad(SamplerPad nextPad, {String? statusMessage}) {
    setState(() {
      _pad = nextPad;
      if (_labelController.text != nextPad.label) {
        _labelController.text = nextPad.label;
      }
      if (statusMessage != null) {
        _statusBanner = statusMessage;
        _isStatusError = false;
      }
    });
    widget.onPadUpdated(nextPad);
  }

  Future<void> _toggleMicRecording() async {
    if (_isBusy) return;
    if (!_isRecordingMic) {
      try {
        final started = await widget.audioEngine.startMicRecording(_pad.id);
        if (!mounted) return;
        if (started) {
          setState(() {
            _isRecordingMic = true;
            _micAmplitude = 0.15;
            _recordingElapsedMs = 0;
            _micStartTime = DateTime.now();
            _statusBanner =
                'Enregistrement micro en cours... Parlez ou jouez un son puis appuyez sur STOP.';
            _isStatusError = false;
          });
          _micPollTimer?.cancel();
          _micPollTimer =
              Timer.periodic(const Duration(milliseconds: 60), (Timer _) async {
            if (!mounted || !_isRecordingMic) return;
            final amp = await widget.audioEngine.getMicAmplitude();
            if (!mounted || !_isRecordingMic) return;
            final elapsed = _micStartTime != null
                ? DateTime.now().difference(_micStartTime!).inMilliseconds
                : _recordingElapsedMs + 60;
            setState(() {
              _micAmplitude = amp;
              _recordingElapsedMs = elapsed;
            });
          });
        }
      } on PlatformException catch (e) {
        if (!mounted) return;
        setState(() {
          _statusBanner =
              e.message ?? 'Permission microphone requise pour enregistrer.';
          _isStatusError = true;
        });
      }
    } else {
      _micPollTimer?.cancel();
      setState(() {
        _isRecordingMic = false;
        _isBusy = true;
      });
      try {
        final customText = _labelController.text.trim();
        final preserveCustomLabel = customText.isNotEmpty &&
            !customText.startsWith('VIDE ') &&
            !customText.startsWith('PAD ');
        final updated = await widget.audioEngine.stopMicRecording(
          _pad,
          autoTrimSilence: _autoTrimSilence,
          normalize: _normalizeOnRecord,
          customLabel: preserveCustomLabel ? customText : null,
        );
        if (!mounted) return;
        _commitPad(
          updated,
          statusMessage:
              'Son micro enregistré et assigné à ${_pad.padNumberLabel} (${updated.durationMs} ms).',
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _statusBanner = 'Erreur lors de la finalisation micro : $e';
          _isStatusError = true;
        });
      } finally {
        if (mounted) {
          setState(() {
            _isBusy = false;
            _micAmplitude = 0.0;
          });
        }
      }
    }
  }

  Future<void> _pickAudioFile() async {
    if (_isBusy || _isRecordingMic) return;
    setState(() {
      _isBusy = true;
      _statusBanner = null;
    });
    try {
      final updated = await widget.audioEngine.pickAudioFileForPad(_pad);
      if (!mounted) return;
      if (updated != null) {
        _commitPad(
          updated,
          statusMessage:
              'Fichier "${updated.originalFileName ?? updated.label}" assigné à ${_pad.padNumberLabel}.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusBanner = 'Impossible de charger le fichier audio : $e';
        _isStatusError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _selectSynthPreset(SynthPresetKind preset) async {
    if (_isBusy || _isRecordingMic) return;
    setState(() {
      _isBusy = true;
    });
    try {
      final updated = await widget.audioEngine.assignSynthPresetToPad(_pad, preset);
      if (!mounted) return;
      _commitPad(
        updated,
        statusMessage:
            'Son studio "${preset.defaultLabel}" assigné à ${_pad.padNumberLabel}.',
      );
      unawaited(widget.audioEngine.triggerPad(updated));
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _updateTrim(RangeValues values) async {
    final start = values.start.clamp(0.0, 0.92);
    final end = values.end.clamp(start + 0.05, 1.0);
    setState(() {
      _pad = _pad.copyWith(trimStart: start, trimEnd: end);
    });
  }

  Future<void> _commitTrimEnd(RangeValues values) async {
    final updated = await widget.audioEngine.applyTrimToPad(
      _pad,
      trimStart: values.start,
      trimEnd: values.end,
    );
    if (!mounted) return;
    _commitPad(
      updated,
      statusMessage:
          'Découpe ajustée : ${(updated.trimStart * 100).round()}% → ${(updated.trimEnd * 100).round()}% (${updated.effectiveDurationMs} ms).',
    );
  }

  Future<void> _exportWav() async {
    if (!_pad.hasSound || _isBusy) return;
    setState(() {
      _isBusy = true;
    });
    try {
      final path = await widget.audioEngine.exportPadWavToDevice(_pad);
      if (!mounted) return;
      setState(() {
        _statusBanner = 'Exporté en WAV : $path';
        _isStatusError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusBanner = 'Erreur export WAV : $e';
        _isStatusError = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  void _clearPad() {
    unawaited(widget.audioEngine.stopPad(_pad.id));
    final cleared = _pad.cleared();
    _commitPad(
      cleared,
      statusMessage: '${_pad.padNumberLabel} réinitialisé (vide).',
    );
  }

  @override
  Widget build(BuildContext context) {
    final padColor = _pad.color;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      key: const Key('pad_assignment_sheet'),
      constraints: BoxConstraints(maxHeight: screenHeight * 0.88),
      decoration: BoxDecoration(
        color: const Color(0xFF111420),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: padColor.withValues(alpha: 0.75), width: 2),
        ),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 14 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Poignée supérieure
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // En-tête de la case sélectionnée
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: padColor.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: padColor, width: 1.4),
                ),
                child: Text(
                  _pad.padNumberLabel,
                  style: TextStyle(
                    color: padColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Assigner & Régler ${_pad.padNumberLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _pad.hasSound
                          ? 'Source : ${_pad.source.labelFr} • ${_pad.effectiveDurationMs} ms'
                          : 'Case vide — Micro ou fichier WAV',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (_pad.hasSound)
                FilledButton.icon(
                  key: const Key('preview_pad_sound_button'),
                  onPressed: () {
                    unawaited(widget.audioEngine.triggerPad(_pad));
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: padColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 17),
                  label: const Text(
                    'JOUER',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11.5),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_statusBanner != null) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _isStatusError
                            ? const Color(0xFF45121A)
                            : const Color(0xFF132F26),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _isStatusError
                              ? Colors.redAccent
                              : const Color(0xFF10B981),
                        ),
                      ),
                      child: Text(
                        _statusBanner!,
                        style: TextStyle(
                          color: _isStatusError
                              ? Colors.red.shade100
                              : Colors.greenAccent.shade100,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

            // SECTION 1 : ASSIGNATION DU SON (MICRO OU FICHIER WAV)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF181C2C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    '1. ASSIGNER UN SON À CETTE CASE (RECORD)',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Deux boutons principaux : Micro & Fichier WAV
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: ElevatedButton.icon(
                          key: const Key('mic_record_toggle_button'),
                          onPressed: _toggleMicRecording,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isRecordingMic
                                ? const Color(0xFFDC2626)
                                : const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Icon(
                            _isRecordingMic
                                ? Icons.stop_circle_rounded
                                : Icons.mic_rounded,
                            size: 20,
                          ),
                          label: Text(
                            _isRecordingMic
                                ? 'STOP (${(_recordingElapsedMs / 1000).toStringAsFixed(1)}s)'
                                : 'ENREGISTRER MICRO',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          key: const Key('import_wav_file_button'),
                          onPressed: _isRecordingMic ? null : _pickAudioFile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.folder_open_rounded, size: 20),
                          label: const Text(
                            'FICHIER WAV / AUDIO',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // VU-Mètre en direct pendant l'enregistrement micro
                  if (_isRecordingMic) ...<Widget>[
                    const SizedBox(height: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            const Text(
                              'NIVEAU MICRO EN DIRECT',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${(_micAmplitude * 100).round()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: _micAmplitude.clamp(0.04, 1.0),
                            minHeight: 10,
                            backgroundColor: Colors.white10,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _micAmplitude > 0.8
                                  ? Colors.redAccent
                                  : Colors.greenAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 8),
                  // Options intelligentes d'enregistrement micro
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      FilterChip(
                        key: const Key('auto_trim_silence_chip'),
                        selected: _autoTrimSilence,
                        onSelected: (bool val) {
                          setState(() {
                            _autoTrimSilence = val;
                          });
                        },
                        label: const Text(
                          'Auto-Trim Silence (0 ms latence)',
                          style: TextStyle(fontSize: 11),
                        ),
                        selectedColor: padColor.withValues(alpha: 0.28),
                        checkmarkColor: padColor,
                      ),
                      FilterChip(
                        key: const Key('normalize_mic_chip'),
                        selected: _normalizeOnRecord,
                        onSelected: (bool val) {
                          setState(() {
                            _normalizeOnRecord = val;
                          });
                        },
                        label: const Text(
                          'Booster & Normaliser Micro',
                          style: TextStyle(fontSize: 11),
                        ),
                        selectedColor: padColor.withValues(alpha: 0.28),
                        checkmarkColor: padColor,
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),
                  const Text(
                    'Sons Studio 808 intégrés (chargement rapide) :',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: SynthPresetKind.values.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (BuildContext context, int idx) {
                        final preset = SynthPresetKind.values[idx];
                        final isSelected =
                            _pad.source == PadSoundSource.synthPreset &&
                                _pad.synthPreset == preset;
                        return ActionChip(
                          key: Key('preset_chip_${preset.name}'),
                          backgroundColor: isSelected
                              ? padColor.withValues(alpha: 0.3)
                              : const Color(0xFF23283C),
                          side: BorderSide(
                            color: isSelected ? padColor : Colors.white12,
                          ),
                          label: Text(
                            preset.defaultLabel,
                            style: TextStyle(
                              color: isSelected ? padColor : Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () => _selectSynthPreset(preset),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // SECTION 2 : FORME D'ONDE & DÉCOUPE (TRIM IN / TRIM OUT)
            if (_pad.hasSound) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF181C2C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Expanded(
                          child: Text(
                            '2. FORME D’ONDE & DÉCOUPE (TRIM)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(_pad.trimStart * 100).round()}% - ${(_pad.trimEnd * 100).round()}%',
                          style: TextStyle(
                            color: padColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: CustomPaint(
                        painter: WaveformPainter(
                          peaks: _pad.waveformPeaks,
                          activeColor: padColor,
                          inactiveColor: Colors.white12,
                          trimStart: _pad.trimStart,
                          trimEnd: _pad.trimEnd,
                          showTrimHandles: true,
                        ),
                      ),
                    ),
                    RangeSlider(
                      key: const Key('pad_trim_range_slider'),
                      values: RangeValues(
                        _pad.trimStart.clamp(0.0, 0.92),
                        _pad.trimEnd.clamp(
                          (_pad.trimStart + 0.05).clamp(0.05, 1.0),
                          1.0,
                        ),
                      ),
                      min: 0.0,
                      max: 1.0,
                      activeColor: padColor,
                      inactiveColor: Colors.white12,
                      onChanged: _updateTrim,
                      onChangeEnd: _commitTrimEnd,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // SECTION 3 : MODE DE JEU, VOLUME, PITCH, NOM & COULEUR
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF181C2C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    '3. RÉGLAGES DU PAD (MODE, VOLUME, PITCH & IDENTITÉ)',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Sélecteur de Mode : CUT / POLY / LOOP
                  Row(
                    children: PadTriggerMode.values.map((PadTriggerMode mode) {
                      final selected = _pad.triggerMode == mode;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: OutlinedButton(
                            key: Key('trigger_mode_${mode.name}'),
                            onPressed: () {
                              _commitPad(_pad.copyWith(triggerMode: mode));
                            },
                            style: OutlinedButton.styleFrom(
                              backgroundColor: selected
                                  ? padColor.withValues(alpha: 0.24)
                                  : const Color(0xFF111420),
                              side: BorderSide(
                                color: selected ? padColor : Colors.white24,
                                width: selected ? 1.6 : 1.0,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            child: Text(
                              mode.shortBadge,
                              style: TextStyle(
                                color: selected ? padColor : Colors.white70,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(growable: false),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _pad.triggerMode.descriptionFr,
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),

                  const SizedBox(height: 10),

                  // Curseur de Volume (0% .. 150%)
                  Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 68,
                        child: Text(
                          'Volume',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          key: const Key('pad_volume_slider'),
                          value: _pad.volume.clamp(0.0, 1.5),
                          min: 0.0,
                          max: 1.5,
                          activeColor: padColor,
                          onChanged: (double v) {
                            _commitPad(_pad.copyWith(volume: v));
                          },
                        ),
                      ),
                      SizedBox(
                        width: 46,
                        child: Text(
                          '${(_pad.volume * 100).round()}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Curseur de Pitch / Vitesse (0.5x .. 2.0x)
                  Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 68,
                        child: Text(
                          'Pitch/Vit.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          key: const Key('pad_pitch_slider'),
                          value: _pad.pitch.clamp(0.5, 2.0),
                          min: 0.5,
                          max: 2.0,
                          activeColor: padColor,
                          onChanged: (double v) {
                            _commitPad(_pad.copyWith(pitch: v));
                          },
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _commitPad(_pad.copyWith(pitch: 1.0)),
                        child: SizedBox(
                          width: 46,
                          child: Text(
                            '${_pad.pitch.toStringAsFixed(2)}×',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Nom personnalisé du Pad
                  TextField(
                    key: const Key('pad_label_text_field'),
                    controller: _labelController,
                    maxLength: 14,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Nom affiché sur la case',
                      labelStyle: const TextStyle(color: Colors.white60),
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFF111420),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onChanged: (String val) {
                      final trimmed = val.trim();
                      if (trimmed.isNotEmpty) {
                        widget.onPadUpdated(
                          _pad.copyWith(label: trimmed.toUpperCase()),
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 10),

                  // Sélecteur de couleur néon
                  SizedBox(
                    height: 30,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: kPadNeonPalette.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (BuildContext context, int idx) {
                        final c = kPadNeonPalette[idx];
                        final isSelected =
                            (_pad.colorIndex % kPadNeonPalette.length) == idx;
                        return GestureDetector(
                          onTap: () => _commitPad(_pad.copyWith(colorIndex: idx)),
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.white : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Barre d'actions inférieure épinglée (Exporter WAV, Vider la case, Terminer)
          Row(
            children: <Widget>[
              if (_pad.hasSound) ...<Widget>[
                OutlinedButton.icon(
                  key: const Key('export_pad_wav_button'),
                  onPressed: _exportWav,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 15),
                  label: const Text('WAV', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  key: const Key('clear_pad_button'),
                  onPressed: _clearPad,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 15),
                  label: const Text('Vider', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: FilledButton.icon(
                  key: const Key('save_pad_assignment_button'),
                  onPressed: () async {
                    if (_isRecordingMic) {
                      await _toggleMicRecording();
                    }
                    final trimmed = _labelController.text.trim();
                    if (trimmed.isNotEmpty) {
                      widget.onPadUpdated(
                        _pad.copyWith(label: trimmed.toUpperCase()),
                      );
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: padColor,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text(
                    'VALIDER LA CASE',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
