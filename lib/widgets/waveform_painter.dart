import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Dessine la forme d'onde (Waveform) d'un échantillon sur 32 barres
/// en mettant en évidence la portion active entre `trimStart` et `trimEnd`.
class WaveformPainter extends CustomPainter {
  const WaveformPainter({
    required this.peaks,
    required this.activeColor,
    required this.inactiveColor,
    this.trimStart = 0.0,
    this.trimEnd = 1.0,
    this.showTrimHandles = false,
    this.isTriggered = false,
  });

  final List<double> peaks;
  final Color activeColor;
  final Color inactiveColor;
  final double trimStart;
  final double trimEnd;
  final bool showTrimHandles;
  final bool isTriggered;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final bars = peaks.isEmpty ? const <double>[0.2, 0.35, 0.25, 0.4, 0.2] : peaks;
    final count = bars.length;
    final barStep = size.width / count;
    final barWidth = math.max(1.5, barStep * 0.62);
    final centerY = size.height / 2.0;

    final activePaint = Paint()
      ..color = isTriggered ? Colors.white : activeColor
      ..style = PaintingStyle.fill;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final posNorm = (i + 0.5) / count;
      final inTrim = posNorm >= trimStart && posNorm <= trimEnd;
      final amp = bars[i].clamp(0.06, 1.0);
      final halfHeight = math.max(2.0, amp * (size.height * 0.46));
      final left = i * barStep + (barStep - barWidth) / 2.0;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          left,
          centerY - halfHeight,
          left + barWidth,
          centerY + halfHeight,
        ),
        const Radius.circular(2.0),
      );
      canvas.drawRRect(rect, inTrim ? activePaint : inactivePaint);
    }

    if (showTrimHandles) {
      final handlePaint = Paint()
        ..color = Colors.amberAccent
        ..strokeWidth = 2.0;

      final startX = (trimStart.clamp(0.0, 1.0) * size.width).clamp(1.0, size.width - 1.0);
      final endX = (trimEnd.clamp(0.0, 1.0) * size.width).clamp(1.0, size.width - 1.0);

      canvas.drawLine(Offset(startX, 0), Offset(startX, size.height), handlePaint);
      canvas.drawLine(Offset(endX, 0), Offset(endX, size.height), handlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant WaveformPainter oldDelegate) {
    return oldDelegate.peaks != peaks ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.trimStart != trimStart ||
        oldDelegate.trimEnd != trimEnd ||
        oldDelegate.isTriggered != isTriggered ||
        oldDelegate.showTrimHandles != showTrimHandles;
  }
}
