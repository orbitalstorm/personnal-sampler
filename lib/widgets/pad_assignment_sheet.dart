import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/sampler_models.dart';
import '../services/sampler_audio_engine.dart';
import 'waveform_painter.dart';

/// Fenêtre modale d'enregistrement et d'édition d'une des 16 cases de LifeSampler :
/// 1. Capture directe au Microphone ou import d'un fichier audio, avec Auto-Trim et Booster regroupés sur la même ligne ;
/// 2. Découpe sur forme d'onde (Trim Début / Fin) ;
/// 3. Réglages du pad : Mode (Cut / Poly / Loop), Volume, Pitch, Nom et Couleur ;
/// 4. Export direct du son enregistré en fichier WAV (`Music/LifeSampler/`).
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
                'Enregistrement en cours... Capturez votre son puis appuyez sur STOP.';
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
              'Son capturé sur ${_pad.padNumberLabel} (${updated.durationMs} ms).',
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
              'Audio "${updated.originalFileName ?? updated.label}" chargé sur ${_pad.padNumberLabel}.',
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
        _statusBanner = 'Son exporté : $path';
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
      constraints: BoxConstraints(maxHeight: screenHeight * 0.90),
      decoration: BoxDecoration(
        color: const Color(0xFF111420),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(
          top: BorderSide(color: padColor.withValues(alpha: 0.8), width: 2),
        ),
      ),
      padding: EdgeInsets.fromLTRB(14, 10, 14, 12 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Poignée supérieure
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // En-tête de la fenêtre Éditer
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: padColor.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: padColor, width: 1.4),
                ),
                child: Text(
                  _pad.padNumberLabel,
                  style: TextStyle(
                    color: padColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Éditer ${_pad.padNumberLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      _pad.hasSound
                          ? '${_pad.source.labelFr} • ${_pad.effectiveDurationMs} ms'
                          : 'Case vide — Enregistrez ou importez un son',
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
                SizedBox(
                  height: 36,
                  child: FilledButton.icon(
                    key: const Key('preview_pad_sound_button'),
                    onPressed: () {
                      unawaited(widget.audioEngine.triggerPad(_pad));
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: padColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text(
                      'ÉCOUTER',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_statusBanner != null) ...<Widget>[
                    Container(
                      key: const Key('pad_status_banner'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
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
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // SECTION 1 : CAPTURER OU IMPORTER UN SON (SANS PRÉ-RÉGLAGES STUDIO)
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181C2C),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Text(
                          '1. CAPTURER UN SON DE LA VIE',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Deux boutons principaux alignés : Micro & Fichier Audio
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: SizedBox(
                                height: 42,
                                child: ElevatedButton.icon(
                                  key: const Key('mic_record_toggle_button'),
                                  onPressed: _toggleMicRecording,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isRecordingMic
                                        ? const Color(0xFFDC2626)
                                        : const Color(0xFFEF4444),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                  ),
                                  icon: Icon(
                                    _isRecordingMic
                                        ? Icons.stop_circle_rounded
                                        : Icons.mic_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _isRecordingMic
                                        ? 'STOP (${(_recordingElapsedMs / 1000).toStringAsFixed(1)}s)'
                                        : 'MICRO',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: 42,
                                child: ElevatedButton.icon(
                                  key: const Key('import_wav_file_button'),
                                  onPressed:
                                      _isRecordingMic ? null : _pickAudioFile,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2563EB),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(11),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.folder_open_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'FICHIER AUDIO',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        // VU-Mètre en direct pendant l'enregistrement micro
                        if (_isRecordingMic) ...<Widget>[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              const Expanded(
                                child: Text(
                                  'NIVEAU MICRO EN DIRECT',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(_micAmplitude * 100).round()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              value: _micAmplitude.clamp(0.04, 1.0),
                              minHeight: 8,
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _micAmplitude > 0.8
                                    ? Colors.redAccent
                                    : Colors.greenAccent,
                              ),
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),

                        // Boutons Auto-Trim et Booster regroupés strictement sur la même ligne
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: _OptionToggleButton(
                                key: const Key('auto_trim_silence_chip'),
                                selected: _autoTrimSilence,
                                icon: Icons.content_cut_rounded,
                                label: 'Auto-Trim',
                                accentColor: padColor,
                                onTap: () {
                                  setState(() {
                                    _autoTrimSilence = !_autoTrimSilence;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _OptionToggleButton(
                                key: const Key('normalize_mic_chip'),
                                selected: _normalizeOnRecord,
                                icon: Icons.bolt_rounded,
                                label: 'Booster Micro',
                                accentColor: padColor,
                                onTap: () {
                                  setState(() {
                                    _normalizeOnRecord = !_normalizeOnRecord;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // SECTION 2 : FORME D'ONDE & DÉCOUPE (TRIM)
                  if (_pad.hasSound) ...<Widget>[
                    Container(
                      padding: const EdgeInsets.fromLTRB(11, 10, 11, 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF181C2C),
                        borderRadius: BorderRadius.circular(13),
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
                                  '2. DÉCOUPE DU SON (TRIM)',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(_pad.trimStart * 100).round()}% – ${(_pad.trimEnd * 100).round()}%',
                                style: TextStyle(
                                  color: padColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 44,
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
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                            ),
                            child: RangeSlider(
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
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // SECTION 3 : RÉGLAGES DU PAD (MODE, VOLUME, PITCH, NOM & COULEUR)
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: const Color(0xFF181C2C),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const Text(
                          '3. RÉGLAGES DU PAD',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Sélecteur de Mode : CUT / POLY / LOOP
                        Row(
                          children:
                              PadTriggerMode.values.map((PadTriggerMode mode) {
                            final selected = _pad.triggerMode == mode;
                            return Expanded(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                child: SizedBox(
                                  height: 36,
                                  child: OutlinedButton(
                                    key: Key('trigger_mode_${mode.name}'),
                                    onPressed: () {
                                      _commitPad(
                                        _pad.copyWith(triggerMode: mode),
                                      );
                                    },
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: selected
                                          ? padColor.withValues(alpha: 0.24)
                                          : const Color(0xFF111420),
                                      side: BorderSide(
                                        color:
                                            selected ? padColor : Colors.white24,
                                        width: selected ? 1.6 : 1.0,
                                      ),
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                    ),
                                    child: Text(
                                      mode.shortBadge,
                                      style: TextStyle(
                                        color: selected
                                            ? padColor
                                            : Colors.white70,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(growable: false),
                        ),
                        const SizedBox(height: 6),

                        // Volume (0% .. 150%)
                        SizedBox(
                          height: 32,
                          child: Row(
                            children: <Widget>[
                              const SizedBox(
                                width: 58,
                                child: Text(
                                  'Volume',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5,
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
                                width: 44,
                                child: Text(
                                  '${(_pad.volume * 100).round()}%',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Pitch / Vitesse (0.5x .. 2.0x)
                        SizedBox(
                          height: 32,
                          child: Row(
                            children: <Widget>[
                              const SizedBox(
                                width: 58,
                                child: Text(
                                  'Pitch',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11.5,
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
                                onTap: () =>
                                    _commitPad(_pad.copyWith(pitch: 1.0)),
                                child: SizedBox(
                                  width: 44,
                                  child: Text(
                                    '${_pad.pitch.toStringAsFixed(2)}×',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),

                        // Nom personnalisé du Pad + Couleur
                        Row(
                          children: <Widget>[
                            Expanded(
                              flex: 5,
                              child: SizedBox(
                                height: 38,
                                child: TextField(
                                  key: const Key('pad_label_text_field'),
                                  controller: _labelController,
                                  maxLength: 14,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Nom du pad',
                                    labelStyle: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 11,
                                    ),
                                    counterText: '',
                                    filled: true,
                                    fillColor: const Color(0xFF111420),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                  ),
                                  onChanged: (String val) {
                                    final trimmed = val.trim();
                                    if (trimmed.isNotEmpty) {
                                      widget.onPadUpdated(
                                        _pad.copyWith(
                                          label: trimmed.toUpperCase(),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 5,
                              child: SizedBox(
                                height: 28,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: kPadNeonPalette.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(width: 6),
                                  itemBuilder: (BuildContext context, int idx) {
                                    final c = kPadNeonPalette[idx];
                                    final isSelected = (_pad.colorIndex %
                                            kPadNeonPalette.length) ==
                                        idx;
                                    return GestureDetector(
                                      onTap: () => _commitPad(
                                        _pad.copyWith(colorIndex: idx),
                                      ),
                                      child: Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          color: c,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isSelected
                                                ? Colors.white
                                                : Colors.transparent,
                                            width: 2.2,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // BARRE D'ACTIONS INFÉRIEURE ÉPINGLÉE : EXPORT SON (.WAV), VIDER & VALIDER
          if (_pad.hasSound) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 38,
                    child: OutlinedButton.icon(
                      key: const Key('export_pad_wav_button'),
                      onPressed: _exportWav,
                      style: OutlinedButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF10B981).withValues(alpha: 0.16),
                        foregroundColor: const Color(0xFF34D399),
                        side: const BorderSide(
                          color: Color(0xFF10B981),
                          width: 1.3,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text(
                        'EXPORTER (.WAV)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 38,
                    child: OutlinedButton.icon(
                      key: const Key('clear_pad_button'),
                      onPressed: _clearPad,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text(
                        'VIDER',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.check_circle_rounded, size: 17),
                label: const Text(
                  'VALIDER LA CASE',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          ] else
            Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      key: const Key('export_pad_wav_button'),
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: const Color(0xFF151926),
                        foregroundColor: Colors.white30,
                        side: const BorderSide(
                          color: Colors.white12,
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 16),
                      label: const Text(
                        'EXPORTER (.WAV)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 40,
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
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle_rounded, size: 16),
                      label: const Text(
                        'VALIDER',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
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

/// Bouton bascule compact pour regrouper Auto-Trim et Booster Micro sur une seule ligne.
class _OptionToggleButton extends StatelessWidget {
  const _OptionToggleButton({
    super.key,
    required this.selected,
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? accentColor.withValues(alpha: 0.22)
              : const Color(0xFF111420),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? accentColor : Colors.white24,
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              selected ? Icons.check_circle_rounded : icon,
              size: 14,
              color: selected ? accentColor : Colors.white54,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
