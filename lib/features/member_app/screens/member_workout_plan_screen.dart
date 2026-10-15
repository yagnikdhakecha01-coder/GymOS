import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/supabase_service.dart';
import '../member_app_viewmodel.dart';
import 'member_exercise_library_screen.dart';

// ─────────────────────────────────────────────────────────────
// Member Workout Plan Screen
// Supports dual-mode planning:
// 1. Gym Plan (Official 7-day routine assigned by Gym Owner)
// 2. My Custom Plan (Member-created personalized 7-day routine)
// Allows seamless switching, toggling active routine, and full custom editing.
// ─────────────────────────────────────────────────────────────

class MemberWorkoutPlanScreen extends StatefulWidget {
  final String? memberId;
  final String? gymId;
  final String? workoutPlanId;
  final String? workoutPlanTitle;
  final int? initialDayOfWeek; // 1 = Mon, 7 = Sun

  const MemberWorkoutPlanScreen({
    super.key,
    this.memberId,
    this.gymId,
    this.workoutPlanId,
    this.workoutPlanTitle,
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
  String _workoutPlanId = '';
  String _workoutPlanTitle = '';

  // Mode: 'gym' (Official gym plan) vs 'custom' (Member's own custom plan)
  String _viewingMode = 'gym';
  String _activePlanMode = 'gym';

  Map<String, dynamic> _rawOwnerSchedule = {};
  bool _hasOwnerPlan = false;
  bool _hasCustomPlan = false;
  bool get hasCustomPlan => _hasCustomPlan;

  // Schedules (day 1..7)
  final Map<int, Map<String, dynamic>> _ownerWeeklySchedule = {};
  final Map<int, Map<String, dynamic>> _customWeeklySchedule = {};

  static const List<Map<String, dynamic>> _defaultDays = [
    {'day': 1, 'name': 'Monday', 'short': 'Mon', 'is_rest': false},
    {'day': 2, 'name': 'Tuesday', 'short': 'Tue', 'is_rest': false},
    {'day': 3, 'name': 'Wednesday', 'short': 'Wed', 'is_rest': false},
    {'day': 4, 'name': 'Thursday', 'short': 'Thu', 'is_rest': false},
    {'day': 5, 'name': 'Friday', 'short': 'Fri', 'is_rest': false},
    {'day': 6, 'name': 'Saturday', 'short': 'Sat', 'is_rest': false},
    {'day': 7, 'name': 'Sunday', 'short': 'Sun', 'is_rest': true},
  ];

  static const List<String> _quickMuscleSuggestions = [
    'Chest',
    'Back',
    'Legs',
    'Shoulders',
    'Arms',
    'Biceps',
    'Triceps',
    'Abs & Core',
    'Cardio',
    'Full Body',
    'Push Day',
    'Pull Day',
    'Rest Day',
  ];

  static const String _imgBase =
      'https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@7455efae41b330c265e7cd4b78dfa848e7ce5ebd/images/';

  @override
  void initState() {
    super.initState();
    _memberId = widget.memberId ?? '';
    _gymId = widget.gymId ?? '';
    _workoutPlanId = widget.workoutPlanId ?? '';
    _workoutPlanTitle = widget.workoutPlanTitle ?? '';
    final todayWeekday = DateTime.now().weekday; // 1..7
    _selectedDay = widget.initialDayOfWeek ?? todayWeekday;

    // Initialize blank base structures
    for (final d in _defaultDays) {
      final dayNum = d['day'] as int;
      _ownerWeeklySchedule[dayNum] = {
        'day_of_week': dayNum,
        'muscle_group': '',
        'is_rest_day': d['is_rest'] as bool,
        'notes': '',
        'exercises': <Map<String, dynamic>>[],
      };
      _customWeeklySchedule[dayNum] = {
        'day_of_week': dayNum,
        'muscle_group': '',
        'is_rest_day': d['is_rest'] as bool,
        'notes': '',
        'exercises': <Map<String, dynamic>>[],
      };
    }

    _loadSchedules();
  }

  String get _customCacheKey => 'member_weekly_schedule_$_memberId';

  void _seedOwnerSchedule(Map<String, dynamic> rawSchedule) {
    _rawOwnerSchedule = Map<String, dynamic>.from(rawSchedule);
    _hasOwnerPlan = true;
    const dayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];

    for (int dayNum = 1; dayNum <= 7; dayNum++) {
      final dayName = dayNames[dayNum - 1];
      dynamic dayList;
      for (final entry in rawSchedule.entries) {
        if (entry.key.toString().trim().toLowerCase() == dayName.toLowerCase()) {
          dayList = entry.value;
          break;
        }
      }

      final List<String> splits = [];
      if (dayList is List) {
        for (final item in dayList) {
          String t = '';
          if (item is Map) {
            t = item['title']?.toString() ?? '';
          } else if (item is String) {
            t = item;
          }
          if (t.trim().isNotEmpty) splits.add(t.trim());
        }
      } else if (dayList is Map) {
        final t = dayList['title']?.toString() ?? '';
        if (t.trim().isNotEmpty) splits.add(t.trim());
      } else if (dayList is String && dayList.trim().isNotEmpty) {
        splits.add(dayList.trim());
      }

      bool isRest = false;
      String muscle = '';
      if (splits.isEmpty) {
        isRest = true;
        muscle = 'Rest & Recovery';
      } else {
        final realSplits =
            splits.where((s) => !s.toLowerCase().contains('rest')).toList();
        if (realSplits.isEmpty) {
          isRest = true;
          muscle = 'Rest & Recovery';
        } else {
          isRest = false;
          muscle = realSplits.join(' & ');
        }
      }

      final existingExercises =
          _ownerWeeklySchedule[dayNum]?['exercises'] as List? ?? [];
      _ownerWeeklySchedule[dayNum] = {
        'day_of_week': dayNum,
        'muscle_group': muscle,
        'is_rest_day': isRest,
        'notes': _ownerWeeklySchedule[dayNum]?['notes'] ?? '',
        'exercises': existingExercises,
      };
    }
  }

  Future<void> _loadSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    if (_memberId.isEmpty) {
      _memberId = prefs.getString('gymos_member_id') ?? '';
    }
    if (_gymId.isEmpty) {
      _gymId = prefs.getString('gymos_gym_id') ?? '';
    }
    if (_workoutPlanId.isEmpty) {
      _workoutPlanId = prefs.getString('member_cached_workout_id') ?? '';
    }
    if (_workoutPlanTitle.isEmpty) {
      _workoutPlanTitle = prefs.getString('member_cached_workout_title') ?? '';
    }

    // 1. Read stored active plan mode
    final storedActive = prefs.getString('member_active_plan_mode_$_memberId');
    if (storedActive != null && storedActive.isNotEmpty) {
      _activePlanMode = storedActive;
      _viewingMode = storedActive;
    }

    // 2. Load Gym Owner Schedule (from cache first)
    if (_workoutPlanId.isNotEmpty) {
      final cachedOwnerSchedStr =
          prefs.getString('member_cached_workout_schedule_$_memberId') ??
              prefs.getString('member_cached_workout_schedule');
      if (cachedOwnerSchedStr != null && cachedOwnerSchedStr.isNotEmpty) {
        try {
          final map = jsonDecode(cachedOwnerSchedStr);
          if (map is Map) {
            _seedOwnerSchedule(Map<String, dynamic>.from(map));
          }
        } catch (_) {}
      }
    }

    // 3. Load Member Custom Schedule (from cache first)
    final customCachedStr = prefs.getString(_customCacheKey);
    if (customCachedStr != null && customCachedStr.isNotEmpty) {
      try {
        final List list = jsonDecode(customCachedStr);
        bool foundAny = false;
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
            final m = (map['muscle_group']?.toString() ?? '').trim();
            if ((m.isNotEmpty && !m.toLowerCase().contains('rest')) ||
                exList.isNotEmpty) {
              foundAny = true;
            }
            _customWeeklySchedule[day] = {
              'day_of_week': day,
              'muscle_group': m,
              'is_rest_day': map['is_rest_day'] ?? false,
              'notes': map['notes'] ?? '',
              'exercises': exList,
            };
          }
        }
        _hasCustomPlan = foundAny;
      } catch (_) {}
    }

    // If owner plan is not assigned and active was not chosen, default to custom!
    if (!_hasOwnerPlan && storedActive == null) {
      _activePlanMode = 'custom';
      _viewingMode = 'custom';
    }

    if (mounted) setState(() => _isLoading = false);

    // 4. Online sync from Supabase
    if (SupabaseService.isInitialized && _memberId.isNotEmpty) {
      try {
        // A. Verify Gym Owner Assigned Plan
        final mRes = await SupabaseService.client
            .from('members')
            .select('assigned_workout_id')
            .eq('id', _memberId)
            .maybeSingle();

        final cloudPlanId = mRes?['assigned_workout_id']?.toString() ?? '';

        if (cloudPlanId.isEmpty) {
          _workoutPlanId = '';
          _workoutPlanTitle = '';
          _hasOwnerPlan = false;
          _rawOwnerSchedule = {};
          await prefs.remove('member_cached_workout_id');
          await prefs.remove('member_cached_workout_title');
          await prefs.remove('member_cached_workout_schedule_$_memberId');
          await prefs.remove('member_cached_workout_schedule');
          await prefs.remove('member_cached_schedule_json');

          // Reset owner schedule map
          for (final d in _defaultDays) {
            final dayNum = d['day'] as int;
            _ownerWeeklySchedule[dayNum] = {
              'day_of_week': dayNum,
              'muscle_group': '',
              'is_rest_day': d['is_rest'] as bool,
              'notes': '',
              'exercises': <Map<String, dynamic>>[],
            };
          }

          // If gym has no plan, default to custom mode
          if (_activePlanMode == 'gym' && storedActive == null) {
            _activePlanMode = 'custom';
            _viewingMode = 'custom';
          }
        } else {
          _workoutPlanId = cloudPlanId;
          await prefs.setString('member_cached_workout_id', _workoutPlanId);

          final wData = await SupabaseService.client
              .from('workout_plans')
              .select('title, schedule')
              .eq('id', _workoutPlanId)
              .maybeSingle();

          if (wData != null) {
            _workoutPlanTitle = wData['title'] ?? _workoutPlanTitle;
            await prefs.setString(
                'member_cached_workout_title', _workoutPlanTitle);
            dynamic raw = wData['schedule'];
            if (raw is String && raw.isNotEmpty) {
              try {
                raw = jsonDecode(raw);
              } catch (_) {}
            }
            if (raw is Map) {
              await prefs.setString(
                  'member_cached_workout_schedule_$_memberId',
                  jsonEncode(raw));
              await prefs.setString(
                  'member_cached_workout_schedule', jsonEncode(raw));
              _seedOwnerSchedule(Map<String, dynamic>.from(raw));
            }
          } else {
            _workoutPlanId = '';
            _workoutPlanTitle = '';
            _hasOwnerPlan = false;
            _rawOwnerSchedule = {};
          }
        }

        // B. Fetch Member's Custom Plan from Supabase (member_weekly_schedule)
        final res = await SupabaseService.client
            .from('member_weekly_schedule')
            .select()
            .eq('member_id', _memberId);

        if (res.isNotEmpty) {
          bool foundAny = false;
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

              final m = (row['muscle_group']?.toString() ?? '').trim();
              if ((m.isNotEmpty && !m.toLowerCase().contains('rest')) ||
                  exList.isNotEmpty) {
                foundAny = true;
              }

              _customWeeklySchedule[day] = {
                'day_of_week': day,
                'muscle_group': m,
                'is_rest_day': row['is_rest_day'] ?? false,
                'notes': row['notes'] ?? '',
                'exercises': exList,
              };
            }
          }
          _hasCustomPlan = foundAny;
          await prefs.setString(_customCacheKey,
              jsonEncode(_customWeeklySchedule.values.toList()));
        }
      } catch (e) {
        debugPrint('Error syncing workout schedules: $e');
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// Sets the active routine mode ('gym' or 'custom') and syncs with ViewModel.
  Future<void> _setActivePlanMode(String mode) async {
    setState(() => _activePlanMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('member_active_plan_mode_$_memberId', mode);

    if (!mounted) return;
    try {
      final vm = Provider.of<MemberAppViewModel>(context, listen: false);
      await vm.setActivePlanMode(mode);
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == 'custom'
              ? 'Activated "My Custom Plan"! Dashboard will now track your custom routine.'
              : 'Activated "Official Gym Plan"! Dashboard will now track your gym routine.',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Saves changes to a custom routine day
  Future<void> _saveCustomDaySchedule(int day) async {
    final dayData = _customWeeklySchedule[day];
    if (dayData == null) return;

    setState(() => _isSaving = true);

    // Save to local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _customCacheKey, jsonEncode(_customWeeklySchedule.values.toList()));
      // Automatically switch to custom plan mode if not set
      if (_activePlanMode != 'custom' && !_hasOwnerPlan) {
        _activePlanMode = 'custom';
        await prefs.setString(
            'member_active_plan_mode_$_memberId', 'custom');
      }
      _hasCustomPlan = true;
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
        debugPrint('Error saving custom routine day to Supabase: $e');
      }
    }

    if (mounted) {
      try {
        final vm = Provider.of<MemberAppViewModel>(context, listen: false);
        await vm.reloadWorkoutSchedules();
      } catch (_) {}
      setState(() => _isSaving = false);
    }
  }

  /// Removes an exercise from a custom routine day
  void _removeExerciseFromCustom(int day, int index) async {
    final dayData = _customWeeklySchedule[day];
    if (dayData == null) return;
    final List list = List.from(dayData['exercises'] ?? []);
    if (index >= 0 && index < list.length) {
      final removed = list.removeAt(index);
      setState(() {
        dayData['exercises'] = list;
      });
      await _saveCustomDaySchedule(day);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Removed ${removed['name'] ?? 'exercise'} from ${_getDayName(day)}'),
            backgroundColor: AppTheme.textPrimary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Edit target sets and reps for an exercise in custom plan
  void _editExerciseSetsReps(int day, int index) {
    final dayData = _customWeeklySchedule[day];
    if (dayData == null) return;
    final List list = List.from(dayData['exercises'] ?? []);
    if (index < 0 || index >= list.length) return;

    final ex = Map<String, dynamic>.from(list[index] as Map);
    final setsCtrl = TextEditingController(text: (ex['target_sets'] ?? 3).toString());
    final repsCtrl = TextEditingController(text: (ex['target_reps'] ?? '8-12').toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Edit Sets & Reps',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ex['name']?.toString() ?? 'Exercise',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: setsCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Target Sets',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: repsCtrl,
              decoration: InputDecoration(
                labelText: 'Target Reps (e.g. 10-12, 15)',
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
              final newSets = int.tryParse(setsCtrl.text.trim()) ?? 3;
              final newReps = repsCtrl.text.trim().isNotEmpty ? repsCtrl.text.trim() : '8-12';
              setState(() {
                ex['target_sets'] = newSets;
                ex['target_reps'] = newReps;
                list[index] = ex;
                dayData['exercises'] = list;
              });
              Navigator.pop(ctx);
              _saveCustomDaySchedule(day);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Dialog to edit or choose muscle focus for a custom routine day
  void _editCustomMuscleGroup(int day) {
    final current = _customWeeklySchedule[day]?['muscle_group']?.toString() ?? '';
    final ctrl = TextEditingController(text: current);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Customize ${_getDayName(day)} Focus',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Select a target muscle or type a custom split for this day:',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _quickMuscleSuggestions.map((suggestion) {
                  final isSelected = ctrl.text.trim().toLowerCase() ==
                      suggestion.toLowerCase();
                  return InkWell(
                    onTap: () {
                      setModalState(() {
                        ctrl.text = suggestion;
                      });
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary
                            : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text(
                        suggestion,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF334155),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: 'Target Focus (e.g. Chest & Triceps)',
                  hintText: 'e.g. Chest & Triceps',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  suffixIcon: ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            setModalState(() {
                              ctrl.clear();
                            });
                          },
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () {
                    final newName = ctrl.text.trim();
                    if (newName.isNotEmpty) {
                      setState(() {
                        _customWeeklySchedule[day]?['muscle_group'] = newName;
                        if (newName.toLowerCase().contains('rest')) {
                          _customWeeklySchedule[day]?['is_rest_day'] = true;
                        } else {
                          _customWeeklySchedule[day]?['is_rest_day'] = false;
                        }
                      });
                      _saveCustomDaySchedule(day);
                    }
                    Navigator.pop(ctx);
                  },
                  child: Text(
                    'Save Target Focus',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Reset to Gym Owner Plan
  Future<void> _resetToOwnerPlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Reset to Gym Plan?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        content: Text(
          'This will restore your 7-day routine to the official schedule assigned by your gym.',
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.inter(
                    color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Reset',
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    if (_rawOwnerSchedule.isNotEmpty) {
      _seedOwnerSchedule(_rawOwnerSchedule);
    }
    await _setActivePlanMode('gym');
    setState(() => _isLoading = false);
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
    final bool isCustomView = _viewingMode == 'custom';

    // Current schedule map based on viewing mode
    final Map<int, Map<String, dynamic>> activeMap =
        isCustomView ? _customWeeklySchedule : _ownerWeeklySchedule;

    final currentDayData = activeMap[_selectedDay] ?? {};
    final String rawMuscle =
        (currentDayData['muscle_group']?.toString() ?? '').trim();

    final bool hasSplitConfigured =
        rawMuscle.isNotEmpty && rawMuscle != 'No Plan Assigned';

    final String displayMuscle = hasSplitConfigured
        ? rawMuscle
        : (isCustomView
            ? 'No Muscle Focus Set'
            : (_hasOwnerPlan ? 'Rest & Recovery' : 'No Plan Assigned'));

    final bool isRest = currentDayData['is_rest_day'] == true ||
        displayMuscle.toLowerCase().contains('rest');

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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Workout Routine',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _activePlanMode == 'custom'
                        ? const Color(0xFF8B5CF6)
                        : (_hasOwnerPlan ? const Color(0xFF10B981) : const Color(0xFF94A3B8)),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  _activePlanMode == 'custom'
                      ? 'Active: My Custom Plan'
                      : (_hasOwnerPlan ? 'Active: Gym Plan' : 'No Active Plan'),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _activePlanMode == 'custom'
                        ? const Color(0xFF7C3AED)
                        : (_hasOwnerPlan ? const Color(0xFF059669) : const Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          ],
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
          if (!isCustomView && _hasOwnerPlan)
            IconButton(
              icon: const Icon(Icons.restore_rounded, color: AppTheme.primary),
              tooltip: 'Reset to Official Gym Plan',
              onPressed: _resetToOwnerPlan,
            ),
          IconButton(
            icon: const Icon(Icons.fitness_center_rounded, color: AppTheme.primary),
            tooltip: 'Browse All Exercises',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MemberExerciseLibraryScreen(
                    initialMuscleGroup: hasSplitConfigured ? displayMuscle : null,
                    memberId: widget.memberId,
                    gymId: widget.gymId,
                  ),
                ),
              );
              _loadSchedules();
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
                // ── PLAN SWITCHER TABS (Gym Plan vs My Custom Plan) ──
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        // TAB 1: Official Gym Routine
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (_viewingMode != 'gym') {
                                setState(() => _viewingMode = 'gym');
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !isCustomView
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: !isCustomView
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.business_rounded,
                                    size: 16,
                                    color: !isCustomView
                                        ? AppTheme.primary
                                        : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Gym Plan',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: !isCustomView
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: !isCustomView
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                  if (_activePlanMode == 'gym' && _hasOwnerPlan) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'ACTIVE',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF15803D),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),

                        // TAB 2: Member's Custom Plan
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (_viewingMode != 'custom') {
                                setState(() => _viewingMode = 'custom');
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isCustomView
                                    ? Colors.white
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: isCustomView
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.auto_awesome_rounded,
                                    size: 16,
                                    color: isCustomView
                                        ? const Color(0xFF7C3AED)
                                        : const Color(0xFF64748B),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'My Custom Plan',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: isCustomView
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: isCustomView
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                  if (_activePlanMode == 'custom') ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEDE9FE),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'ACTIVE',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF7C3AED),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── SWITCH TO THIS PLAN BANNER (When viewing inactive plan) ──
                if (_viewingMode != _activePlanMode &&
                    (!isCustomView ? _hasOwnerPlan : true))
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: const Color(0xFFF5F3FF),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded,
                            size: 18, color: Color(0xFF7C3AED)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isCustomView
                                ? 'Viewing Custom Plan · Dashboard uses Gym Plan'
                                : 'Viewing Gym Plan · Dashboard uses Custom Plan',
                            style: GoogleFonts.inter(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF5B21B6),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _setActivePlanMode(_viewingMode),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Use This Plan',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── 7-Day Horizontal Selector ──
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
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
                        final dayPlan = activeMap[dayNum];
                        final exCount =
                            (dayPlan?['exercises'] as List?)?.length ?? 0;
                        final dayMuscle =
                            (dayPlan?['muscle_group']?.toString() ?? '').trim();
                        final isDayRest = dayPlan?['is_rest_day'] == true ||
                            dayMuscle.toLowerCase().contains('rest');
                        final bool hasSplit = dayMuscle.isNotEmpty &&
                            dayMuscle != 'No Plan Assigned';

                        return GestureDetector(
                          onTap: () => setState(() => _selectedDay = dayNum),
                          child: Container(
                            width: 58,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? LinearGradient(
                                      colors: isCustomView
                                          ? [
                                              const Color(0xFF8B5CF6),
                                              const Color(0xFF7C3AED)
                                            ]
                                          : [
                                              const Color(0xFF6366F1),
                                              const Color(0xFF4F46E5)
                                            ],
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
                                        color: const Color(0xFF7C3AED)
                                            .withValues(alpha: 0.3),
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
                                  isToday
                                      ? 'TODAY'
                                      : (isCustomView
                                          ? (exCount > 0
                                              ? '$exCount'
                                              : (hasSplit
                                                  ? (isDayRest ? 'Rest' : '✓')
                                                  : '-'))
                                          : (_hasOwnerPlan
                                              ? (exCount > 0
                                                  ? '$exCount'
                                                  : (hasSplit ? '✓' : 'Rest'))
                                              : '-')),
                                  style: GoogleFonts.inter(
                                    fontSize: isToday ? 10 : 13,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected
                                        ? Colors.white
                                        : (isToday
                                            ? AppTheme.primary
                                            : const Color(0xFF0F172A)),
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

                // ── CONTENT AREA ──
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ════════════════════════════════════════════════
                        // 1. OFFICIAL GYM PLAN VIEW
                        // ════════════════════════════════════════════════
                        if (!isCustomView) ...[
                          if (!_hasOwnerPlan) ...[
                            // Unassigned Gym Plan View
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 36),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.08),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.business_center_rounded,
                                      size: 30,
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No Gym Plan Assigned',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Your gym owner has not assigned a weekly workout routine to your account yet.\n\nGood news: You can build and follow your own 7-day Custom Plan anytime!',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: const Color(0xFF64748B),
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.auto_awesome_rounded,
                                        size: 16),
                                    label: const Text(
                                        'Open My Custom Plan'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF7C3AED),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 24, vertical: 13),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () {
                                      setState(() => _viewingMode = 'custom');
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // Assigned Gym Plan Focus Card
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isRest
                                      ? [
                                          const Color(0xFF0F172A),
                                          const Color(0xFF1E293B)
                                        ]
                                      : [
                                          const Color(0xFF4338CA),
                                          const Color(0xFF6366F1)
                                        ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: (isRest
                                            ? const Color(0xFF0F172A)
                                            : const Color(0xFF4338CA))
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
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(10),
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
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.white
                                              .withValues(alpha: 0.2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          'Gym Routine',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    isRest
                                        ? 'Rest & Recovery Day'
                                        : displayMuscle,
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
                                        ? 'Scheduled by gym as rest day.'
                                        : '${exercises.length} planned exercises for this session',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color:
                                          Colors.white.withValues(alpha: 0.85),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ]
                        // ════════════════════════════════════════════════
                        // 2. MY CUSTOM PLAN VIEW (Full Member Control)
                        // ════════════════════════════════════════════════
                        else ...[
                          // Custom Focus Day Card
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isRest
                                    ? [
                                        const Color(0xFF1E1B4B),
                                        const Color(0xFF312E81)
                                      ]
                                    : [
                                        const Color(0xFF7C3AED),
                                        const Color(0xFF6D28D9)
                                      ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF7C3AED)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.white
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(10),
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
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.edit_rounded,
                                          size: 14),
                                      label: const Text('Edit Focus'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor:
                                            const Color(0xFF7C3AED),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      onPressed: () =>
                                          _editCustomMuscleGroup(_selectedDay),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  isRest
                                      ? 'Rest & Recovery Day'
                                      : (hasSplitConfigured
                                          ? displayMuscle
                                          : 'Tap "Edit Focus" to set routine'),
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
                                      ? 'Rest is when muscles rebuild and grow stronger.'
                                      : '${exercises.length} planned exercises for this session',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color:
                                        Colors.white.withValues(alpha: 0.85),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Divider(
                                    color: Colors.white24, height: 1),
                                const SizedBox(height: 10),
                                // Rest Day Toggle
                                Row(
                                  children: [
                                    Text(
                                      'Mark as Rest Day',
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
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
                                          if (val) {
                                            currentDayData['muscle_group'] =
                                                'Rest Day';
                                          }
                                        });
                                        _saveCustomDaySchedule(_selectedDay);
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // ── PLANNED EXERCISES SECTION ──
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
                                    builder: (_) =>
                                        MemberExerciseLibraryScreen(
                                      initialMuscleGroup: hasSplitConfigured
                                          ? displayMuscle
                                          : null,
                                      memberId: widget.memberId,
                                      gymId: widget.gymId,
                                    ),
                                  ),
                                );
                                _loadSchedules();
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
                                horizontal: 24, vertical: 30),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  width: 54,
                                  height: 54,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.fitness_center_rounded,
                                    size: 26,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  isRest
                                      ? 'Rest Day Scheduled'
                                      : (hasSplitConfigured
                                          ? 'Target: $displayMuscle'
                                          : 'No Exercises Added Yet'),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isRest
                                      ? 'Take time to recover and hydrate.'
                                      : 'Add workouts for ${_getDayName(_selectedDay)} to track your sets and reps.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFF64748B),
                                    height: 1.4,
                                  ),
                                ),
                                if (!isRest) ...[
                                  const SizedBox(height: 18),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.add_rounded,
                                        size: 16),
                                    label: const Text('Add Exercises from Library'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 20, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              MemberExerciseLibraryScreen(
                                            initialMuscleGroup:
                                                hasSplitConfigured
                                                    ? displayMuscle
                                                    : null,
                                            memberId: widget.memberId,
                                            gymId: widget.gymId,
                                          ),
                                        ),
                                      );
                                      _loadSchedules();
                                    },
                                  ),
                                ],
                              ],
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: exercises.length,
                            itemBuilder: (context, idx) {
                              final ex = Map<String, dynamic>.from(
                                  exercises[idx] as Map);
                              final name =
                                  ex['name']?.toString() ?? 'Exercise';
                              final target = ex['target']?.toString() ??
                                  ex['muscle'] ??
                                  displayMuscle;
                              final eq = ex['equipment']?.toString() ??
                                  'Bodyweight';
                              final sets = ex['target_sets'] ?? 3;
                              final reps = ex['target_reps'] ?? '8-12';
                              final img = ex['img']?.toString() ?? '';
                              final imgUrl =
                                  img.isNotEmpty ? '$_imgBase$img' : '';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.02),
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
                                                errorBuilder: (context, error, stackTrace) =>
                                                    Center(
                                                  child: Icon(
                                                    Icons.fitness_center_rounded,
                                                    color: AppTheme.primary
                                                        .withValues(alpha: 0.4),
                                                    size: 24,
                                                  ),
                                                ),
                                              )
                                            : Center(
                                                child: Icon(
                                                  Icons.fitness_center_rounded,
                                                  color: AppTheme.primary
                                                      .withValues(alpha: 0.4),
                                                  size: 24,
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
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
                                          InkWell(
                                            onTap: isCustomView
                                                ? () => _editExerciseSetsReps(
                                                    _selectedDay, idx)
                                                : null,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primary
                                                    .withValues(alpha: 0.08),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    '$sets sets × $reps reps',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: AppTheme.primary,
                                                    ),
                                                  ),
                                                  if (isCustomView) ...[
                                                    const SizedBox(width: 4),
                                                    const Icon(
                                                      Icons.edit,
                                                      size: 11,
                                                      color: AppTheme.primary,
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Delete button (Custom mode)
                                    if (isCustomView)
                                      IconButton(
                                        icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Color(0xFFEF4444),
                                            size: 20),
                                        onPressed: () =>
                                            _removeExerciseFromCustom(
                                                _selectedDay, idx),
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
