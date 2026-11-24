import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Five stars drawn on a canvas: a custom widget with no child widgets to find.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, required this.onChanged});

  static const double starSize = 40;

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rating',
      value: '$rating of 5',
      // A node that can be increased must also say what it would become.
      increasedValue: rating < 5 ? '${rating + 1} of 5' : null,
      decreasedValue: rating > 0 ? '${rating - 1} of 5' : null,
      onIncrease: rating < 5 ? () => onChanged(rating + 1) : null,
      onDecrease: rating > 0 ? () => onChanged(rating - 1) : null,
      child: GestureDetector(
        onTapDown: (details) =>
            onChanged((details.localPosition.dx / starSize).floor() + 1),
        child: CustomPaint(
          size: const Size(starSize * 5, starSize),
          painter: _StarsPainter(
            rating: rating,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _StarsPainter extends CustomPainter {
  const _StarsPainter({required this.rating, required this.color});

  final int rating;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (var star = 0; star < 5; star++) {
      final centre = Offset(
        RatingStars.starSize * (star + 0.5),
        size.height / 2,
      );
      final path = Path();
      for (var point = 0; point < 10; point++) {
        final radius = RatingStars.starSize * (point.isEven ? 0.45 : 0.2);
        final angle = -math.pi / 2 + point * math.pi / 5;
        final offset =
            centre + Offset(math.cos(angle), math.sin(angle)) * radius;
        point == 0
            ? path.moveTo(offset.dx, offset.dy)
            : path.lineTo(offset.dx, offset.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = star < rating ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_StarsPainter oldDelegate) =>
      oldDelegate.rating != rating || oldDelegate.color != color;
}
