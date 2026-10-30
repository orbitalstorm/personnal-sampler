import 'dart:async';

import 'package:flutter/material.dart';

/// Splash Screen de démarrage de LifeSampler mettant en valeur le nom de
/// l'application, sa philosophie (« L'enregistreur bruiteur de la vie ») et
/// l'illustration cartoon signée Leonardo.
class LifeSamplerSplashScreen extends StatefulWidget {
  const LifeSamplerSplashScreen({
    super.key,
    required this.onContinue,
    this.autoDismissDuration = const Duration(milliseconds: 2400),
  });

  final VoidCallback onContinue;
  final Duration? autoDismissDuration;

  @override
  State<LifeSamplerSplashScreen> createState() =>
      _LifeSamplerSplashScreenState();
}

class _LifeSamplerSplashScreenState extends State<LifeSamplerSplashScreen> {
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    final duration = widget.autoDismissDuration;
    if (duration != null) {
      _autoTimer = Timer(duration, () {
        if (mounted) {
          widget.onContinue();
        }
      });
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  void _handleContinue() {
    _autoTimer?.cancel();
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('lifesampler_splash_screen'),
      backgroundColor: const Color(0xFF0B0D14),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleContinue,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Badge supérieur philosophie
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171C2E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.55),
                        width: 1.2,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.mic_external_on_rounded,
                          color: Color(0xFF38BDF8),
                          size: 15,
                        ),
                        SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'ENREGISTREUR & BRUITEUR DE LA VIE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF38BDF8),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Illustration Cartoon Leonardo centrale
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.65),
                            width: 2.2,
                          ),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: const Color(0xFF38BDF8).withValues(alpha: 0.22),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Image.asset(
                            'assets/images/lifesampler_splash_cartoon.png',
                            key: const Key('splash_cartoon_image'),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Titre principal LifeSampler + slogan
                const Text(
                  'LifeSampler',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Capturez les sons du quotidien — bébé qui rit, phrase culte du boss, porte qui grince — et rejouez-les pour le plaisir !',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),

                // 3 Piliers alignés sur une seule ligne
                const Row(
                  children: <Widget>[
                    Expanded(
                      child: _SplashFeaturePill(
                        icon: Icons.mic_rounded,
                        label: 'Micro Direct',
                        color: Color(0xFFEF4444),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _SplashFeaturePill(
                        icon: Icons.grid_view_rounded,
                        label: '16 Pads Fun',
                        color: Color(0xFF10B981),
                      ),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: _SplashFeaturePill(
                        icon: Icons.ios_share_rounded,
                        label: 'Export WAV',
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Bouton d'entrée directe
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    key: const Key('splash_continue_button'),
                    onPressed: _handleContinue,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: const Color(0xFF06130E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    label: const Text(
                      'OUVRIR LIFESAMPLER',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashFeaturePill extends StatelessWidget {
  const _SplashFeaturePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF141826),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
