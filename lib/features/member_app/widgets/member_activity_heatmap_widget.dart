import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/supabase_service.dart';

/// GitHub-style activity heatmap showing the member's gym attendance
/// over the current year. Each cell = 1 day, shaded by attendance intensity.
class MemberActivityHeatmapWidget extends StatefulWidget {
  final String memberId;
  final String gymId;

  const MemberActivityHeatmapWidget({
    super.key,
    required this.memberId,
    required this.gymId,
  });

  @override
  State<MemberActivityHeatmapWidget> createState() =>
      _MemberActivityHeatmapWidgetState();
}

class _MemberActivityHeatmapWidgetState
    extends State<MemberActivityHeatmapWidget> {
  Map<String, int> _activityMap = {};
  Set<String> _workoutCompletedDates = {};
  bool _isLoading = true;
  int _totalActiveDays = 0;
  int _currentStreak = 0;

  static const List<String> _monthLabels = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _loadHeatmapData();
  }

  Future<void> _loadHeatmapData() async {
    // Try offline cache first
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('member_heatmap_${widget.memberId}');
    if (cached != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(cached);
        setState(() {
          _activityMap = Map<String, int>.from(decoded['activity'] ?? {});
          _workoutCompletedDates =
              Set<String>.from((decoded['workouts'] as List?) ?? []);
          _computeStats();
          _isLoading = false;
        });
      } catch (_) {}
    }

    // Fetch from Supabase
    if (!SupabaseService.isInitialized || widget.memberId.isEmpty || widget.gymId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final year = DateTime.now().year;
      final result = await SupabaseService.client
          .rpc('get_member_activity_heatmap', params: {
        'p_member_id': widget.memberId,
        'p_gym_id': widget.gymId,
        'p_year': year,
      });

      final Map<String, int> activityMap = {};
      final Set<String> workoutDates = {};

      for (final row in (result as List)) {
        final dateStr = (row['activity_date'] as String).substring(0, 10);
        activityMap[dateStr] = (row['attendance_count'] as num).toInt();
        if (row['workout_completed'] == true) {
          workoutDates.add(dateStr);
        }
      }

      // Cache for offline
      await prefs.setString(
        'member_heatmap_${widget.memberId}',
        jsonEncode({
          'activity': activityMap,
          'workouts': workoutDates.toList(),
        }),
      );

      if (mounted) {
        setState(() {
          _activityMap = activityMap;
          _workoutCompletedDates = workoutDates;
          _computeStats();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _computeStats() {
    _totalActiveDays = _activityMap.values.where((v) => v > 0).length;

    // Prefer MemberAppViewModel streak from database RPC if available
    try {
      final vm = Provider.of<MemberAppViewModel>(context, listen: false);
      if (vm.currentStreak > 0) {
        _currentStreak = vm.currentStreak;
        return;
      }
    } catch (_) {}

    // Calculate current streak with Sunday & off-day preservation
    int streak = 0;
    var day = DateTime.now();
    final todayKey =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    if ((_activityMap[todayKey] ?? 0) > 0) {
      streak = 1;
      day = day.subtract(const Duration(days: 1));
    } else {
      streak = 0;
      day = day.subtract(const Duration(days: 1));
    }

    final now = DateTime.now();
    while (day.isAfter(now.subtract(const Duration(days: 365)))) {
      final key =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      if ((_activityMap[key] ?? 0) > 0) {
        streak++;
        day = day.subtract(const Duration(days: 1));
      } else if (day.weekday == DateTime.sunday) {
        // Skip Sundays without breaking streak
        day = day.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    _currentStreak = streak;
  }

  Color _cellColor(int count) {
    if (count == 0) return const Color(0xFFF0F0F4);
    if (count == 1) return AppTheme.primary.withValues(alpha: 0.25);
    if (count == 2) return AppTheme.primary.withValues(alpha: 0.50);
    return AppTheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Stats row ──
        Row(
          children: [
            _statChip('🔥', '$_currentStreak', 'day streak'),
            const SizedBox(width: 12),
            _statChip('📅', '$_totalActiveDays', 'days this year'),
          ],
        ),
        const SizedBox(height: 16),

        // ── Heatmap grid ──
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(
                color: AppTheme.primary,
                strokeWidth: 2,
              ),
            ),
          )
        else
          _buildHeatmapGrid(),

        const SizedBox(height: 8),

        // ── Legend ──
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Less',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
            const SizedBox(width: 4),
            ...[0, 1, 2, 3].map((level) => Container(
                  margin: const EdgeInsets.only(left: 3),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _cellColor(level),
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
            const SizedBox(width: 4),
            Text(
              'More',
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statChip(String emoji, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapGrid() {
    final now = DateTime.now();
    final year = now.year;
    // Build a full year grid — start from Jan 1
    final firstDay = DateTime(year, 1, 1);
    // Offset so we start from Monday
    final offset = (firstDay.weekday - 1) % 7; // 0=Mon

    // Total cells = 53 weeks × 7 days
    final totalCells = 53 * 7;
    final cells = List.generate(totalCells, (i) {
      final dayOffset = i - offset;
      if (dayOffset < 0) return null;
      final date = firstDay.add(Duration(days: dayOffset));
      if (date.year != year) return null;
      return date;
    });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month labels
          Row(
            children: List.generate(53, (week) {
              // Show month label at the first week of each month
              final dayOffset = week * 7 - offset;
              if (dayOffset < 0) return const SizedBox(width: 14);
              final date = firstDay.add(Duration(days: dayOffset));
              if (date.year != year) return const SizedBox(width: 14);
              final isFirstWeekOfMonth = date.day <= 7;
              return SizedBox(
                width: 14,
                child: isFirstWeekOfMonth
                    ? Text(
                        _monthLabels[date.month - 1],
                        style: GoogleFonts.inter(
                          fontSize: 8,
                          color: AppTheme.textMuted,
                        ),
                      )
                    : const SizedBox(),
              );
            }),
          ),
          const SizedBox(height: 4),
          // Grid rows (7 rows for Mon–Sun)
          ...List.generate(7, (dayOfWeek) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: List.generate(53, (week) {
                  final index = week * 7 + dayOfWeek;
                  if (index >= cells.length) return const SizedBox(width: 14);
                  final date = cells[index];
                  if (date == null) {
                    return const SizedBox(width: 14);
                  }
                  final key =
                      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                  final count = _activityMap[key] ?? 0;
                  final hasWorkout = _workoutCompletedDates.contains(key);
                  final isFuture = date.isAfter(now);

                  return Tooltip(
                    message: count > 0
                        ? '$key — attended${ hasWorkout ? ' + workout' : ''}'
                        : key,
                    child: Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(right: 2),
                      decoration: BoxDecoration(
                        color: isFuture
                            ? Colors.transparent
                            : _cellColor(count),
                        borderRadius: BorderRadius.circular(2),
                        border: hasWorkout
                            ? Border.all(
                                color: AppTheme.primary,
                                width: 1,
                              )
                            : null,
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }
}
