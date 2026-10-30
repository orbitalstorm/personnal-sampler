import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/sampler_models.dart';
import '../services/sampler_audio_engine.dart';
import 'pad_assignment_sheet.dart';
import 'waveform_painter.dart';

/// Écran principal du sampleur 4x4 (16 cases) PulsePad 16.
class SamplerScreen extends StatefulWidget {
  const SamplerScreen({
    super.key,
    this.audioEngine,
  });

  final SamplerAudioEngine? audioEngine;

  @override
  State<SamplerScreen> createState() => _SamplerScreenState();
}

class _SamplerScreenState extends State<SamplerScreen> {
  late final SamplerAudioEngine _engine;

  List<SamplerBank> _banks = <SamplerBank>[];
  int _activeBankIndex = 0;
  bool _isLoading = true;

  /// Mode d'assignation activé par le bouton principal `RECORD`.
  bool _isRecordMode = false;

  /// Mode d'inspection/réglage d'un pad.
  bool _isEditMode = false;

  /// Pads actuellement illuminés suite à un appui.
  final Set<int> _flashingPads = <int>{};
  final Map<int, Timer> _flashTimers = <int, Timer>{};

  /// Pads actuellement en lecture boucle continue (`PadTriggerMode.loop`).
  final Set<int> _loopingPads = <int>{};

  /// Dernier pad déclenché (pour affichage dans le moniteur LCD supérieur).
  SamplerPad? _lastTriggeredPad;

  /// Métronome
  bool _metronomeActive = false;
  int _bpm = 120;
  int _currentBeat = 0;
  Timer? _metronomeTimer;
  final List<DateTime> _tapTempoTimestamps = <DateTime>[];

  /// Séquenceur / Looper de performance live
  bool _isRecordingSeq = false;
  bool _isPlayingSeq = false;
  DateTime? _seqStartTime;
  int _seqLoopLengthMs = 2000;
  final List<RecordedLoopEvent> _recordedSeqEvents = <RecordedLoopEvent>[];
  final List<Timer> _seqScheduledTimers = <Timer>[];
  Timer? _seqLoopRestartTimer;

  @override
  void initState() {
    super.initState();
    _engine = widget.audioEngine ?? SamplerAudioEngine();
    _banks = _engine.buildDefaultBanksSync();
    _activeBankIndex = 0;
    _isLoading = false;
    _lastTriggeredPad = _banks.first.pads.first;
    unawaited(_initSampler());
  }

  Future<void> _initSampler() async {
    final loadedBanks = await _engine.initialize();
    if (!mounted) return;
    // N'écrase pas les banques en mémoire si l'utilisateur a déjà commencé à jouer
    final hasUserActivity = _banks.any(
      (SamplerBank b) => b.pads.any((SamplerPad p) => p.triggerCount > 0),
    );
    if (!hasUserActivity) {
      setState(() {
        _banks = loadedBanks;
        _isLoading = false;
        _lastTriggeredPad = loadedBanks[_activeBankIndex].pads.first;
      });
    }
  }

  @override
  void dispose() {
    for (final timer in _flashTimers.values) {
      timer.cancel();
    }
    _metronomeTimer?.cancel();
    _stopSequenceTimers();
    super.dispose();
  }

  SamplerBank get _currentBank => _banks[_activeBankIndex];

  void _updatePadInCurrentBank(SamplerPad updatedPad) {
    setState(() {
      final updatedBank = _currentBank.copyWithPad(updatedPad);
      _banks = List<SamplerBank>.generate(
        _banks.length,
        (int idx) => idx == _activeBankIndex ? updatedBank : _banks[idx],
        growable: false,
      );
      _lastTriggeredPad = updatedPad;
      if (!updatedPad.hasSound || updatedPad.triggerMode != PadTriggerMode.loop) {
        _loopingPads.remove(updatedPad.id);
      }
    });
    unawaited(_engine.saveBanks(_banks));
  }

  Future<void> _switchBank(int index) async {
    if (index < 0 || index >= _banks.length || index == _activeBankIndex) {
      return;
    }
    await _engine.stopAllPads();
    setState(() {
      _activeBankIndex = index;
      _loopingPads.clear();
      _lastTriggeredPad = _banks[index].pads.first;
    });
    await _engine.preloadBank(_banks[index]);
  }

  Future<void> _handlePadTap(SamplerPad pad) async {
    if (_isRecordMode || _isEditMode || !pad.hasSound) {
      final openedFromRecord = _isRecordMode || !pad.hasSound;
      setState(() {
        _isRecordMode = false;
        _isEditMode = false;
      });
      await _openPadAssignmentSheet(pad, openInRecordFocus: openedFromRecord);
      return;
    }

    await _firePad(pad, recordToLooper: true);
  }

  Future<void> _firePad(SamplerPad pad, {required bool recordToLooper}) async {
    if (!pad.hasSound) return;

    // Illumination visuelle instantanée + incrément du compteur d'appuis
    _flashTimers[pad.id]?.cancel();
    final updatedPad = pad.copyWith(triggerCount: pad.triggerCount + 1);
    final updatedBank = _currentBank.copyWithPad(updatedPad);

    setState(() {
      _flashingPads.add(pad.id);
      _banks = List<SamplerBank>.generate(
        _banks.length,
        (int idx) => idx == _activeBankIndex ? updatedBank : _banks[idx],
        growable: false,
      );
      _lastTriggeredPad = updatedPad;
    });

    _flashTimers[pad.id] = Timer(const Duration(milliseconds: 140), () {
      if (!mounted) return;
      setState(() {
        _flashingPads.remove(pad.id);
      });
    });

    if (recordToLooper && _isRecordingSeq && _seqStartTime != null) {
      final offset = DateTime.now().difference(_seqStartTime!).inMilliseconds;
      _recordedSeqEvents.add(
        RecordedLoopEvent(
          padId: pad.id,
          offsetMs: offset % math.max(500, _seqLoopLengthMs),
        ),
      );
    }

    final outcome = await _engine.triggerPad(updatedPad);
    if (!mounted) return;
    setState(() {
      if (updatedPad.triggerMode == PadTriggerMode.loop) {
        if (outcome.looping) {
          _loopingPads.add(updatedPad.id);
        } else {
          _loopingPads.remove(updatedPad.id);
        }
      } else {
        _loopingPads.remove(updatedPad.id);
      }
    });
  }

  Future<void> _openPadAssignmentSheet(
    SamplerPad pad, {
    required bool openInRecordFocus,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return PadAssignmentSheet(
          initialPad: pad,
          audioEngine: _engine,
          openInRecordFocus: openInRecordFocus,
          onPadUpdated: _updatePadInCurrentBank,
        );
      },
    );
  }

  Future<void> _stopAllSounds() async {
    await _engine.stopAllPads();
    _stopSequenceTimers();
    if (!mounted) return;
    setState(() {
      _loopingPads.clear();
      _flashingPads.clear();
      _isRecordingSeq = false;
      _isPlayingSeq = false;
    });
  }

  void _toggleMetronome() {
    setState(() {
      _metronomeActive = !_metronomeActive;
      _currentBeat = 0;
    });
    _restartMetronomeTimer();
  }

  void _changeBpm(int delta) {
    setState(() {
      _bpm = (_bpm + delta).clamp(40, 220);
      // Ajuster la durée d'une mesure 4/4 pour le séquenceur live
      _seqLoopLengthMs = ((60000.0 / _bpm) * 4.0).round();
    });
    if (_metronomeActive) {
      _restartMetronomeTimer();
    }
  }

  void _handleTapTempo() {
    final now = DateTime.now();
    _tapTempoTimestamps.removeWhere(
      (DateTime t) => now.difference(t).inMilliseconds > 3000,
    );
    _tapTempoTimestamps.add(now);
    if (_tapTempoTimestamps.length >= 2) {
      var totalIntervals = 0;
      for (var i = 1; i < _tapTempoTimestamps.length; i++) {
        totalIntervals += _tapTempoTimestamps[i]
            .difference(_tapTempoTimestamps[i - 1])
            .inMilliseconds;
      }
      final avgMs = totalIntervals / (_tapTempoTimestamps.length - 1);
      if (avgMs > 250 && avgMs < 1500) {
        final computedBpm = (60000.0 / avgMs).round().clamp(40, 220);
        setState(() {
          _bpm = computedBpm;
          _seqLoopLengthMs = ((60000.0 / _bpm) * 4.0).round();
        });
        if (_metronomeActive) {
          _restartMetronomeTimer();
        }
      }
    }
  }

  void _restartMetronomeTimer() {
    _metronomeTimer?.cancel();
    if (!_metronomeActive) return;

    final intervalMs = (60000.0 / _bpm).round().clamp(250, 1500);
    unawaited(_engine.triggerMetronomeClick(isDownbeat: true));
    _metronomeTimer =
        Timer.periodic(Duration(milliseconds: intervalMs), (Timer _) {
      if (!mounted || !_metronomeActive) return;
      setState(() {
        _currentBeat = (_currentBeat + 1) % 4;
      });
      unawaited(
        _engine.triggerMetronomeClick(isDownbeat: _currentBeat == 0),
      );
    });
  }

  void _toggleSeqRecording() {
    if (_isRecordingSeq) {
      // Fin de l'enregistrement de la boucle -> passe en lecture automatique
      final elapsed = _seqStartTime != null
          ? DateTime.now().difference(_seqStartTime!).inMilliseconds
          : 2000;
      setState(() {
        _isRecordingSeq = false;
        _seqLoopLengthMs = elapsed.clamp(800, 8000);
      });
      if (_recordedSeqEvents.isNotEmpty) {
        _startSequencePlayback();
      }
    } else {
      _stopSequenceTimers();
      setState(() {
        _recordedSeqEvents.clear();
        _isPlayingSeq = false;
        _isRecordingSeq = true;
        _seqStartTime = DateTime.now();
        _seqLoopLengthMs = ((60000.0 / _bpm) * 4.0).round().clamp(1200, 6000);
      });
    }
  }

  void _toggleSeqPlayback() {
    if (_isPlayingSeq) {
      _stopSequenceTimers();
      setState(() {
        _isPlayingSeq = false;
      });
    } else if (_recordedSeqEvents.isNotEmpty) {
      _startSequencePlayback();
    }
  }

  void _startSequencePlayback() {
    _stopSequenceTimers();
    if (_recordedSeqEvents.isEmpty) return;

    setState(() {
      _isPlayingSeq = true;
      _isRecordingSeq = false;
    });

    void scheduleCycle() {
      if (!mounted || !_isPlayingSeq) return;
      for (final ev in _recordedSeqEvents) {
        final t = Timer(Duration(milliseconds: ev.offsetMs), () {
          if (!mounted || !_isPlayingSeq) return;
          if (ev.padId >= 0 && ev.padId < _currentBank.pads.length) {
            unawaited(
              _firePad(_currentBank.pads[ev.padId], recordToLooper: false),
            );
          }
        });
        _seqScheduledTimers.add(t);
      }
    }

    scheduleCycle();
    _seqLoopRestartTimer = Timer.periodic(
      Duration(milliseconds: _seqLoopLengthMs.clamp(800, 8000)),
      (Timer _) => scheduleCycle(),
    );
  }

  void _clearSequence() {
    _stopSequenceTimers();
    setState(() {
      _recordedSeqEvents.clear();
      _isRecordingSeq = false;
      _isPlayingSeq = false;
    });
  }

  void _stopSequenceTimers() {
    _seqLoopRestartTimer?.cancel();
    _seqLoopRestartTimer = null;
    for (final t in _seqScheduledTimers) {
      t.cancel();
    }
    _seqScheduledTimers.clear();
  }

  Future<void> _resetCurrentBank() async {
    await _engine.stopAllPads();
    final freshBanks = await SamplerAudioEngine().initialize();
    if (!mounted) return;
    setState(() {
      _banks = List<SamplerBank>.generate(
        _banks.length,
        (int idx) => idx == _activeBankIndex ? freshBanks[idx] : _banks[idx],
        growable: false,
      );
      _loopingPads.clear();
    });
    await _engine.saveBanks(_banks);
    await _engine.preloadBank(_currentBank);
  }

  void _showFeaturesGuideDialog() {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141826),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: <Widget>[
              Icon(Icons.grid_view_rounded, color: Color(0xFFEF4444)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'PulsePad 16 — Guide & Features',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _FeatureGuideItem(
                  title: '1. Grille 4×4 (16 Cases) Ultra-Réactive',
                  body:
                      'Appuyez sur n’importe quelle case autant de fois que vous le souhaitez pour jouer et rejouer le son instantanément.',
                ),
                _FeatureGuideItem(
                  title: '2. Bouton RECORD (Micro ou Fichier WAV)',
                  body:
                      'Appuyez sur RECORD puis touchez l’une des 16 cases pour enregistrer un son avec le microphone ou récupérer un fichier WAV/audio depuis votre téléphone.',
                ),
                _FeatureGuideItem(
                  title: '3. Auto-Trim Silence & Découpe Waveform',
                  body:
                      'Coupe automatiquement le silence au début des enregistrements micro (0 ms de retard) et permet d’ajuster le Début/Fin sur la forme d’onde.',
                ),
                _FeatureGuideItem(
                  title: '4. Modes CUT / POLY / LOOP + Pitch & Volume',
                  body:
                      'Choisissez par case entre Cut (redéclenchement net), Poly (superposition) ou Loop (boucle continue), et réglez le Volume (0–150%) et le Pitch (0.5×–2.0×).',
                ),
                _FeatureGuideItem(
                  title: '5. 4 Banques Persistées + Métronome & Looper',
                  body:
                      'La Banque A contient 16 sons Studio 808 prêts à jouer, les Banques B/C/D accueillent vos créations personnelles, et le Séquenceur enregistre vos boucles en direct.',
                ),
              ],
            ),
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('COMPRIS'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _banks.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0D14),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFEF4444)),
        ),
      );
    }

    final bank = _currentBank;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0D14),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // 1. EN-TÊTE STUDIO & MONITEUR LCD
              _buildTopHeader(bank),
              const SizedBox(height: 6),

              // 2. SÉLECTEUR DES 4 BANQUES (A / B / C / D)
              _buildBankSelectorRow(),
              const SizedBox(height: 6),

              // 3. BARRE DE COMMANDE PRINCIPALE : BOUTON RECORD / ÉDITER / STOP
              _buildPrimaryTransportBar(),
              const SizedBox(height: 6),

              // 4. BANDEAU D'INSTRUCTION CONTEXTUEL (MODE RECORD OU ÉDITION)
              if (_isRecordMode || _isEditMode) ...<Widget>[
                _buildModeBanner(),
                const SizedBox(height: 6),
              ],

              // 5. GRILLE CENTRALE 4x4 (16 CASES)
              Expanded(
                child: _buildPadGrid4x4(bank),
              ),
              const SizedBox(height: 6),

              // 6. CONSOLE RYTHMIQUE INFÉRIEURE (MÉTRONOME BPM + SÉQUENCEUR LOOPER)
              _buildBottomRhythmConsole(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(SamplerBank bank) {
    final lastPad = _lastTriggeredPad;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF131724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFFEF4444), Color(0xFFF97316)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.grid_4x4_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Flexible(
                      child: Text(
                        'PULSEPAD 16',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '${bank.assignedCount}/16',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  lastPad != null && lastPad.hasSound
                      ? '${lastPad.padNumberLabel} • ${lastPad.label} (${lastPad.source.labelFr} • ${lastPad.effectiveDurationMs} ms • ×${lastPad.triggerCount})'
                      : bank.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('reset_bank_button'),
            onPressed: _resetCurrentBank,
            tooltip: 'Réinitialiser la banque',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.restore_rounded,
              color: Colors.white60,
              size: 19,
            ),
          ),
          IconButton(
            key: const Key('features_help_button'),
            onPressed: _showFeaturesGuideDialog,
            tooltip: 'Guide & Fonctionnalités',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.info_outline_rounded,
              color: Colors.white70,
              size: 19,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankSelectorRow() {
    return Row(
      children: List<Widget>.generate(_banks.length, (int idx) {
        final b = _banks[idx];
        final selected = idx == _activeBankIndex;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: idx == 0 ? 0 : 3,
              right: idx == _banks.length - 1 ? 0 : 3,
            ),
            child: InkWell(
              key: Key('bank_chip_${b.id}'),
              borderRadius: BorderRadius.circular(9),
              onTap: () => _switchBank(idx),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFF232942)
                      : const Color(0xFF131724),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF38BDF8)
                        : Colors.white12,
                    width: selected ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    Text(
                      'BANK ${b.id}',
                      style: TextStyle(
                        color: selected
                            ? const Color(0xFF38BDF8)
                            : Colors.white70,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      '${b.assignedCount}/16',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPrimaryTransportBar() {
    return Row(
      children: <Widget>[
        // BOUTON RECORD PRINCIPAL
        Expanded(
          flex: 5,
          child: ElevatedButton.icon(
            key: const Key('record_mode_button'),
            onPressed: () {
              setState(() {
                _isRecordMode = !_isRecordMode;
                if (_isRecordMode) {
                  _isEditMode = false;
                }
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRecordMode
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF991B1B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
                side: BorderSide(
                  color: _isRecordMode
                      ? Colors.white
                      : const Color(0xFFEF4444),
                  width: _isRecordMode ? 2.0 : 1.2,
                ),
              ),
            ),
            icon: Icon(
              _isRecordMode
                  ? Icons.radio_button_checked_rounded
                  : Icons.fiber_manual_record_rounded,
              size: 18,
              color: Colors.white,
            ),
            label: Text(
              _isRecordMode ? 'RECORD : CHOISIR CASE' : 'RECORD (ASSIGNER SON)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 11.5,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // BOUTON ÉDITER PAD
        Expanded(
          flex: 3,
          child: OutlinedButton.icon(
            key: const Key('edit_mode_button'),
            onPressed: () {
              setState(() {
                _isEditMode = !_isEditMode;
                if (_isEditMode) {
                  _isRecordMode = false;
                }
              });
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: _isEditMode
                  ? const Color(0xFF3B82F6).withValues(alpha: 0.25)
                  : const Color(0xFF131724),
              foregroundColor:
                  _isEditMode ? const Color(0xFF60A5FA) : Colors.white70,
              side: BorderSide(
                color: _isEditMode
                    ? const Color(0xFF60A5FA)
                    : Colors.white24,
              ),
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            icon: const Icon(Icons.tune_rounded, size: 16),
            label: const Text(
              'ÉDITER',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),
            ),
          ),
        ),
        const SizedBox(width: 6),

        // BOUTON STOP ALL (PANIC)
        Expanded(
          flex: 2,
          child: OutlinedButton.icon(
            key: const Key('stop_all_button'),
            onPressed: _stopAllSounds,
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF1C1924),
              foregroundColor: Colors.amberAccent,
              side: BorderSide(
                color: _loopingPads.isNotEmpty || _isPlayingSeq
                    ? Colors.amberAccent
                    : Colors.white24,
              ),
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            icon: const Icon(Icons.stop_rounded, size: 17),
            label: const Text(
              'STOP',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeBanner() {
    final isRec = _isRecordMode;
    final bannerColor =
        isRec ? const Color(0xFFEF4444) : const Color(0xFF3B82F6);
    return Container(
      key: const Key('active_mode_banner'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: bannerColor),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            isRec ? Icons.mic_external_on_rounded : Icons.tune_rounded,
            color: bannerColor,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isRec
                  ? 'MODE RECORD ACTIF : Touchez l’une des 16 cases pour enregistrer au micro ou charger un fichier WAV.'
                  : 'MODE ÉDITION ACTIF : Touchez une case pour régler son volume, son pitch, son mode ou sa découpe.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Construit la grille 4x4 de 16 cases occupant tout l'espace central sans défilement.
  Widget _buildPadGrid4x4(SamplerBank bank) {
    return Column(
      children: List<Widget>.generate(4, (int row) {
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: row == 0 ? 0 : 4,
              bottom: row == 3 ? 0 : 4,
            ),
            child: Row(
              children: List<Widget>.generate(4, (int col) {
                final padIndex = row * 4 + col;
                final pad = bank.pads[padIndex];
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: col == 0 ? 0 : 4,
                      right: col == 3 ? 0 : 4,
                    ),
                    child: _buildPadCell(pad),
                  ),
                );
              }),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildPadCell(SamplerPad pad) {
    final isFlashing = _flashingPads.contains(pad.id);
    final isLooping = _loopingPads.contains(pad.id);
    final padColor = pad.color;
    final hasSound = pad.hasSound;

    final borderColor = _isRecordMode
        ? const Color(0xFFEF4444)
        : isFlashing
            ? Colors.white
            : isLooping
                ? Colors.amberAccent
                : hasSound
                    ? padColor.withValues(alpha: 0.85)
                    : Colors.white24;

    final bgColor = isFlashing
        ? padColor.withValues(alpha: 0.72)
        : hasSound
            ? padColor.withValues(alpha: 0.16)
            : const Color(0xFF131722);

    return GestureDetector(
      key: Key('sampler_pad_${pad.id}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _handlePadTap(pad),
      onLongPress: () => _openPadAssignmentSheet(pad, openInRecordFocus: false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: borderColor,
            width: isFlashing || _isRecordMode || isLooping ? 2.2 : 1.3,
          ),
          boxShadow: isFlashing
              ? <BoxShadow>[
                  BoxShadow(
                    color: padColor.withValues(alpha: 0.55),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : const <BoxShadow>[],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            // Ligne supérieure : Numéro de case + Badge mode / source
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  (pad.id + 1).toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: isFlashing
                        ? Colors.white
                        : hasSound
                            ? padColor
                            : Colors.white38,
                    fontWeight: FontWeight.w900,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: _isRecordMode
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'REC',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          )
                        : hasSound
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    pad.source.icon,
                                    size: 10,
                                    color: Colors.white70,
                                  ),
                                  const SizedBox(width: 2),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isLooping
                                          ? Colors.amberAccent
                                          : Colors.black38,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isLooping
                                          ? 'ON'
                                          : pad.triggerMode.shortBadge,
                                      style: TextStyle(
                                        color: isLooping
                                            ? Colors.black
                                            : Colors.white70,
                                        fontSize: 7.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : const Icon(
                                Icons.add_rounded,
                                size: 12,
                                color: Colors.white30,
                              ),
                  ),
                ),
              ],
            ),

            // Zone centrale : Forme d'onde (Waveform) ou invitation à assigner
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: hasSound
                    ? CustomPaint(
                        painter: WaveformPainter(
                          peaks: pad.waveformPeaks,
                          activeColor: padColor,
                          inactiveColor: Colors.white12,
                          trimStart: pad.trimStart,
                          trimEnd: pad.trimEnd,
                          isTriggered: isFlashing,
                        ),
                      )
                    : Center(
                        child: Text(
                          _isRecordMode ? 'ASSIGNER' : 'VIDE',
                          style: TextStyle(
                            color: _isRecordMode
                                ? const Color(0xFFEF4444)
                                : Colors.white24,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
              ),
            ),

            // Ligne inférieure : Nom du sample & durée / pitch
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  pad.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasSound ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
                if (hasSound)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          '${pad.effectiveDurationMs}ms',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 8.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if ((pad.pitch - 1.0).abs() > 0.03)
                        Text(
                          '${pad.pitch.toStringAsFixed(1)}×',
                          style: TextStyle(
                            color: padColor,
                            fontSize: 8.0,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      else if (pad.triggerCount > 0)
                        Text(
                          '×${pad.triggerCount}',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 8.0,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomRhythmConsole() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF131724),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // MÉTRONOME ON/OFF
            InkWell(
              key: const Key('metronome_toggle_button'),
              onTap: _toggleMetronome,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _metronomeActive
                      ? const Color(0xFF10B981).withValues(alpha: 0.22)
                      : const Color(0xFF1B2030),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _metronomeActive
                        ? const Color(0xFF10B981)
                        : Colors.white12,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.av_timer_rounded,
                      size: 15,
                      color: _metronomeActive
                          ? const Color(0xFF10B981)
                          : Colors.white60,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_bpm BPM',
                      style: TextStyle(
                        color: _metronomeActive
                            ? const Color(0xFF10B981)
                            : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            // BPM - / + / TAP
            IconButton(
              key: const Key('bpm_minus_button'),
              onPressed: () => _changeBpm(-5),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 28),
              icon: const Icon(
                Icons.remove_rounded,
                color: Colors.white70,
                size: 16,
              ),
            ),
            IconButton(
              key: const Key('bpm_plus_button'),
              onPressed: () => _changeBpm(5),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 28),
              icon: const Icon(
                Icons.add_rounded,
                color: Colors.white70,
                size: 16,
              ),
            ),
            InkWell(
              key: const Key('tap_tempo_button'),
              onTap: _handleTapTempo,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2030),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'TAP',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // SÉQUENCEUR / LOOPER LIVE
            InkWell(
              key: const Key('seq_record_button'),
              onTap: _toggleSeqRecording,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _isRecordingSeq
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF1B2030),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isRecordingSeq
                        ? Colors.white
                        : const Color(0xFFEF4444).withValues(alpha: 0.6),
                  ),
                ),
                child: Text(
                  _isRecordingSeq ? 'STOP SEQ' : 'REC SEQ',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 5),
            InkWell(
              key: const Key('seq_play_button'),
              onTap: _recordedSeqEvents.isEmpty ? null : _toggleSeqPlayback,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: _isPlayingSeq
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF1B2030),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _recordedSeqEvents.isNotEmpty
                        ? const Color(0xFF3B82F6)
                        : Colors.white12,
                  ),
                ),
                child: Text(
                  _isPlayingSeq
                      ? 'LOOP ON (${_recordedSeqEvents.length})'
                      : 'LOOP (${_recordedSeqEvents.length})',
                  style: TextStyle(
                    color: _recordedSeqEvents.isNotEmpty
                        ? Colors.white
                        : Colors.white38,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (_recordedSeqEvents.isNotEmpty) ...<Widget>[
              const SizedBox(width: 4),
              IconButton(
                key: const Key('seq_clear_button'),
                onPressed: _clearSequence,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 28),
                icon: const Icon(
                  Icons.clear_rounded,
                  color: Colors.redAccent,
                  size: 16,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureGuideItem extends StatelessWidget {
  const _FeatureGuideItem({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF38BDF8),
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            body,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
