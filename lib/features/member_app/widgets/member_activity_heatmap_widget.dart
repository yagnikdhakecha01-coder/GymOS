import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/supabase_service.dart';
import '../member_app_viewmodel.dart';

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
  final ScrollController _scrollController = ScrollController();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentMonth();
    });
  }

  @override
  void didUpdateWidget(MemberActivityHeatmapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.memberId != widget.memberId || oldWidget.gymId != widget.gymId) {
      _loadHeatmapData();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToCurrentMonth() {
    if (_scrollController.hasClients) {
      final now = DateTime.now();
      final dayOfYear = now.difference(DateTime(now.year, 1, 1)).inDays;
      final currentWeek = (dayOfYear / 7).floor();
      // Each week is 14px (12px cell + 2px margin)
      final targetOffset = (currentWeek * 14.0 - 80.0)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(targetOffset);
    }
  }

  Future<void> _loadHeatmapData() async {
    // Try offline cache first
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('member_heatmap_${widget.memberId}');
    if (cached != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(cached);
        if (mounted) {
          setState(() {
            _activityMap = Map<String, int>.from(decoded['activity'] ?? {});
            _workoutCompletedDates =
                Set<String>.from((decoded['workouts'] as List?) ?? []);
            _computeStats();
            _isLoading = false;
          });
        }
      } catch (_) {}
    }

    // Fetch from Supabase
    if (!SupabaseService.isInitialized) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final user = SupabaseService.client.auth.currentUser;
    final userId = user?.id ?? '';
    final memberId = widget.memberId;

    if (memberId.isEmpty && userId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final uuidRegex = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    final isMemberUuid = uuidRegex.hasMatch(memberId);
    final isGymUuid = uuidRegex.hasMatch(widget.gymId);
    final isUserUuid = uuidRegex.hasMatch(userId);

    try {
      final Map<String, int> activityMap = {};
      final Set<String> workoutDates = {};

      // 1. Try RPC if gymId & memberId available with valid UUIDs
      if (isGymUuid && isMemberUuid) {
        try {
          final year = DateTime.now().year;
          final result = await SupabaseService.client
              .rpc('get_member_activity_heatmap', params: {
            'p_member_id': memberId,
            'p_gym_id': widget.gymId,
            'p_year': year,
          });

          for (final row in (result as List)) {
            final dateStr = (row['activity_date'] as String).substring(0, 10);
            activityMap[dateStr] = (row['attendance_count'] as num).toInt();
            if (row['workout_completed'] == true) {
              workoutDates.add(dateStr);
            }
          }
        } catch (_) {}
      }

      // 2. Direct attendance_logs check to guarantee all member logs are captured
      try {
        if (isMemberUuid || isUserUuid) {
          var query = SupabaseService.client
              .from('attendance_logs')
              .select('check_in, status, shift_status');
          if (isMemberUuid && isUserUuid) {
            query = query.or('member_id.eq.$memberId,user_id.eq.$userId');
          } else if (isMemberUuid) {
            query = query.eq('member_id', memberId);
          } else {
            query = query.eq('user_id', userId);
          }

          final logs = await query.order('check_in', ascending: false);
          for (final row in (logs as List)) {
            final checkInStr = row['check_in']?.toString();
            final status = row['status']?.toString() ?? 'Present';
            if (checkInStr != null &&
                status != 'Absent' &&
                status != 'Leave' &&
                status != 'On Leave') {
              final dateStr = checkInStr.substring(0, 10);
              activityMap[dateStr] = (activityMap[dateStr] ?? 0) + 1;
              if (row['shift_status'] == 'Workout Completed') {
                workoutDates.add(dateStr);
              }
            }
          }
        }
      } catch (_) {}

      // 3. Check member_workout_logs for workouts
      try {
        if (isMemberUuid) {
          final wLogs = await SupabaseService.client
              .from('member_workout_logs')
              .select('date, status')
              .eq('member_id', memberId);
          for (final row in (wLogs as List)) {
            final d = row['date']?.toString();
            if (d != null && d.length >= 10) {
              workoutDates.add(d.substring(0, 10));
            }
          }
        }
      } catch (_) {}

      // Cache for offline
      final cacheKey = memberId.isNotEmpty ? memberId : userId;
      await prefs.setString(
        'member_heatmap_$cacheKey',
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToCurrentMonth();
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
    if (count == 0) return const Color(0xFFF1F5F9);
    if (count == 1) return const Color(0xFFC7D2FE);
    if (count == 2) return const Color(0xFF818CF8);
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

        const SizedBox(height: 10),

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
                    border: Border.all(
                      color: level == 0
                          ? const Color(0xFFCBD5E1)
                          : AppTheme.primary.withValues(alpha: 0.3),
                      width: 0.6,
                    ),
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

  Widget _dayLabel(String text) {
    return SizedBox(
      width: 12,
      height: 12,
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: AppTheme.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildHeatmapGrid() {
    final now = DateTime.now();
    final year = now.year;
    final firstDay = DateTime(year, 1, 1);
    final offset = (firstDay.weekday - 1) % 7; // 0=Mon, 6=Sun

    final totalCells = 53 * 7;
    final cells = List.generate(totalCells, (i) {
      final dayOffset = i - offset;
      if (dayOffset < 0) return null;
      final date = firstDay.add(Duration(days: dayOffset));
      if (date.year != year) return null;
      return date;
    });

    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month labels row
          Row(
            children: [
              const SizedBox(width: 18), // Space corresponding to day label column
              ...List.generate(53, (week) {
                final dayOffset = week * 7 - offset;
                if (dayOffset < 0) return const SizedBox(width: 14);
                final date = firstDay.add(Duration(days: dayOffset));
                if (date.year != year) return const SizedBox(width: 14);
                final isFirstWeekOfMonth = date.day <= 7;
                return SizedBox(
                  width: 14,
                  height: 16,
                  child: isFirstWeekOfMonth
                      ? Text(
                          _monthLabels[date.month - 1],
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.visible,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMuted,
                          ),
                        )
                      : null,
                );
              }),
            ],
          ),
          const SizedBox(height: 4),

          // Day label column + 7 rows of 53 weeks
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Mon, Wed, Fri day labels
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Column(
                  children: [
                    _dayLabel('M'),
                    const SizedBox(height: 2),
                    _dayLabel(''),
                    const SizedBox(height: 2),
                    _dayLabel('W'),
                    const SizedBox(height: 2),
                    _dayLabel(''),
                    const SizedBox(height: 2),
                    _dayLabel('F'),
                    const SizedBox(height: 2),
                    _dayLabel(''),
                    const SizedBox(height: 2),
                    _dayLabel(''),
                  ],
                ),
              ),

              // 7 Day rows
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(7, (dayOfWeek) {
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
                              ? '$key — attended${hasWorkout ? ' + workout' : ''}'
                              : (isFuture ? '$key (Upcoming)' : key),
                          child: Container(
                            width: 12,
                            height: 12,
                            margin: const EdgeInsets.only(right: 2),
                            decoration: BoxDecoration(
                              color: _cellColor(count),
                              borderRadius: BorderRadius.circular(2.5),
                              border: Border.all(
                                color: count > 0
                                    ? AppTheme.primary.withValues(alpha: 0.4)
                                    : const Color(0xFFE2E8F0),
                                width: 0.8,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
