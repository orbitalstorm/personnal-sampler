import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/sampler_audio_engine.dart';
import 'widgets/lifesampler_splash_screen.dart';
import 'widgets/sampler_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Verrouillage strict en mode portrait uniquement (aucune rotation paysage)
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
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

class PersonalSamplerApp extends StatefulWidget {
  const PersonalSamplerApp({
    super.key,
    this.audioEngine,
    this.showSplashOnStart = true,
    this.splashAutoDismissDuration = const Duration(milliseconds: 2400),
  });

  final SamplerAudioEngine? audioEngine;
  final bool showSplashOnStart;
  final Duration? splashAutoDismissDuration;

  @override
  State<PersonalSamplerApp> createState() => _PersonalSamplerAppState();
}

class _PersonalSamplerAppState extends State<PersonalSamplerApp> {
  late bool _showingSplash;

  @override
  void initState() {
    super.initState();
    _showingSplash = widget.showSplashOnStart;
  }

  void _dismissSplash() {
    if (!mounted) return;
    setState(() {
      _showingSplash = false;
    });
  }

  void _reopenSplash() {
    if (!mounted) return;
    setState(() {
      _showingSplash = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LifeSampler — Bruiteur de la Vie',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFF0B0D14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10B981),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: _showingSplash
          ? LifeSamplerSplashScreen(
              onContinue: _dismissSplash,
              autoDismissDuration: widget.splashAutoDismissDuration,
            )
          : SamplerScreen(
              audioEngine: widget.audioEngine,
              onShowSplash: _reopenSplash,
            ),
    );
  }
}
