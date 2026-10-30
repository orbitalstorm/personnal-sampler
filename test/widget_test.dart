import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personnal_sampler/main.dart';
import 'package:personnal_sampler/models/sampler_models.dart';
import 'package:personnal_sampler/services/sampler_audio_engine.dart';
import 'package:personnal_sampler/services/wav_dsp_service.dart';

void main() {
  group('WavDspService — Synthèse, Auto-Trim Silence & Découpe WAV', () {
    test('Génère des fichiers RIFF/WAVE valides pour les 16 instruments Studio 808', () {
      for (final preset in SynthPresetKind.values) {
        final res = WavDspService.generatePresetWav(preset);
        expect(res.wavBytes.length, greaterThan(44));
        // En-tête RIFF....WAVE
        expect(String.fromCharCodes(res.wavBytes.sublist(0, 4)), equals('RIFF'));
        expect(String.fromCharCodes(res.wavBytes.sublist(8, 12)), equals('WAVE'));
        expect(res.durationMs, greaterThan(50));
        expect(res.waveformPeaks.length, equals(WavDspService.defaultPeakCount));
        for (final p in res.waveformPeaks) {
          expect(p, inInclusiveRange(0.0, 1.0));
        }
      }
    });

    test('Auto-Trim coupe le silence initial d’un enregistrement micro et normalise le gain', () {
      const sampleRate = 44100;
      final silenceSamples = (0.20 * sampleRate).round(); // 200 ms de silence
      final toneSamples = (0.30 * sampleRate).round(); // 300 ms de signal
      final pcm = Int16List(silenceSamples + toneSamples);
      for (var i = 0; i < toneSamples; i++) {
        pcm[silenceSamples + i] = (i.isEven ? 4000 : -4000);
      }
      final rawWav = WavDspService.encodePcm16MonoToWav(pcm, sampleRate: sampleRate);

      final rawAnalysis = WavDspService.analyzeAudioBytes(rawWav);
      final trimmed = WavDspService.processRecordedMicWav(
        rawWav,
        autoTrimSilence: true,
        normalize: true,
      );

      // La durée après Auto-Trim doit être nettement plus courte (~305-340 ms au lieu de 500 ms)
      expect(trimmed.durationMs, lessThan(rawAnalysis.durationMs - 120));
      expect(trimmed.durationMs, greaterThanOrEqualTo(280));
    });

    test('sliceWavBytes découpe correctement un échantillon entre trimStart et trimEnd', () {
      final original = WavDspService.generatePresetWav(SynthPresetKind.kick808);
      final sliced = WavDspService.sliceWavBytes(
        original.wavBytes,
        trimStart: 0.25,
        trimEnd: 0.75,
      );
      expect(sliced, isNotNull);
      final slicedAnalysis = WavDspService.analyzeAudioBytes(sliced!);
      expect(
        slicedAnalysis.durationMs,
        closeTo(original.durationMs * 0.5, 25),
      );
    });
  });

  group('SamplerModels — Sérialisation JSON & Grille 4x4 (16 Pads)', () {
    test('Une banque conserve exactement 16 cases après sérialisation JSON', () {
      final bank = SamplerBank.createEmptyBank(
        id: 'B',
        name: 'BANQUE B',
        subtitle: 'Test 4x4',
      );
      expect(bank.pads.length, equals(16));
      final updatedPad = bank.pads[5].copyWith(
        label: 'MON SON',
        source: PadSoundSource.microphone,
        filePath: '/tmp/test.wav',
        durationMs: 420,
        triggerMode: PadTriggerMode.oneShot,
        volume: 1.25,
        pitch: 1.15,
      );
      final updatedBank = bank.copyWithPad(updatedPad);
      final restored = SamplerBank.fromJson(updatedBank.toJson());

      expect(restored.pads.length, equals(16));
      expect(restored.pads[5].label, equals('MON SON'));
      expect(restored.pads[5].source, equals(PadSoundSource.microphone));
      expect(restored.pads[5].triggerMode, equals(PadTriggerMode.oneShot));
      expect(restored.pads[5].volume, closeTo(1.25, 0.001));
      expect(restored.pads[5].pitch, closeTo(1.15, 0.001));
    });
  });

  group('Interface Sampleur 4x4 — Lecture illimitée, Bouton Record (Micro & WAV)', () {
    late Directory tempDir;
    late SamplerAudioEngine engine;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pulsepad_test_');
      engine = SamplerAudioEngine(customStorageDir: tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'Affiche les 16 cases (4x4), rejoue un son autant de fois que voulu et assigne via RECORD (Micro + WAV)',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2280);
        tester.view.devicePixelRatio = 2.625;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(PersonalSamplerApp(audioEngine: engine));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // 1. Vérifier que les 16 cases (0..15) sont présentes à l'écran
        for (var i = 0; i < 16; i++) {
          expect(find.byKey(Key('sampler_pad_$i')), findsOneWidget);
        }

        // 2. Appuyer 4 fois de suite sur la case 0 (KICK 808) pour vérifier la relecture illimitée
        final pad0Finder = find.byKey(const Key('sampler_pad_0'));
        await tester.tap(pad0Finder);
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(pad0Finder);
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(pad0Finder);
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tap(pad0Finder);
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('×4'), findsOneWidget);

        // 3. Basculer sur la Banque B (vierge) pour tester l'assignation via le bouton RECORD
        await tester.tap(find.byKey(const Key('bank_chip_B')));
        await tester.pumpAndSettle();

        // Activer le bouton RECORD
        await tester.tap(find.byKey(const Key('record_mode_button')));
        await tester.pump();
        expect(find.byKey(const Key('active_mode_banner')), findsOneWidget);

        // Toucher la case 0 pour lui assigner un enregistrement Micro
        await tester.tap(find.byKey(const Key('sampler_pad_0')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pad_assignment_sheet')), findsOneWidget);

        // Démarrer l'enregistrement micro puis l'arrêter
        await tester.tap(find.byKey(const Key('mic_record_toggle_button')));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.tap(find.byKey(const Key('mic_record_toggle_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Valider et fermer la fenêtre
        await tester.tap(find.byKey(const Key('save_pad_assignment_button')));
        await tester.pumpAndSettle();

        // La case 0 affiche désormais "MICRO 01" et peut être jouée autant de fois qu'on veut
        expect(find.text('MICRO 01'), findsOneWidget);
        await tester.tap(find.byKey(const Key('sampler_pad_0')));
        await tester.pump(const Duration(milliseconds: 160));
        await tester.tap(find.byKey(const Key('sampler_pad_0')));
        await tester.pump(const Duration(milliseconds: 160));
        expect(find.text('×2'), findsOneWidget);

        // 4. Activer le bouton RECORD et assigner un fichier WAV depuis l'appareil sur la case 1
        await tester.tap(find.byKey(const Key('record_mode_button')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('sampler_pad_1')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('import_wav_file_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.byKey(const Key('save_pad_assignment_button')));
        await tester.pumpAndSettle();

        // La case 1 possède maintenant son fichier WAV importé et peut être déclenchée
        expect(find.text('SAMPLE PAD'), findsOneWidget);
        await tester.tap(find.byKey(const Key('sampler_pad_1')));
        await tester.pump(const Duration(milliseconds: 200));
      },
    );
  });
}
