import 'dart:math';

import 'package:flutter/material.dart';
import 'package:just_waveform/just_waveform.dart';

class AudioWaveformWidget extends StatefulWidget {
  final Color waveColor;
  final double scale;
  final double strokeWidth;
  final double pixelsPerStep;
  final Waveform waveform;
  final Duration start;
  final Duration duration;
  final Duration currentPosition;
  final ValueChanged<Duration> onSeek;

  const AudioWaveformWidget({
    Key? key,
    required this.waveform,
    required this.start,
    required this.duration,
    required this.currentPosition,
    required this.onSeek,
    this.waveColor = const Color.fromARGB(255, 0, 0, 0),
    this.scale = 1,
    this.strokeWidth = 5.0,
    this.pixelsPerStep = 8.0,
  }) : super(key: key);

  @override
  State<AudioWaveformWidget> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<AudioWaveformWidget> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        final tapX = details.localPosition.dx;
        final width = context.size!.width;
        final tappedDuration = widget.duration * (tapX / width);
        widget.onSeek(tappedDuration);
      },
      onHorizontalDragUpdate: (details) {
        final dragX = details.localPosition.dx;
        final width = context.size!.width;
        final draggedDuration = widget.duration * (dragX / width);
        widget.onSeek(draggedDuration);
      },
      child: SizedBox(
        height: 200, // ou o valor que preferir
        width: double.infinity,
        child: CustomPaint(
          painter: AudioWaveformPainter(
            waveColor: widget.waveColor,
            waveform: widget.waveform,
            start: widget.start,
            duration: widget.duration,
            scale: widget.scale,
            strokeWidth: widget.strokeWidth,
            pixelsPerStep: widget.pixelsPerStep,
            currentPosition: widget.currentPosition,
          ),
        ),
      ),
    );
  }
}

class AudioWaveformPainter extends CustomPainter {
  final double scale;
  final double strokeWidth;
  final double pixelsPerStep;
  final Paint wavePaint;
  final Waveform waveform;
  final Duration start;
  final Duration duration;
  final Duration currentPosition; // <- Campo adicionado

  AudioWaveformPainter({
    required this.waveform,
    required this.start,
    required this.duration,
    required this.currentPosition, // <- Incluído corretamente aqui
    Color waveColor = const Color.fromARGB(255, 0, 0, 0),
    this.scale = 1.0,
    this.strokeWidth = 5.0,
    this.pixelsPerStep = 8.0,
  }) : wavePaint = Paint()
         ..style = PaintingStyle.stroke
         ..strokeWidth = strokeWidth
         ..strokeCap = StrokeCap.round
         ..color = waveColor;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    // Fundo preto elegante
    final backgroundPaint = Paint()..color = const Color(0xFF121212);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), backgroundPaint);

    // Gradiente no waveform (desenha primeiro)
    final gradient = LinearGradient(
      colors: [
        const Color.fromARGB(255, 83, 83, 83),
        const Color.fromARGB(255, 59, 59, 59),
      ],
    ).createShader(Rect.fromLTWH(0, 0, width, height));

    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = gradient;

    final waveformPixelsPerWindow = waveform.positionToPixel(duration).toInt();
    final waveformPixelsPerDevicePixel = waveformPixelsPerWindow / width;
    final waveformPixelsPerStep = waveformPixelsPerDevicePixel * pixelsPerStep;
    final sampleOffset = waveform.positionToPixel(start);
    final sampleStart = -sampleOffset % waveformPixelsPerStep;

    for (
      var i = sampleStart.toDouble();
      i <= waveformPixelsPerWindow + 1.0;
      i += waveformPixelsPerStep
    ) {
      final sampleIdx = (sampleOffset + i).toInt();
      final x = i / waveformPixelsPerDevicePixel;
      final minY = normalise(waveform.getPixelMin(sampleIdx), height);
      final maxY = normalise(waveform.getPixelMax(sampleIdx), height);
      canvas.drawLine(
        Offset(x + strokeWidth / 2, max(strokeWidth * 0.75, minY)),
        Offset(x + strokeWidth / 2, min(height - strokeWidth * 0.75, maxY)),
        wavePaint,
      );
    }

    // Agora desenha o cursor branco por cima do waveform
    final positionFraction =
        (currentPosition.inMilliseconds / duration.inMilliseconds).clamp(
          0.0,
          1.0,
        );
    final cursorX = positionFraction * width;

    final cursorPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;

    canvas.drawLine(Offset(cursorX, 0), Offset(cursorX, height), cursorPaint);
  }

  @override
  bool shouldRepaint(covariant AudioWaveformPainter oldDelegate) {
    return oldDelegate.currentPosition != currentPosition ||
        oldDelegate.duration != duration ||
        oldDelegate.start != start;
  }

  double normalise(int s, double height) {
    if (waveform.flags == 0) {
      final y = 32768 + (scale * s).clamp(-32768.0, 32767.0).toDouble();
      return height - 1 - y * height / 65536;
    } else {
      final y = 128 + (scale * s).clamp(-128.0, 127.0).toDouble();
      return height - 1 - y * height / 256;
    }
  }
}
