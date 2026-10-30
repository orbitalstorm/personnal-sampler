import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/sampler_audio_engine.dart';
import 'widgets/sampler_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0B0D14),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const PersonalSamplerApp());
}

class PersonalSamplerApp extends StatelessWidget {
  const PersonalSamplerApp({
    super.key,
    this.audioEngine,
  });

  final SamplerAudioEngine? audioEngine;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PulsePad 16 — Personal Sampler',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0D14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFEF4444),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: SamplerScreen(audioEngine: audioEngine),
    );
  }
}
