import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/supabase_service.dart';
import 'member_exercise_library_screen.dart';

// ─────────────────────────────────────────────────────────────
// Member Workout Plan Screen
// 7-Day Workout Routine Viewer & Planner with Supabase + Cache sync.
// Allows members to see and manage exercises planned for each day.
// ─────────────────────────────────────────────────────────────

class MemberWorkoutPlanScreen extends StatefulWidget {
  final String? memberId;
  final String? gymId;
  final int? initialDayOfWeek; // 1 = Mon, 7 = Sun

  const MemberWorkoutPlanScreen({
    super.key,
    this.memberId,
    this.gymId,
    this.initialDayOfWeek,
  });

  @override
  State<MemberWorkoutPlanScreen> createState() =>
      _MemberWorkoutPlanScreenState();
}

class _MemberWorkoutPlanScreenState extends State<MemberWorkoutPlanScreen> {
  late int _selectedDay; // 1=Mon, 7=Sun
  bool _isLoading = true;
  bool _isSaving = false;
  String _memberId = '';
  String _gymId = '';

  // Day index 1..7 mapping to schedule map
  final Map<int, Map<String, dynamic>> _weeklySchedule = {};

  static const List<Map<String, dynamic>> _defaultDays = [
    {'day': 1, 'name': 'Monday', 'short': 'Mon', 'muscle': 'Chest & Triceps', 'is_rest': false},
    {'day': 2, 'name': 'Tuesday', 'short': 'Tue', 'muscle': 'Back & Biceps', 'is_rest': false},
    {'day': 3, 'name': 'Wednesday', 'short': 'Wed', 'muscle': 'Legs & Core', 'is_rest': false},
    {'day': 4, 'name': 'Thursday', 'short': 'Thu', 'muscle': 'Shoulders & Abs', 'is_rest': false},
    {'day': 5, 'name': 'Friday', 'short': 'Fri', 'muscle': 'Chest & Back', 'is_rest': false},
    {'day': 6, 'name': 'Saturday', 'short': 'Sat', 'muscle': 'Full Body / Cardio', 'is_rest': false},
    {'day': 7, 'name': 'Sunday', 'short': 'Sun', 'muscle': 'Rest & Recovery', 'is_rest': true},
  ];

  static const String _imgBase =
      'https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@7455efae41b330c265e7cd4b78dfa848e7ce5ebd/images/';

  @override
  void initState() {
    super.initState();
    _memberId = widget.memberId ?? '';
    _gymId = widget.gymId ?? '';
    final todayWeekday = DateTime.now().weekday; // 1..7
    _selectedDay = widget.initialDayOfWeek ?? todayWeekday;

    // Seed defaults first
    for (final d in _defaultDays) {
      _weeklySchedule[d['day'] as int] = {
        'day_of_week': d['day'],
        'muscle_group': d['muscle'],
        'is_rest_day': d['is_rest'],
        'notes': '',
        'exercises': <Map<String, dynamic>>[],
      };
    }

    _loadSchedule();
  }

  String get _cacheKey => 'member_weekly_schedule_$_memberId';

  Future<void> _loadSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    if (_memberId.isEmpty) {
      _memberId = prefs.getString('gymos_member_id') ?? '';
    }
    if (_gymId.isEmpty) {
      _gymId = prefs.getString('gymos_gym_id') ?? '';
    }

    // 1. Instant load from local cache
    final cachedStr = prefs.getString(_cacheKey);
    if (cachedStr != null) {
      try {
        final List list = jsonDecode(cachedStr);
        for (final item in list) {
          final map = Map<String, dynamic>.from(item as Map);
          final day = (map['day_of_week'] as num?)?.toInt();
          if (day != null && day >= 1 && day <= 7) {
            List<Map<String, dynamic>> exList = [];
            if (map['exercises'] is List) {
              exList = (map['exercises'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
            }
            _weeklySchedule[day] = {
              'day_of_week': day,
              'muscle_group': map['muscle_group'] ?? _weeklySchedule[day]?['muscle_group'] ?? 'General',
              'is_rest_day': map['is_rest_day'] ?? false,
              'notes': map['notes'] ?? '',
              'exercises': exList,
            };
          }
        }
        if (mounted) setState(() => _isLoading = false);
      } catch (_) {}
    }

    // 2. Fetch from Supabase
    if (SupabaseService.isInitialized && _memberId.isNotEmpty) {
      try {
        final res = await SupabaseService.client
            .from('member_weekly_schedule')
            .select()
            .eq('member_id', _memberId);

        if (res.isNotEmpty) {
          for (final row in res) {
            final day = (row['day_of_week'] as num?)?.toInt();
            if (day != null && day >= 1 && day <= 7) {
              List<Map<String, dynamic>> exList = [];
              if (row['exercises'] is List) {
                exList = (row['exercises'] as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList();
              } else if (row['exercises'] is String) {
                try {
                  exList = (jsonDecode(row['exercises']) as List)
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList();
                } catch (_) {}
              }

              _weeklySchedule[day] = {
                'day_of_week': day,
                'muscle_group': row['muscle_group'] ?? _weeklySchedule[day]?['muscle_group'] ?? 'General',
                'is_rest_day': row['is_rest_day'] ?? false,
                'notes': row['notes'] ?? '',
                'exercises': exList,
              };
            }
          }

          // Cache fresh data
          await prefs.setString(
              _cacheKey,
              jsonEncode(_weeklySchedule.values.toList()));
        }
      } catch (e) {
        debugPrint('Error fetching weekly schedule: $e');
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveDaySchedule(int day) async {
    final dayData = _weeklySchedule[day];
    if (dayData == null) return;

    setState(() => _isSaving = true);

    // Save to local cache first
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _cacheKey,
          jsonEncode(_weeklySchedule.values.toList()));
    } catch (_) {}

    // Save to Supabase
    if (SupabaseService.isInitialized &&
        _memberId.isNotEmpty &&
        _gymId.isNotEmpty) {
      try {
        await SupabaseService.client.from('member_weekly_schedule').upsert({
          'gym_id': _gymId,
          'member_id': _memberId,
          'day_of_week': day,
          'muscle_group': dayData['muscle_group'] ?? 'General',
          'is_rest_day': dayData['is_rest_day'] ?? false,
          'notes': dayData['notes'] ?? '',
          'exercises': dayData['exercises'] ?? [],
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'member_id, day_of_week');
      } catch (e) {
        debugPrint('Error saving weekly schedule to Supabase: $e');
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
    }
  }

  void _removeExercise(int day, int index) async {
    final dayData = _weeklySchedule[day];
    if (dayData == null) return;
    final List list = List.from(dayData['exercises'] ?? []);
    if (index >= 0 && index < list.length) {
      final removed = list.removeAt(index);
      setState(() {
        dayData['exercises'] = list;
      });
      await _saveDaySchedule(day);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${removed['name'] ?? 'exercise'} from ${_getDayName(day)}'),
            backgroundColor: AppTheme.textPrimary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _editMuscleGroup(int day) {
    final current = _weeklySchedule[day]?['muscle_group']?.toString() ?? '';
    final ctrl = TextEditingController(text: current);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Edit ${_getDayName(day)} Muscle',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set target muscle or focus for this day (e.g. Chest & Back, Legs, Rest):',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'e.g. Chest & Triceps',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty) {
                setState(() {
                  _weeklySchedule[day]?['muscle_group'] = newName;
                });
                _saveDaySchedule(day);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _getDayName(int day) {
    switch (day) {
      case 1:
        return 'Monday';
      case 2:
        return 'Tuesday';
      case 3:
        return 'Wednesday';
      case 4:
        return 'Thursday';
      case 5:
        return 'Friday';
      case 6:
        return 'Saturday';
      case 7:
        return 'Sunday';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday;
    final currentDayData = _weeklySchedule[_selectedDay] ?? {};
    final String muscle = currentDayData['muscle_group']?.toString() ?? 'General';
    final bool isRest = currentDayData['is_rest_day'] == true;
    final List exercises = (currentDayData['exercises'] as List?) ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'My Workout Plan',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.fitness_center_rounded, color: AppTheme.primary),
            tooltip: 'Browse All Exercises',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MemberExerciseLibraryScreen(
                    initialMuscleGroup: muscle,
                    memberId: widget.memberId,
                    gymId: widget.gymId,
                  ),
                ),
              );
              _loadSchedule();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            )
          : Column(
              children: [
                // ── 7-Day Horizontal Selector ──
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SizedBox(
                    height: 68,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _defaultDays.length,
                      itemBuilder: (context, i) {
                        final d = _defaultDays[i];
                        final dayNum = d['day'] as int;
                        final isSelected = dayNum == _selectedDay;
                        final isToday = dayNum == today;
                        final dayPlan = _weeklySchedule[dayNum];
                        final exCount = (dayPlan?['exercises'] as List?)?.length ?? 0;

                        return GestureDetector(
                          onTap: () => setState(() => _selectedDay = dayNum),
                          child: Container(
                            width: 58,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? const LinearGradient(
                                      colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: isSelected ? null : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isToday && !isSelected
                                    ? AppTheme.primary
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  d['short'] as String,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? Colors.white70
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  isToday ? 'TODAY' : '$exCount',
                                  style: GoogleFonts.inter(
                                    fontSize: isToday ? 10 : 14,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? Colors.white
                                        : (isToday ? AppTheme.primary : const Color(0xFF0F172A)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),

                const Divider(height: 1, color: Color(0xFFE2E8F0)),

                // ── Day Details & Planned Exercises ──
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Day Target Focus Card
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isRest
                                  ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                                  : [const Color(0xFF4338CA), const Color(0xFF6366F1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: (isRest ? const Color(0xFF0F172A) : const Color(0xFF4338CA))
                                    .withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          isRest
                                              ? Icons.bedtime_rounded
                                              : Icons.fitness_center_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        _getDayName(_selectedDay),
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  // Edit muscle button
                                  IconButton(
                                    icon: const Icon(Icons.edit_rounded, color: Colors.white, size: 18),
                                    onPressed: () => _editMuscleGroup(_selectedDay),
                                    tooltip: 'Change Target Muscle',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                isRest ? 'Rest & Recovery Day' : muscle,
                                style: GoogleFonts.inter(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                isRest
                                    ? 'Rest is when muscles recover and grow stronger.'
                                    : '${exercises.length} planned exercises for this session',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Rest Day Toggle
                              Row(
                                children: [
                                  Text(
                                    'Mark as Rest Day',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const Spacer(),
                                  Switch(
                                    value: isRest,
                                    activeThumbColor: Colors.white,
                                    activeTrackColor: AppTheme.success,
                                    inactiveThumbColor: Colors.white,
                                    inactiveTrackColor: Colors.white24,
                                    onChanged: (val) {
                                      setState(() {
                                        currentDayData['is_rest_day'] = val;
                                      });
                                      _saveDaySchedule(_selectedDay);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Section Title: Exercises
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'PLANNED EXERCISES (${exercises.length})',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.add_rounded, size: 16),
                              label: const Text('Add Exercise'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MemberExerciseLibraryScreen(
                                      initialMuscleGroup: muscle,
                                      memberId: widget.memberId,
                                      gymId: widget.gymId,
                                    ),
                                  ),
                                );
                                _loadSchedule();
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // Exercise List
                        if (exercises.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 36),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.fitness_center_rounded,
                                    size: 28,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'No exercises planned for ${_getDayName(_selectedDay)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Add exercises from the library to customize your workout routine.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 18),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.search_rounded, size: 16),
                                  label: const Text('Browse Exercise Library'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 12),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MemberExerciseLibraryScreen(
                                          initialMuscleGroup: muscle,
                                          memberId: widget.memberId,
                                          gymId: widget.gymId,
                                        ),
                                      ),
                                    );
                                    _loadSchedule();
                                  },
                                ),
                              ],
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: exercises.length,
                            itemBuilder: (context, idx) {
                              final ex = Map<String, dynamic>.from(exercises[idx] as Map);
                              final name = ex['name']?.toString() ?? 'Exercise';
                              final target = ex['target']?.toString() ?? ex['muscle'] ?? muscle;
                              final eq = ex['equipment']?.toString() ?? 'Bodyweight';
                              final sets = ex['target_sets'] ?? 3;
                              final reps = ex['target_reps'] ?? '8-12';
                              final img = ex['img']?.toString() ?? '';
                              final imgUrl = img.isNotEmpty ? '$_imgBase$img' : '';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.02),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    // Thumbnail
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        width: 52,
                                        height: 52,
                                        color: const Color(0xFFF8FAFC),
                                        child: imgUrl.isNotEmpty
                                            ? Image.network(
                                                imgUrl,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) => Center(
                                                  child: Icon(
                                                    Icons.fitness_center_rounded,
                                                    color: AppTheme.primary.withValues(alpha: 0.4),
                                                    size: 24,
                                                  ),
                                                ),
                                              )
                                            : Center(
                                                child: Icon(
                                                  Icons.fitness_center_rounded,
                                                  color: AppTheme.primary.withValues(alpha: 0.4),
                                                  size: 24,
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: GoogleFonts.inter(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF0F172A),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '$target · $eq',
                                            style: GoogleFonts.inter(
                                              fontSize: 11.5,
                                              color: const Color(0xFF64748B),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 5),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primary.withValues(alpha: 0.08),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '$sets sets × $reps reps',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.primary,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Delete button
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded,
                                          color: Color(0xFFEF4444), size: 20),
                                      onPressed: () => _removeExercise(_selectedDay, idx),
                                      tooltip: 'Remove from Plan',
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
