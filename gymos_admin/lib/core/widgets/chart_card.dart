import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../theme/admin_theme.dart';

class ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget chart;
  final double height;
  final List<Widget>? actions;

  const ChartCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.chart,
    this.height = 280,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AdminTheme.textColor(context),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AdminTheme.mutedTextColor(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ...?actions,
              ],
            ),
          ),
          SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: chart,
            ),
          ),
        ],
      ),
    );
  }
}

/// Convenience builder for common line chart
class AdminLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final Color color;
  final double? maxY;
  final List<String>? bottomLabels;

  const AdminLineChart({
    super.key,
    required this.spots,
    this.color = AdminTheme.primary,
    this.maxY,
    this.bottomLabels,
  });

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY != null ? maxY! / 4 : null,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AdminTheme.borderColor(context),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  _formatValue(value),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AdminTheme.mutedTextColor(context),
                  ),
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: bottomLabels != null,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (bottomLabels != null && idx >= 0 && idx < bottomLabels!.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      bottomLabels![idx],
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AdminTheme.mutedTextColor(context),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
              _formatValue(s.y),
              GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            )).toList(),
          ),
        ),
      ),
    );
  }

  String _formatValue(double value) {
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }
}

/// Convenience builder for bar chart
class AdminBarChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final Color color;

  const AdminBarChart({
    super.key,
    required this.values,
    required this.labels,
    this.color = AdminTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                _formatValue(rod.toY),
                GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx >= 0 && idx < labels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      labels[idx],
                      style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  _formatValue(value),
                  style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                ),
              ),
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: AdminTheme.borderColor(context),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: values.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value,
                color: color,
                width: 20,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  String _formatValue(double value) {
    if (value >= 100000) return '${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }
}

/// Convenience builder for pie/donut chart
class AdminDonutChart extends StatelessWidget {
  final List<DonutChartSection> sections;
  final double centerRadius;

  const AdminDonutChart({
    super.key,
    required this.sections,
    this.centerRadius = 50,
  });

  @override
  Widget build(BuildContext context) {
    return PieChart(
      PieChartData(
        sections: sections.map((s) => PieChartSectionData(
          value: s.value,
          color: s.color,
          title: s.showTitle ? '${s.value.toStringAsFixed(0)}%' : '',
          titleStyle: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          radius: 24,
          titlePositionPercentageOffset: 0.6,
        )).toList(),
        centerSpaceRadius: centerRadius,
        sectionsSpace: 2,
      ),
    );
  }
}

class DonutChartSection {
  final double value;
  final Color color;
  final String label;
  final bool showTitle;

  const DonutChartSection({
    required this.value,
    required this.color,
    required this.label,
    this.showTitle = true,
  });
}
