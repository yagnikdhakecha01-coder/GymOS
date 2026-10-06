import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/supabase_service.dart';
import '../widgets/rest_timer_widget.dart';

// ─────────────────────────────────────────────────────────────
// Guided Workout Screen
// Live workout session: exercise by exercise, set by set.
// Features: rest timer, PR detection, timed exercises, supersets.
// Offline-first: all sets saved locally before Supabase sync.
// ─────────────────────────────────────────────────────────────

class MemberGuidedWorkoutScreen extends StatefulWidget {
  final String memberId;
  final String gymId;
  final String muscleGroup;
  final List<Map<String, dynamic>> exercises; // pre-loaded exercises for today

  const MemberGuidedWorkoutScreen({
    super.key,
    required this.memberId,
    required this.gymId,
    required this.muscleGroup,
    required this.exercises,
  });

  @override
  State<MemberGuidedWorkoutScreen> createState() =>
      _MemberGuidedWorkoutScreenState();
}

class _MemberGuidedWorkoutScreenState
    extends State<MemberGuidedWorkoutScreen> with TickerProviderStateMixin {
  int _currentExerciseIndex = 0;
  bool _sessionComplete = false;
  bool _showRestTimer = false;
  int _restSeconds = 90;

  // Per-exercise set logs: [{reps, weight, duration, done, isPR}]
  final List<List<Map<String, dynamic>>> _setsLog = [];
  // Personal records for comparison (fetched from Supabase/cache)
  Map<String, double> _existingPRs = {};

  // Timed exercise state
  bool _isTimerRunning = false;
  int _timedSeconds = 0;

  late AnimationController _successController;
  late Animation<double> _successAnim;

  final GlobalKey<RestTimerWidgetState> _restTimerKey =
      GlobalKey<RestTimerWidgetState>();

  @override
  void initState() {
    super.initState();
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successAnim = CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    );
    // Initialize sets for each exercise (default 3 sets)
    for (final ex in widget.exercises) {
      final defaultSets = (ex['default_sets'] as int?) ?? 3;
      _setsLog.add(List.generate(
        defaultSets,
        (_) => {
          'reps': ex['is_timed'] == true ? null : 10,
          'weight': ex['is_bodyweight'] == true ? 0.0 : 20.0,
          'duration': ex['is_timed'] == true ? 30 : null,
          'done': false,
          'isPR': false,
        },
      ));
    }
    _loadExistingPRs();
  }

  Future<void> _loadExistingPRs() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('member_prs_${widget.memberId}');
    if (cached != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(cached);
        setState(() {
          _existingPRs = decoded
              .map((k, v) => MapEntry(k, (v as num).toDouble()));
        });
      } catch (_) {}
    }

    if (!SupabaseService.isInitialized || widget.memberId.isEmpty) return;
    try {
      final result = await SupabaseService.client
          .from('member_personal_records')
          .select('exercise_name, best_weight_kg')
          .eq('member_id', widget.memberId);

      final Map<String, double> prs = {};
      for (final row in (result as List)) {
        prs[row['exercise_name'] as String] =
            (row['best_weight_kg'] as num?)?.toDouble() ?? 0.0;
      }
      await prefs.setString(
          'member_prs_${widget.memberId}', jsonEncode(prs));
      if (mounted) setState(() => _existingPRs = prs);
    } catch (_) {}
  }

  Map<String, dynamic> get _currentExercise =>
      widget.exercises[_currentExerciseIndex];

  bool get _isCurrentTimed =>
      _currentExercise['is_timed'] as bool? ?? false;

  bool get _isCurrentBodyweight =>
      _currentExercise['is_bodyweight'] as bool? ?? false;

  List<Map<String, dynamic>> get _currentSets =>
      _setsLog[_currentExerciseIndex];

  int get _doneSetsCount =>
      _currentSets.where((s) => s['done'] == true).length;

  // Mark a set as done and detect PR
  void _markSetDone(int setIndex) {
    final set = _currentSets[setIndex];
    final weight = (set['weight'] as num?)?.toDouble() ?? 0.0;
    final exName = _currentExercise['name'] as String? ?? '';
    final existingPR = _existingPRs[exName] ?? 0.0;
    final isPR = weight > 0 && weight > existingPR;

    setState(() {
      set['done'] = true;
      set['isPR'] = isPR;
      if (isPR) _existingPRs[exName] = weight;
    });

    HapticFeedback.mediumImpact();

    if (isPR) {
      _showPRBanner(exName, weight);
    }

    // Show rest timer after marking done (except last set of last exercise)
    final isLastSet = setIndex == _currentSets.length - 1;
    final isLastExercise =
        _currentExerciseIndex == widget.exercises.length - 1;

    if (!(isLastSet && isLastExercise)) {
      setState(() {
        _showRestTimer = true;
        _restSeconds = _isCurrentTimed ? 60 : 90;
      });
    }
  }

  void _showPRBanner(String exerciseName, double weight) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF6C3AED),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        content: Row(
          children: [
            const Text('🏆', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'New PR! $exerciseName — ${weight}kg 🎉',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _nextExercise() {
    if (_currentExerciseIndex < widget.exercises.length - 1) {
      setState(() {
        _currentExerciseIndex++;
        _showRestTimer = false;
      });
    } else {
      _finishWorkout();
    }
  }

  void _addSet() {
    setState(() {
      _currentSets.add({
        'reps': _isCurrentTimed ? null : 10,
        'weight': _isCurrentBodyweight ? 0.0 : 20.0,
        'duration': _isCurrentTimed ? 30 : null,
        'done': false,
        'isPR': false,
      });
    });
  }

  Future<void> _finishWorkout() async {
    setState(() => _sessionComplete = true);
    _successController.forward();
    HapticFeedback.heavyImpact();

    // Save all sets to local storage first (offline-first)
    final prefs = await SharedPreferences.getInstance();
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final sessionKey = 'workout_session_${widget.memberId}_$todayStr';
    final sessionData = {
      'date': todayStr,
      'muscle_group': widget.muscleGroup,
      'exercises': List.generate(widget.exercises.length, (i) {
        return {
          'exercise': widget.exercises[i],
          'sets': _setsLog[i],
        };
      }),
    };
    await prefs.setString(sessionKey, jsonEncode(sessionData));

    // Sync to Supabase in background
    _syncWorkoutToSupabase(prefs, todayStr, sessionData);
  }

  Future<void> _syncWorkoutToSupabase(
    SharedPreferences prefs,
    String todayStr,
    Map<String, dynamic> sessionData,
  ) async {
    if (!SupabaseService.isInitialized ||
        widget.memberId.isEmpty ||
        widget.gymId.isEmpty) return;

    try {
      final rows = <Map<String, dynamic>>[];
      int setGlobalNum = 0;

      for (int ei = 0; ei < widget.exercises.length; ei++) {
        final ex = widget.exercises[ei];
        final exName = ex['name'] as String? ?? '';
        final exId = ex['id'] as String?;
        final muscleGroup = ex['muscle_group'] as String? ?? widget.muscleGroup;
        final sets = _setsLog[ei];

        for (int si = 0; si < sets.length; si++) {
          final set = sets[si];
          if (set['done'] != true) continue;
          setGlobalNum++;

          rows.add({
            'gym_id': widget.gymId,
            'member_id': widget.memberId,
            'session_date': todayStr,
            'exercise_id': exId,
            'exercise_name': exName,
            'muscle_group': muscleGroup,
            'set_number': si + 1,
            'reps': set['reps'],
            'weight_kg': set['weight'],
            'duration_secs': set['duration'],
            'is_pr': set['isPR'] ?? false,
          });
        }
      }

      if (rows.isNotEmpty) {
        await SupabaseService.client
            .from('member_workout_sets')
            .insert(rows);
      }

      // Also update member_workout_logs (existing table)
      try {
        await SupabaseService.client.from('member_workout_logs').upsert({
          'gym_id': widget.gymId,
          'member_id': widget.memberId,
          'date': todayStr,
          'muscle': widget.muscleGroup,
          'status': 'Completed',
        });
      } catch (_) {}
    } catch (e) {
      // Queue for retry
      final queue = prefs.getStringList('gymos_crud_queue') ?? [];
      queue.add(jsonEncode({
        'type': 'workout_session',
        'data': sessionData,
        'memberId': widget.memberId,
        'gymId': widget.gymId,
      }));
      await prefs.setStringList('gymos_crud_queue', queue);
    }
  }

  @override
  void dispose() {
    _successController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.exercises.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(
            'Workout',
            style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded,
                color: AppTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏋️', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text(
                'No exercises for today',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ask your trainer to assign a workout plan',
                style: GoogleFonts.inter(
                    fontSize: 14, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    if (_sessionComplete) {
      return _buildCompletionScreen();
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon:
              const Icon(Icons.close_rounded, color: AppTheme.textPrimary),
          onPressed: () => _confirmQuit(),
        ),
        title: Column(
          children: [
            Text(
              widget.muscleGroup,
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            Text(
              '${_currentExerciseIndex + 1} of ${widget.exercises.length} exercises',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _nextExercise,
              child: Text(
                _currentExerciseIndex < widget.exercises.length - 1
                    ? 'Skip'
                    : 'Finish',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value: (_currentExerciseIndex + 1) / widget.exercises.length,
            backgroundColor: AppTheme.primaryLight,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            minHeight: 3,
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Exercise header card
                  _buildExerciseHeader(),
                  const SizedBox(height: 16),

                  // Rest timer (shows after completing a set)
                  if (_showRestTimer) ...[
                    RestTimerWidget(
                      key: _restTimerKey,
                      seconds: _restSeconds,
                      onFinished: () =>
                          setState(() => _showRestTimer = false),
                      onSkip: () =>
                          setState(() => _showRestTimer = false),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Sets table
                  _buildSetsSection(),
                  const SizedBox(height: 12),

                  // Add set button
                  GestureDetector(
                    onTap: _addSet,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.4),
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_rounded,
                              color: AppTheme.primary, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Add Set',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Next exercise preview
                  if (_currentExerciseIndex <
                      widget.exercises.length - 1) ...[
                    Text(
                      'NEXT UP',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textMuted,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceGray,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Center(
                                child: Text('💪',
                                    style: TextStyle(fontSize: 18))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.exercises[_currentExerciseIndex + 1]
                                      ['name'] as String? ??
                                  '',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Done with this exercise button
                  if (_doneSetsCount > 0)
                    ElevatedButton(
                      onPressed: _nextExercise,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        minimumSize:
                            const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _currentExerciseIndex < widget.exercises.length - 1
                            ? 'Next Exercise →'
                            : 'Finish Workout 🎉',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExerciseHeader() {
    final ex = _currentExercise;
    final name = ex['name'] as String? ?? '';
    final muscle = ex['muscle_group'] as String? ?? '';
    final equipment = ex['equipment'] as String? ?? '';
    final isTimed = ex['is_timed'] as bool? ?? false;
    final existingPR = _existingPRs[name];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary,
            AppTheme.primaryDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  muscle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isTimed ? '⏱ Timed' : equipment,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          if (existingPR != null && existingPR > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('🏆',
                    style: TextStyle(fontSize: 14)),
                const SizedBox(width: 4),
                Text(
                  'PR: ${existingPR}kg',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSetsSection() {
    final isTimed = _isCurrentTimed;
    final isBodyweight = _isCurrentBodyweight;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  'SET',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              if (!isTimed && !isBodyweight) ...[
                Expanded(
                  child: Text(
                    'KG',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              Expanded(
                child: Text(
                  isTimed ? 'SECS' : 'REPS',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 44),
            ],
          ),
          const SizedBox(height: 8),

          ..._currentSets.asMap().entries.map((entry) {
            final i = entry.key;
            final set = entry.value;
            final isDone = set['done'] == true;
            final isPR = set['isPR'] == true;
            return _SetRow(
              setNumber: i + 1,
              set: set,
              isDone: isDone,
              isPR: isPR,
              isTimed: isTimed,
              isBodyweight: isBodyweight,
              onDone: () => _markSetDone(i),
              onRepsChanged: (v) =>
                  setState(() => set['reps'] = v),
              onWeightChanged: (v) =>
                  setState(() => set['weight'] = v),
              onDurationChanged: (v) =>
                  setState(() => set['duration'] = v),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCompletionScreen() {
    final totalSets = _setsLog.fold<int>(
      0,
      (sum, sets) =>
          sum + sets.where((s) => s['done'] == true).length,
    );
    final prsCount =
        _setsLog.fold<int>(0, (sum, sets) {
      return sum +
          sets.where((s) => s['done'] == true && s['isPR'] == true).length;
    });

    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _successAnim,
                child: const Text(
                  '🎉',
                  style: TextStyle(fontSize: 80),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Workout Complete!',
                style: GoogleFonts.inter(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.muscleGroup,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _summaryTile('💪', '$totalSets', 'Sets Done'),
                  _summaryTile(
                      '🏋️', '${widget.exercises.length}', 'Exercises'),
                  _summaryTile('🏆', '$prsCount', 'New PRs'),
                ],
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Back to Dashboard',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
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

  Widget _summaryTile(String emoji, String value, String label) {
    return Column(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 28)),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  void _confirmQuit() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Quit Workout?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Your progress so far will be saved.',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Continue',
                style: GoogleFonts.inter(color: AppTheme.primary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              if (_doneSetsCount > 0) _finishWorkout();
              Navigator.pop(context); // Pop workout screen
            },
            child: Text('Quit',
                style: GoogleFonts.inter(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Individual Set Row widget
// ─────────────────────────────────────────────────────────────
class _SetRow extends StatefulWidget {
  final int setNumber;
  final Map<String, dynamic> set;
  final bool isDone;
  final bool isPR;
  final bool isTimed;
  final bool isBodyweight;
  final VoidCallback onDone;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<double> onWeightChanged;
  final ValueChanged<int> onDurationChanged;

  const _SetRow({
    required this.setNumber,
    required this.set,
    required this.isDone,
    required this.isPR,
    required this.isTimed,
    required this.isBodyweight,
    required this.onDone,
    required this.onRepsChanged,
    required this.onWeightChanged,
    required this.onDurationChanged,
  });

  @override
  State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late TextEditingController _repsCtrl;
  late TextEditingController _weightCtrl;
  late TextEditingController _durationCtrl;

  @override
  void initState() {
    super.initState();
    _repsCtrl =
        TextEditingController(text: '${widget.set['reps'] ?? 10}');
    _weightCtrl =
        TextEditingController(text: '${widget.set['weight'] ?? 20.0}');
    _durationCtrl =
        TextEditingController(text: '${widget.set['duration'] ?? 30}');
  }

  @override
  void dispose() {
    _repsCtrl.dispose();
    _weightCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // Set number
          SizedBox(
            width: 36,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: widget.isDone
                    ? AppTheme.success
                    : AppTheme.surfaceGray,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${widget.setNumber}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: widget.isDone
                        ? Colors.white
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
            ),
          ),

          // Weight input (not for bodyweight or timed)
          if (!widget.isTimed && !widget.isBodyweight) ...[
            Expanded(
              child: _inputField(
                controller: _weightCtrl,
                suffix: 'kg',
                enabled: !widget.isDone,
                onChanged: (v) {
                  final d = double.tryParse(v);
                  if (d != null) widget.onWeightChanged(d);
                },
              ),
            ),
            const SizedBox(width: 8),
          ],

          // Reps or duration
          Expanded(
            child: _inputField(
              controller: widget.isTimed ? _durationCtrl : _repsCtrl,
              suffix: widget.isTimed ? 's' : 'reps',
              enabled: !widget.isDone,
              onChanged: (v) {
                final i = int.tryParse(v);
                if (i != null) {
                  if (widget.isTimed) {
                    widget.onDurationChanged(i);
                  } else {
                    widget.onRepsChanged(i);
                  }
                }
              },
            ),
          ),
          const SizedBox(width: 8),

          // Done button / PR badge
          GestureDetector(
            onTap: widget.isDone ? null : widget.onDone,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 36,
              decoration: BoxDecoration(
                color: widget.isDone
                    ? AppTheme.success
                    : AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: widget.isPR
                    ? const Text('🏆',
                        style: TextStyle(fontSize: 16))
                    : Icon(
                        widget.isDone
                            ? Icons.check_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String suffix,
    required bool enabled,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: enabled ? Colors.white : AppTheme.surfaceGray,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled ? AppTheme.border : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: enabled
                    ? AppTheme.textPrimary
                    : AppTheme.textMuted,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8),
                isDense: true,
              ),
              onChanged: onChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              suffix,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: AppTheme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
