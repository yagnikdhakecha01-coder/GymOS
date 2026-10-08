import 'package:flutter/material.dart';

class MiniSparkline extends StatelessWidget {
  final List<double> data;
  final Color color;
  final double height;
  final double width;

  const MiniSparkline({
    super.key,
    required this.data,
    required this.color,
    this.height = 36.0,
    this.width = 70.0,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _SparklinePainter(data, color),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _SparklinePainter(this.data, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final path = Path();
    final fillPath = Path();

    final double widthBetweenPoints = size.width / (data.length - 1);
    
    double max = data.reduce((a, b) => a > b ? a : b);
    double min = data.reduce((a, b) => a < b ? a : b);
    
    if (max == min) {
      max += 1.0;
      min -= 1.0;
    }
    
    final double range = max - min;

    double getX(int index) => index * widthBetweenPoints;
    double getY(int index) {
      final double normalized = (data[index] - min) / range;
      return size.height - (normalized * (size.height - 4)) - 2; // Add padding
    }

    path.moveTo(getX(0), getY(0));
    fillPath.moveTo(getX(0), size.height);
    fillPath.lineTo(getX(0), getY(0));

    for (int i = 1; i < data.length; i++) {
      final double x = getX(i);
      final double y = getY(i);
      
      // Control points for smooth bezier curves
      final double prevX = getX(i - 1);
      final double prevY = getY(i - 1);
      final double controlX1 = prevX + (x - prevX) / 2;
      final double controlY1 = prevY;
      final double controlX2 = prevX + (x - prevX) / 2;
      final double controlY2 = y;

      path.cubicTo(controlX1, controlY1, controlX2, controlY2, x, y);
      fillPath.cubicTo(controlX1, controlY1, controlX2, controlY2, x, y);
    }

    fillPath.lineTo(getX(data.length - 1), size.height);
    fillPath.close();

    // Draw background gradient fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.15),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Draw main sparkline curve
    final strokePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    if (oldDelegate.color != color || oldDelegate.data.length != data.length) return true;
    for (int i = 0; i < data.length; i++) {
      if (oldDelegate.data[i] != data[i]) return true;
    }
    return false;
  }
}
