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
      final silenceSamples = (0.20 * sampleRate).round();
      final toneSamples = (0.30 * sampleRate).round();
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

  group('SamplerModels — Sérialisation JSON & Organisation Banques A/B/C vs D Studio', () {
    test('Une banque conserve exactement 16 cases après sérialisation JSON', () {
      final bank = SamplerBank.createEmptyBank(
        id: 'A',
        name: 'BANQUE A',
        subtitle: 'Sons de la Vie 1',
      );
      expect(bank.pads.length, equals(16));
      expect(bank.isStudioBank, isFalse);

      final updatedPad = bank.pads[5].copyWith(
        label: 'RIRE BEBE',
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
      expect(restored.pads[5].label, equals('RIRE BEBE'));
      expect(restored.pads[5].source, equals(PadSoundSource.microphone));
      expect(restored.pads[5].triggerMode, equals(PadTriggerMode.oneShot));
      expect(restored.pads[5].volume, closeTo(1.25, 0.001));
      expect(restored.pads[5].pitch, closeTo(1.15, 0.001));
    });

    test('Les banques par défaut placent les sons de vie en A/B/C et le Kit Studio 808 en Banque D', () {
      final engine = SamplerAudioEngine();
      final banks = engine.buildDefaultBanksSync();
      expect(banks.length, equals(4));
      expect(banks[0].id, equals('A'));
      expect(banks[0].isStudioBank, isFalse);
      expect(banks[0].assignedCount, equals(0));
      expect(banks[1].id, equals('B'));
      expect(banks[1].assignedCount, equals(0));
      expect(banks[2].id, equals('C'));
      expect(banks[2].assignedCount, equals(0));
      expect(banks[3].id, equals('D'));
      expect(banks[3].isStudioBank, isTrue);
      expect(banks[3].assignedCount, equals(16));
    });
  });

  group('LifeSampler UI — Splash Screen, Banques A/D, Fenêtre Éditer & Export WAV', () {
    late Directory tempDir;
    late SamplerAudioEngine engine;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('lifesampler_test_');
      engine = SamplerAudioEngine(customStorageDir: tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets(
      'Affiche le Splash Screen LifeSampler au démarrage, verrouille l’organisation A/B/C vs D Studio, groupe Auto-Trim/Booster sur la même ligne et exporte un son en WAV',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          PersonalSamplerApp(
            audioEngine: engine,
            showSplashOnStart: true,
            splashAutoDismissDuration: null,
          ),
        );
        await tester.pump();

        // 1. Vérifier le Splash Screen au démarrage avec le nom LifeSampler et l'illustration cartoon
        expect(find.byKey(const Key('lifesampler_splash_screen')), findsOneWidget);
        expect(find.text('LifeSampler'), findsOneWidget);
        expect(find.byKey(const Key('splash_cartoon_image')), findsOneWidget);

        // Passer à l'écran principal
        await tester.tap(find.byKey(const Key('splash_continue_button')));
        await tester.pumpAndSettle();

        // 2. Vérifier l'écran principal sur la Banque A (Sons de la vie) :
        //    - Titre LIFESAMPLER
        //    - 16 cases présentes
        //    - Pas de console BPM global sur la Banque A
        expect(find.text('LIFESAMPLER'), findsOneWidget);
        for (var i = 0; i < 16; i++) {
          expect(find.byKey(Key('sampler_pad_$i')), findsOneWidget);
        }
        expect(find.byKey(const Key('studio_bpm_console')), findsNothing);

        // 3. Toucher la case 0 (vide sur la Banque A) pour enregistrer un son micro
        await tester.tap(find.byKey(const Key('sampler_pad_0')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('pad_assignment_sheet')), findsOneWidget);

        // Vérifier que les pré-réglages Studio 808 ne sont PAS dans la fenêtre Éditer
        expect(find.text('KICK 808'), findsNothing);
        expect(find.byKey(const Key('preset_chip_kick808')), findsNothing);

        // Vérifier que les boutons Auto-Trim et Booster Micro sont sur la même ligne (même ordonnée Y)
        final autoTrimCenter =
            tester.getCenter(find.byKey(const Key('auto_trim_silence_chip')));
        final boosterCenter =
            tester.getCenter(find.byKey(const Key('normalize_mic_chip')));
        expect((autoTrimCenter.dy - boosterCenter.dy).abs(), lessThan(1.0));

        // Démarrer l'enregistrement micro puis l'arrêter
        await tester.tap(find.byKey(const Key('mic_record_toggle_button')));
        await tester.pump(const Duration(milliseconds: 120));
        await tester.tap(find.byKey(const Key('mic_record_toggle_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Exporter le son directement depuis la fenêtre Éditer
        final exportBtn = find.byKey(const Key('export_pad_wav_button'));
        expect(exportBtn, findsOneWidget);
        await tester.tap(exportBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const Key('pad_status_banner')), findsOneWidget);
        expect(find.textContaining('Son exporté :'), findsOneWidget);

        // Valider et fermer la fenêtre Éditer
        await tester.tap(find.byKey(const Key('save_pad_assignment_button')));
        await tester.pumpAndSettle();

        // La case 0 affiche désormais "MICRO 01" et peut être rejouée à volonté
        expect(find.text('MICRO 01'), findsOneWidget);
        await tester.tap(find.byKey(const Key('sampler_pad_0')));
        await tester.pump(const Duration(milliseconds: 160));
        await tester.tap(find.byKey(const Key('sampler_pad_0')));
        await tester.pump(const Duration(milliseconds: 160));
        expect(find.text('×2'), findsOneWidget);

        // 4. Basculer sur la Banque D (Studio) et vérifier que les 16 sons Studio 808
        //    ainsi que le BPM global s'affichent uniquement sur la Banque D
        await tester.tap(find.byKey(const Key('bank_chip_D')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('studio_bpm_console')), findsOneWidget);
        expect(find.text('KICK 808'), findsOneWidget);
        expect(find.text('120 BPM'), findsOneWidget);
      },
    );
  });
}
