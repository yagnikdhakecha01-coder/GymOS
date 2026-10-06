import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/theme.dart';

class SparklineChart extends StatefulWidget {
  final List<double> data;
  final List<String> labels;
  final Color lineColor;
  final double? maxVal;
  final List<double>? customYValues;
  final String Function(double)? yLabelFormatter;
  final int? tooltipIndex;
  final String? tooltipDate;
  final String Function(double)? tooltipValueFormatter;

  const SparklineChart({
    super.key,
    required this.data,
    required this.labels,
    this.lineColor = const Color(0xFF6C3AED),
    this.maxVal,
    this.customYValues,
    this.yLabelFormatter,
    this.tooltipIndex,
    this.tooltipDate,
    this.tooltipValueFormatter,
  });

  @override
  State<SparklineChart> createState() => _SparklineChartState();
}

class _SparklineChartState extends State<SparklineChart> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 2.0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double paddingLeft = 36.0;
          final double paddingRight = 12.0;
          final double chartWidth = constraints.maxWidth - paddingLeft - paddingRight;
          final double stepX = widget.data.isEmpty ? 1.0 : chartWidth / (widget.data.length - 1);

          void handleTouch(Offset localPosition) {
            if (widget.data.isEmpty) return;
            final double localX = localPosition.dx - paddingLeft;
            int index = (localX / stepX).round().clamp(0, widget.data.length - 1);
            if (_selectedIndex != index) {
              setState(() {
                _selectedIndex = index;
              });
            }
          }

          final int? activeTooltipIndex = _selectedIndex;
          final String? activeTooltipDate = activeTooltipIndex != null && activeTooltipIndex < widget.labels.length 
              ? widget.labels[activeTooltipIndex] 
              : null;

          return GestureDetector(
            onPanDown: (details) => handleTouch(details.localPosition),
            onPanUpdate: (details) => handleTouch(details.localPosition),
            onPanEnd: (_) {
              setState(() {
                _selectedIndex = null;
              });
            },
            onTapDown: (details) => handleTouch(details.localPosition),
            onTapUp: (_) {
              setState(() {
                _selectedIndex = null;
              });
            },
            onTapCancel: () {
              setState(() {
                _selectedIndex = null;
              });
            },
            child: CustomPaint(
              painter: _SparklineChartPainter(
                data: widget.data,
                labels: widget.labels,
                lineColor: widget.lineColor,
                maxVal: widget.maxVal,
                customYValues: widget.customYValues,
                yLabelFormatter: widget.yLabelFormatter,
                tooltipIndex: activeTooltipIndex,
                tooltipDate: activeTooltipDate,
                tooltipValueFormatter: widget.tooltipValueFormatter,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SparklineChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final Color lineColor;
  final double? maxVal;
  final List<double>? customYValues;
  final String Function(double)? yLabelFormatter;
  final int? tooltipIndex;
  final String? tooltipDate;
  final String Function(double)? tooltipValueFormatter;

  _SparklineChartPainter({
    required this.data,
    required this.labels,
    required this.lineColor,
    this.maxVal,
    this.customYValues,
    this.yLabelFormatter,
    this.tooltipIndex,
    this.tooltipDate,
    this.tooltipValueFormatter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final double paddingLeft = 36.0;
    final double paddingRight = 12.0;
    final double paddingTop = 25.0;
    final double paddingBottom = 20.0;

    final double chartWidth = size.width - paddingLeft - paddingRight;
    final double chartHeight = size.height - paddingTop - paddingBottom;

    final double max = maxVal ?? 2500000.0;
    final double min = 0.0;
    final double range = max - min;
    final double stepX = chartWidth / (data.length - 1);

    double getX(int index) => paddingLeft + (index * stepX);
    double getY(int index) {
      final double val = data[index];
      final double normalized = (val - min) / range;
      final double clampedNormalized = normalized.clamp(0.0, 1.0);
      return paddingTop + chartHeight - (clampedNormalized * chartHeight);
    }

    // Grid lines & labels
    final gridPaint = Paint()
      ..color = AppTheme.border.withValues(alpha: 0.7)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    final List<double> yValues = customYValues ?? [0, 500000, 1000000, 1500000, 2000000, 2500000];
    for (final val in yValues) {
      final double normalized = (val - min) / range;
      final double y = paddingTop + chartHeight - (normalized * chartHeight);
      
      canvas.drawLine(Offset(paddingLeft, y), Offset(size.width - paddingRight, y), gridPaint);

      String labelText = '';
      if (yLabelFormatter != null) {
        labelText = yLabelFormatter!(val);
      } else {
        if (val == 0) {
          labelText = '₹0';
        } else {
          labelText = '₹${(val / 100000).toStringAsFixed(0)}L';
        }
      }

      textPainter.text = TextSpan(
        text: labelText,
        style: GoogleFonts.inter(
          fontSize: 8.5,
          color: AppTheme.textMuted,
          fontWeight: FontWeight.w500,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(paddingLeft - textPainter.width - 6, y - (textPainter.height / 2)),
      );
    }

    // Draw curve
    final path = Path();
    final fillPath = Path();

    path.moveTo(getX(0), getY(0));
    fillPath.moveTo(getX(0), paddingTop + chartHeight);
    fillPath.lineTo(getX(0), getY(0));

    for (int i = 1; i < data.length; i++) {
      final double x = getX(i);
      final double y = getY(i);
      final double prevX = getX(i - 1);
      final double prevY = getY(i - 1);

      final double controlX1 = prevX + (x - prevX) / 2;
      final double controlY1 = prevY;
      final double controlX2 = prevX + (x - prevX) / 2;
      final double controlY2 = y;

      path.cubicTo(controlX1, controlY1, controlX2, controlY2, x, y);
      fillPath.cubicTo(controlX1, controlY1, controlX2, controlY2, x, y);
    }

    fillPath.lineTo(getX(data.length - 1), paddingTop + chartHeight);
    fillPath.close();

    // Fill Gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          lineColor.withValues(alpha: 0.22),
          lineColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(paddingLeft, paddingTop, chartWidth, chartHeight))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);

    // Stroke curve
    final strokePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, strokePaint);

    // Draw dots
    final dotPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.fill;
    
    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < data.length; i++) {
      canvas.drawCircle(Offset(getX(i), getY(i)), 3.0, dotPaint);
      canvas.drawCircle(Offset(getX(i), getY(i)), 3.0, dotBorderPaint);
    }

    // Tooltip Callout
    if (tooltipIndex != null && tooltipIndex! < data.length) {
      final int tIdx = tooltipIndex!;
      final double tx = getX(tIdx);
      final double ty = getY(tIdx);

      final double tooltipWidth = 65.0;
      final double tooltipHeight = 30.0;
      final double bubbleOffset = 8.0;

      final Rect rect = Rect.fromLTWH(
        tx - (tooltipWidth / 2),
        ty - tooltipHeight - bubbleOffset,
        tooltipWidth,
        tooltipHeight,
      );

      final shadowPath = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)));
      canvas.drawShadow(shadowPath, Colors.black.withValues(alpha: 0.15), 4, false);

      final tooltipBgPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawPath(shadowPath, tooltipBgPaint);

      final arrowPath = Path();
      arrowPath.moveTo(tx - 4, ty - bubbleOffset);
      arrowPath.lineTo(tx + 4, ty - bubbleOffset);
      arrowPath.lineTo(tx, ty - bubbleOffset + 4);
      arrowPath.close();
      canvas.drawPath(arrowPath, tooltipBgPaint);

      // Tooltip date text
      final String tDate = tooltipDate ?? '14 May';
      final dateTextPainter = TextPainter(
        text: TextSpan(
          text: tDate,
          style: GoogleFonts.inter(
            fontSize: 7.5,
            color: AppTheme.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      dateTextPainter.paint(
        canvas,
        Offset(tx - (dateTextPainter.width / 2), rect.top + 3),
      );

      // Tooltip value text
      String tValueStr = '';
      if (tooltipValueFormatter != null) {
        tValueStr = tooltipValueFormatter!(data[tIdx]);
      } else {
        tValueStr = '₹${(data[tIdx] / 1000).toStringAsFixed(0)}K';
      }

      final valTextPainter = TextPainter(
        text: TextSpan(
          text: tValueStr,
          style: GoogleFonts.inter(
            fontSize: 9,
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      valTextPainter.paint(
        canvas,
        Offset(tx - (valTextPainter.width / 2), rect.top + 14),
      );
    }

    // Bottom labels
    final int stepIdx = (data.length / labels.length).floor();
    for (int i = 0; i < labels.length; i++) {
      int idx = i * stepIdx;
      if (idx >= data.length) {
        idx = data.length - 1;
      }
      final double x = getX(idx);
      textPainter.text = TextSpan(
        text: labels[i],
        style: GoogleFonts.inter(
          fontSize: 8.5,
          color: AppTheme.textMuted,
          fontWeight: FontWeight.w500,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - (textPainter.width / 2), size.height - paddingBottom + 6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
