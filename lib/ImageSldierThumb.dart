import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class ImageSliderThumb extends SliderComponentShape {
  final double size;
  final ui.Image image;
  final double rotationAngle; // em radianos

  ImageSliderThumb({
    required this.size,
    required this.image,
    this.rotationAngle = pi / 2, // gira 90°
  });

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => Size(size, size);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required Size sizeWithOverflow,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
  }) {
    final paint = Paint();

    // Salva o estado do canvas
    context.canvas.save();

    // Move o canvas para o centro da imagem
    context.canvas.translate(center.dx, center.dy);

    // Rotaciona o canvas
    context.canvas.rotate(rotationAngle);

    // --- Desenha sombra quadrada ---
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4); // blur da sombra
    final shadowRect = Rect.fromCenter(
      center: Offset(0, 0),
      width: size,
      height: size,
    );
    context.canvas.drawRect(shadowRect, shadowPaint); // agora sem radius

    // --- Desenha a imagem por cima da sombra ---
    final rect = Rect.fromCenter(
      center: Offset(0, 0),
      width: size,
      height: size,
    );

    context.canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      paint,
    );

    // Restaura o canvas
    context.canvas.restore();
  }
}
