import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/supabase_service.dart';

/// Front + Back body muscle map widget — shaded by how much each muscle
/// group was trained in the last [days] days.
class MemberMuscleMapWidget extends StatefulWidget {
  final String memberId;
  final int days;

  const MemberMuscleMapWidget({
    super.key,
    required this.memberId,
    this.days = 7,
  });

  @override
  State<MemberMuscleMapWidget> createState() => _MemberMuscleMapWidgetState();
}

class _MemberMuscleMapWidgetState extends State<MemberMuscleMapWidget> {
  Map<String, int> _muscleActivity = {};
  int _selectedDays = 7;
  bool _isLoading = false;

  // Normalized muscle group names → display label
  static const Map<String, String> _muscleLabels = {
    'Chest': 'Chest',
    'Back': 'Back',
    'Legs': 'Legs',
    'Shoulders': 'Shoulders',
    'Arms': 'Arms',
    'Core': 'Core',
    'Cardio': 'Cardio',
  };

  static const Map<String, String> _muscleEmojis = {
    'Chest': '🫁',
    'Back': '🦵',
    'Legs': '🦵',
    'Shoulders': '💪',
    'Arms': '💪',
    'Core': '🎯',
    'Cardio': '❤️',
  };

  @override
  void initState() {
    super.initState();
    _selectedDays = widget.days;
    _loadMuscleActivity();
  }

  String? _normalizeMuscle(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('chest')) return 'Chest';
    if (lower.contains('back')) return 'Back';
    if (lower.contains('leg') || lower.contains('quad') || lower.contains('hamstring') || lower.contains('calves') || lower.contains('calf')) return 'Legs';
    if (lower.contains('shoulder') || lower.contains('delt')) return 'Shoulders';
    if (lower.contains('arm') || lower.contains('bicep') || lower.contains('tricep') || lower.contains('trisep')) return 'Arms';
    if (lower.contains('core') || lower.contains('ab')) return 'Core';
    if (lower.contains('cardio') || lower.contains('aerobic') || lower.contains('arobix') || lower.contains('steam') || lower.contains('treadmill') || lower.contains('cycling')) return 'Cardio';
    return null;
  }

  Future<void> _loadMuscleActivity() async {
    setState(() => _isLoading = true);

    // Try cache first
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('member_muscle_map_${widget.memberId}_$_selectedDays');
    if (cached != null) {
      try {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        setState(() {
          _muscleActivity = Map<String, int>.from(decoded);
          _isLoading = false;
        });
      } catch (_) {}
    }

    if (!SupabaseService.isInitialized) {
      setState(() => _isLoading = false);
      return;
    }

    final user = SupabaseService.client.auth.currentUser;
    final userId = user?.id ?? '';
    final memberId = widget.memberId;

    if (memberId.isEmpty && userId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final Map<String, int> activity = {};

      // 1. Try RPC for explicit sets
      if (memberId.isNotEmpty) {
        try {
          final result = await SupabaseService.client
              .rpc('get_member_muscle_activity', params: {
            'p_member_id': memberId,
            'p_days': _selectedDays,
          });

          for (final row in (result as List)) {
            final raw = row['muscle_group'] as String? ?? '';
            final norm = _normalizeMuscle(raw);
            if (norm != null) {
              activity[norm] = (activity[norm] ?? 0) + (row['total_sets'] as num).toInt();
            }
          }
        } catch (_) {}
      }

      final cutoffDate = DateTime.now().subtract(Duration(days: _selectedDays));
      final cutoffStr = cutoffDate.toIso8601String().substring(0, 10);

      // 2. Query member_workout_logs
      if (memberId.isNotEmpty) {
        try {
          final wLogs = await SupabaseService.client
              .from('member_workout_logs')
              .select('muscle, date')
              .eq('member_id', memberId)
              .gte('date', cutoffStr);

          for (final row in (wLogs as List)) {
            final raw = row['muscle']?.toString() ?? '';
            final norm = _normalizeMuscle(raw);
            if (norm != null) {
              activity[norm] = (activity[norm] ?? 0) + 4; // 4 sets per logged session
            }
          }
        } catch (_) {}
      }

      // 3. Match member attendance with workout plan schedule
      try {
        var attQuery = SupabaseService.client
            .from('attendance_logs')
            .select('check_in, status')
            .gte('check_in', cutoffDate.toIso8601String());

        if (memberId.isNotEmpty && userId.isNotEmpty) {
          attQuery = attQuery.or('member_id.eq.$memberId,user_id.eq.$userId');
        } else if (memberId.isNotEmpty) {
          attQuery = attQuery.eq('member_id', memberId);
        } else {
          attQuery = attQuery.eq('user_id', userId);
        }

        final attLogs = await attQuery;

        Map<String, dynamic>? weeklySchedule;
        final cachedSchedule = prefs.getString('member_cached_schedule_json');
        if (cachedSchedule != null) {
          try {
            weeklySchedule = jsonDecode(cachedSchedule) as Map<String, dynamic>;
          } catch (_) {}
        }

        if (weeklySchedule == null && memberId.isNotEmpty) {
          final mRow = await SupabaseService.client
              .from('members')
              .select('assigned_workout_id')
              .eq('id', memberId)
              .maybeSingle();

          final planId = mRow?['assigned_workout_id']?.toString() ?? '';
          if (planId.isNotEmpty) {
            final pRow = await SupabaseService.client
                .from('workout_plans')
                .select('schedule')
                .eq('id', planId)
                .maybeSingle();

            if (pRow != null && pRow['schedule'] != null) {
              dynamic s = pRow['schedule'];
              if (s is String) {
                try { s = jsonDecode(s); } catch (_) {}
              }
              if (s is Map) {
                weeklySchedule = Map<String, dynamic>.from(s);
                await prefs.setString('member_cached_schedule_json', jsonEncode(weeklySchedule));
              }
            }
          }
        }

        if (weeklySchedule != null) {
          for (final row in (attLogs as List)) {
            final checkInStr = row['check_in']?.toString();
            final status = row['status']?.toString() ?? 'Present';
            if (checkInStr != null && status != 'Absent' && status != 'Leave') {
              final checkInDate = DateTime.tryParse(checkInStr);
              if (checkInDate != null) {
                final dayName = DateFormat('EEEE').format(checkInDate);
                final daySplits = weeklySchedule[dayName];
                if (daySplits is List) {
                  for (final item in daySplits) {
                    String title = '';
                    if (item is Map) {
                      title = item['title']?.toString() ?? '';
                    } else if (item is String) {
                      title = item;
                    }
                    final norm = _normalizeMuscle(title);
                    if (norm != null) {
                      activity[norm] = (activity[norm] ?? 0) + 3;
                    }
                  }
                }
              }
            }
          }
        }
      } catch (_) {}

      final cacheKey = memberId.isNotEmpty ? memberId : userId;
      await prefs.setString(
        'member_muscle_map_${cacheKey}_$_selectedDays',
        jsonEncode(activity),
      );

      if (mounted) {
        setState(() {
          _muscleActivity = activity;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Color _muscleColor(String muscle) {
    final sets = _muscleActivity[muscle] ?? 0;
    if (sets == 0) return const Color(0xFFE5E7EB);
    if (sets <= 3) return AppTheme.primary.withValues(alpha: 0.3);
    if (sets <= 8) return AppTheme.primary.withValues(alpha: 0.6);
    return AppTheme.primary;
  }

  String _muscleStatus(String muscle) {
    final sets = _muscleActivity[muscle] ?? 0;
    if (sets == 0) return 'Not trained';
    if (sets <= 3) return '$sets sets — Light';
    if (sets <= 8) return '$sets sets — Moderate';
    return '$sets sets — Heavy';
  }

  @override
  Widget build(BuildContext context) {
    // Muscles not trained in selected period
    final untrained = _muscleLabels.keys
        .where((m) => (_muscleActivity[m] ?? 0) == 0)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Period selector ──
        Row(
          children: [7, 30, 90].map((days) {
            final isSelected = _selectedDays == days;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedDays = days);
                _loadMuscleActivity();
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : AppTheme.border,
                  ),
                ),
                child: Text(
                  '${days}d',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 16),

        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(
              color: AppTheme.primary,
              strokeWidth: 2,
            ),
          )
        else ...[
          // ── Muscle group bars ──
          ..._muscleLabels.entries.map((entry) {
            final muscle = entry.key;
            final sets = _muscleActivity[muscle] ?? 0;
            final maxSets = _muscleActivity.values.fold(1, (a, b) => a > b ? a : b);
            final progress = sets == 0 ? 0.0 : (sets / maxSets).clamp(0.05, 1.0);

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            _muscleEmojis[muscle] ?? '💪',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            muscle,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _muscleStatus(muscle),
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: sets == 0
                              ? AppTheme.textMuted
                              : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _muscleColor(muscle),
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            );
          }),

          // ── Untrained notice ──
          if (untrained.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Not trained in last ${_selectedDays}d: ${untrained.join(', ')}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF92400E),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
