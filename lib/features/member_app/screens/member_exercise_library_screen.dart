import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────
// Exercise Library Screen
// Searchable, filterable list of all exercises (global + gym-custom)
// Offline-first: caches exercise list in SharedPreferences
// ─────────────────────────────────────────────────────────────

class MemberExerciseLibraryScreen extends StatefulWidget {
  const MemberExerciseLibraryScreen({super.key});

  @override
  State<MemberExerciseLibraryScreen> createState() =>
      _MemberExerciseLibraryScreenState();
}

class _MemberExerciseLibraryScreenState
    extends State<MemberExerciseLibraryScreen> {
  List<Map<String, dynamic>> _exercises = [];
  List<Map<String, dynamic>> _filtered = [];
  String _searchQuery = '';
  String _selectedMuscle = 'All';
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  static const List<String> _muscles = [
    'All', 'Chest', 'Back', 'Legs', 'Shoulders', 'Arms', 'Core', 'Cardio',
  ];

  static const Map<String, Color> _muscleColors = {
    'Chest': Color(0xFFEF4444),
    'Back': Color(0xFF3B82F6),
    'Legs': Color(0xFF10B981),
    'Shoulders': Color(0xFFF59E0B),
    'Arms': Color(0xFF8B5CF6),
    'Core': Color(0xFFEC4899),
    'Cardio': Color(0xFF06B6D4),
  };

  @override
  void initState() {
    super.initState();
    _exercises = List<Map<String, dynamic>>.from(_defaultExercises);
    _applyFilters();
    _loadExercises();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExercises() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Load from cache for instant display
    final cached = prefs.getString('gymos_exercises_cache');
    if (cached != null) {
      try {
        final list = (jsonDecode(cached) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (list.isNotEmpty && mounted) {
          setState(() {
            _exercises = list;
            _applyFilters();
            _isLoading = false;
          });
        }
      } catch (_) {}
    } else {
      if (mounted) {
        setState(() {
          _exercises = List<Map<String, dynamic>>.from(_defaultExercises);
          _applyFilters();
          _isLoading = false;
        });
      }
    }

    // 2. Fetch from Supabase
    if (!SupabaseService.isInitialized) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final result = await SupabaseService.client
          .from('exercises')
          .select()
          .order('muscle_group')
          .order('name');

      if (result is List && result.isNotEmpty) {
        final exercises = result
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        await prefs.setString('gymos_exercises_cache', jsonEncode(exercises));

        if (mounted) {
          setState(() {
            _exercises = exercises;
            _applyFilters();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filtered = _exercises.where((ex) {
        final muscle = (ex['muscle_group'] as String? ?? '').trim();
        final matchMuscle = _selectedMuscle == 'All' ||
            muscle.toLowerCase() == _selectedMuscle.toLowerCase();
        final name = (ex['name'] as String? ?? '').toLowerCase();
        final equipment = (ex['equipment'] as String? ?? '').toLowerCase();
        final query = _searchQuery.trim().toLowerCase();
        final matchSearch = query.isEmpty ||
            name.contains(query) ||
            muscle.toLowerCase().contains(query) ||
            equipment.contains(query);
        return matchMuscle && matchSearch;
      }).toList();
    });
  }

  static const List<Map<String, dynamic>> _defaultExercises = [
    // ── Chest ──
    {
      'name': 'Barbell Bench Press',
      'muscle_group': 'Chest',
      'secondary_muscles': ['Triceps', 'Shoulders'],
      'equipment': 'Barbell',
      'category': 'Strength',
      'description': 'The standard barbell flat bench press builds upper body pressing strength and chest mass.',
      'tips': 'Plant feet firmly, retract shoulder blades, touch mid-chest with control.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Incline Barbell Press',
      'muscle_group': 'Chest',
      'secondary_muscles': ['Shoulders', 'Triceps'],
      'equipment': 'Barbell',
      'category': 'Strength',
      'description': 'Incline press on a 30-45 degree bench targeting clavicular upper chest fibers.',
      'tips': 'Keep wrists straight, touch upper chest, don\'t flare elbows too wide.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Incline Dumbbell Press',
      'muscle_group': 'Chest',
      'secondary_muscles': ['Shoulders', 'Triceps'],
      'equipment': 'Dumbbells',
      'category': 'Hypertrophy',
      'description': 'Pressing dumbbells on an incline allows independent arm work and deep stretch.',
      'tips': 'Lower with control to armpit level and press up in an arc.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Dumbbell Fly',
      'muscle_group': 'Chest',
      'secondary_muscles': ['Shoulders'],
      'equipment': 'Dumbbells',
      'category': 'Isolation',
      'description': 'Flat bench fly emphasizing full pectoral stretch and contraction.',
      'tips': 'Maintain slight bend in elbows throughout, imagine hugging a large tree.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Cable Crossover',
      'muscle_group': 'Chest',
      'secondary_muscles': ['Shoulders'],
      'equipment': 'Cable Machine',
      'category': 'Isolation',
      'description': 'Standing cable fly providing continuous tension across the chest.',
      'tips': 'Squeeze inner chest at crossover, control eccentric phase.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Push-Up',
      'muscle_group': 'Chest',
      'secondary_muscles': ['Triceps', 'Core'],
      'equipment': 'Bodyweight',
      'category': 'Hypertrophy',
      'description': 'Foundational bodyweight pushing exercise building chest and core stability.',
      'tips': 'Maintain rigid plank posture, lower until chest is an inch from floor.',
      'is_timed': false,
      'is_bodyweight': true,
    },
    {
      'name': 'Dips (Chest Focus)',
      'muscle_group': 'Chest',
      'secondary_muscles': ['Triceps', 'Shoulders'],
      'equipment': 'Bodyweight',
      'category': 'Hypertrophy',
      'description': 'Parallel bar dips with forward torso lean to activate lower pectorals.',
      'tips': 'Lean torso 30 degrees forward, don\'t shrug shoulders up.',
      'is_timed': false,
      'is_bodyweight': true,
    },
    // ── Back ──
    {
      'name': 'Deadlift',
      'muscle_group': 'Back',
      'secondary_muscles': ['Hamstrings', 'Glutes', 'Traps'],
      'equipment': 'Barbell',
      'category': 'Strength',
      'description': 'Conventional barbell deadlift building full posterior chain power and dense back musculature.',
      'tips': 'Keep bar close to shins, engage lats, drive hips forward to lockout.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Pull-Up',
      'muscle_group': 'Back',
      'secondary_muscles': ['Biceps', 'Forearms'],
      'equipment': 'Bodyweight',
      'category': 'Strength',
      'description': 'Overhand grip pull-up targeting latissimus dorsi width and upper back thickness.',
      'tips': 'Pull chest to bar, initiate movement by depressing scapulae.',
      'is_timed': false,
      'is_bodyweight': true,
    },
    {
      'name': 'Barbell Row',
      'muscle_group': 'Back',
      'secondary_muscles': ['Biceps', 'Rear Delts'],
      'equipment': 'Barbell',
      'category': 'Strength',
      'description': 'Bent-over barbell row pulling to lower ribcage for lat and rhomboid density.',
      'tips': 'Hinge hips at 45 degrees, keep spine neutral, pull with elbows.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Lat Pulldown',
      'muscle_group': 'Back',
      'secondary_muscles': ['Biceps'],
      'equipment': 'Cable Machine',
      'category': 'Hypertrophy',
      'description': 'Wide grip vertical pulling movement building V-taper lat width.',
      'tips': 'Pull bar down to upper chest, avoid leaning excessively backward.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Seated Cable Row',
      'muscle_group': 'Back',
      'secondary_muscles': ['Biceps', 'Traps'],
      'equipment': 'Cable Machine',
      'category': 'Hypertrophy',
      'description': 'Horizontal cable row targeting mid-back thickness, rhomboids, and lower lats.',
      'tips': 'Sit tall, pull handles to abdomen, squeeze shoulder blades together.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'T-Bar Row',
      'muscle_group': 'Back',
      'secondary_muscles': ['Biceps', 'Lower Back'],
      'equipment': 'Barbell',
      'category': 'Strength',
      'description': 'Heavy compound row supporting big upper back overload.',
      'tips': 'Brace core, maintain bent posture, pull handles tight to chest.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    // ── Legs ──
    {
      'name': 'Barbell Back Squat',
      'muscle_group': 'Legs',
      'secondary_muscles': ['Glutes', 'Hamstrings', 'Core'],
      'equipment': 'Barbell',
      'category': 'Strength',
      'description': 'The king of lower body exercises developing quadricep power, glutes, and overall leg size.',
      'tips': 'Descend until hip crease is below knee level, push knees outward over toes.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Front Squat',
      'muscle_group': 'Legs',
      'secondary_muscles': ['Glutes', 'Core'],
      'equipment': 'Barbell',
      'category': 'Strength',
      'description': 'Barbell resting across front deltoids placing primary focus on the quadriceps and core.',
      'tips': 'Keep elbows pointed straight forward and chest upright.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Leg Press',
      'muscle_group': 'Legs',
      'secondary_muscles': ['Glutes', 'Hamstrings'],
      'equipment': 'Machine',
      'category': 'Hypertrophy',
      'description': 'Incline sled leg press for high-volume quad and leg development without spinal loading.',
      'tips': 'Lower sled until knees reach 90 degrees, do not lock knees violently at top.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Romanian Deadlift',
      'muscle_group': 'Legs',
      'secondary_muscles': ['Glutes', 'Lower Back'],
      'equipment': 'Barbell',
      'category': 'Hypertrophy',
      'description': 'Hip hinge movement emphasizing hamstring elongation and glute hypertrophy.',
      'tips': 'Push hips backward while keeping shins vertical and back completely flat.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Bulgarian Split Squat',
      'muscle_group': 'Legs',
      'secondary_muscles': ['Glutes', 'Quads'],
      'equipment': 'Dumbbells',
      'category': 'Hypertrophy',
      'description': 'Elevated rear-foot unilateral squat targeting glute activation and quad mass.',
      'tips': 'Descend smoothly on front leg until back knee almost touches ground.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Leg Extension',
      'muscle_group': 'Legs',
      'secondary_muscles': [],
      'equipment': 'Machine',
      'category': 'Isolation',
      'description': 'Machine exercise isolating the quadriceps through knee extension.',
      'tips': 'Hold contraction for 1 second at top, lower slowly with continuous resistance.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Seated Leg Curl',
      'muscle_group': 'Legs',
      'secondary_muscles': ['Calves'],
      'equipment': 'Machine',
      'category': 'Isolation',
      'description': 'Machine exercise isolating hamstrings through knee flexion.',
      'tips': 'Keep thighs firmly secured under pad, curl heels under with control.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Standing Calf Raise',
      'muscle_group': 'Legs',
      'secondary_muscles': [],
      'equipment': 'Machine',
      'category': 'Isolation',
      'description': 'Straight-leg calf raises targeting gastrocnemius muscle mass.',
      'tips': 'Full deep stretch at bottom, rise high on toes and pause 1 second.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    // ── Shoulders ──
    {
      'name': 'Overhead Press',
      'muscle_group': 'Shoulders',
      'secondary_muscles': ['Triceps', 'Upper Chest', 'Core'],
      'equipment': 'Barbell',
      'category': 'Strength',
      'description': 'Standing strict military barbell press building powerful deltoids and shoulder stability.',
      'tips': 'Squeeze glutes and abs, press straight up and lock arms overhead.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Seated Dumbbell Shoulder Press',
      'muscle_group': 'Shoulders',
      'secondary_muscles': ['Triceps'],
      'equipment': 'Dumbbells',
      'category': 'Strength',
      'description': 'Vertical pressing with dumbbells providing natural shoulder range of motion.',
      'tips': 'Lower dumbbells to ear level, press up without clanking weights together.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Dumbbell Lateral Raise',
      'muscle_group': 'Shoulders',
      'secondary_muscles': ['Traps'],
      'equipment': 'Dumbbells',
      'category': 'Isolation',
      'description': 'Lateral raises building wide 3D lateral deltoids and shoulder width.',
      'tips': 'Lead with elbows, keep pinkies slightly elevated, avoid swinging body.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Face Pull',
      'muscle_group': 'Shoulders',
      'secondary_muscles': ['Upper Back', 'Rotator Cuff'],
      'equipment': 'Cable Machine',
      'category': 'Hypertrophy',
      'description': 'Rope cable pull toward forehead with external shoulder rotation for rear delts and rotator cuffs.',
      'tips': 'Pull rope apart at eye level, squeeze rear delts and hold peak 1 sec.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Front Dumbbell Raise',
      'muscle_group': 'Shoulders',
      'secondary_muscles': ['Upper Chest'],
      'equipment': 'Dumbbells',
      'category': 'Isolation',
      'description': 'Alternating or bilateral forward dumbbell raise targeting anterior deltoids.',
      'tips': 'Raise dumbbell smoothly to eye level, lower under tension.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    // ── Arms ──
    {
      'name': 'Barbell Bicep Curl',
      'muscle_group': 'Arms',
      'secondary_muscles': ['Forearms'],
      'equipment': 'Barbell',
      'category': 'Isolation',
      'description': 'Standard standing barbell curl for bicep mass and peak development.',
      'tips': 'Pin elbows to sides, curl barbell upward without rocking torso.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Dumbbell Hammer Curl',
      'muscle_group': 'Arms',
      'secondary_muscles': ['Brachialis', 'Forearms'],
      'equipment': 'Dumbbells',
      'category': 'Isolation',
      'description': 'Neutral grip curl developing brachialis muscle for arm thickness.',
      'tips': 'Keep palms facing each other throughout the curl.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Preacher Curl',
      'muscle_group': 'Arms',
      'secondary_muscles': ['Forearms'],
      'equipment': 'EZ Bar',
      'category': 'Isolation',
      'description': 'Curling on preacher bench pad preventing momentum and isolating bicep peak.',
      'tips': 'Don\'t bounce off bottom pad, control the negative extension.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Tricep Rope Pushdown',
      'muscle_group': 'Arms',
      'secondary_muscles': [],
      'equipment': 'Cable Machine',
      'category': 'Isolation',
      'description': 'Cable pushdown with rope attachment targeting lateral and medial tricep heads.',
      'tips': 'Lock upper arms stationary, spread rope outward at full extension.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Skull Crusher',
      'muscle_group': 'Arms',
      'secondary_muscles': [],
      'equipment': 'EZ Bar',
      'category': 'Isolation',
      'description': 'Lying tricep extension behind head isolating long tricep head.',
      'tips': 'Lower bar slowly toward forehead or hairline, press upward from elbows.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    {
      'name': 'Close-Grip Bench Press',
      'muscle_group': 'Arms',
      'secondary_muscles': ['Chest', 'Shoulders'],
      'equipment': 'Barbell',
      'category': 'Strength',
      'description': 'Compound pressing with hands shoulder-width apart overloading triceps.',
      'tips': 'Tuck elbows close to ribs, touch lower sternum.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    // ── Core ──
    {
      'name': 'Plank',
      'muscle_group': 'Core',
      'secondary_muscles': ['Shoulders', 'Glutes'],
      'equipment': 'Bodyweight',
      'category': 'Endurance',
      'description': 'Isometric core stability hold strengthening transverse abdominis and pelvic floor.',
      'tips': 'Maintain straight line from head to heels, squeeze glutes and brace abs.',
      'is_timed': true,
      'is_bodyweight': true,
    },
    {
      'name': 'Hanging Leg Raise',
      'muscle_group': 'Core',
      'secondary_muscles': ['Hip Flexors'],
      'equipment': 'Pull-up Bar',
      'category': 'Strength',
      'description': 'Hanging from pull-up bar and curling pelvis upward for lower abdominal definition.',
      'tips': 'Avoid swinging, curl pelvis upward at top of movement.',
      'is_timed': false,
      'is_bodyweight': true,
    },
    {
      'name': 'Ab Wheel Rollout',
      'muscle_group': 'Core',
      'secondary_muscles': ['Lats', 'Shoulders'],
      'equipment': 'Ab Wheel',
      'category': 'Strength',
      'description': 'Advanced anti-extension core builder rolling wheel out from knees.',
      'tips': 'Keep back slightly rounded into hollow posture, don\'t let lower back sag.',
      'is_timed': false,
      'is_bodyweight': true,
    },
    {
      'name': 'Cable Woodchopper',
      'muscle_group': 'Core',
      'secondary_muscles': ['Shoulders'],
      'equipment': 'Cable Machine',
      'category': 'Functional',
      'description': 'Rotational cable movement strengthening obliques and functional core power.',
      'tips': 'Pivot on back foot, rotate through torso while keeping arms extended.',
      'is_timed': false,
      'is_bodyweight': false,
    },
    // ── Cardio ──
    {
      'name': 'Treadmill Run',
      'muscle_group': 'Cardio',
      'secondary_muscles': ['Legs', 'Calves'],
      'equipment': 'Cardio Machine',
      'category': 'Endurance',
      'description': 'Aerobic running intervals or steady state conditioning for cardiovascular health.',
      'tips': 'Land midfoot with upright posture and relaxed shoulders.',
      'is_timed': true,
      'is_bodyweight': false,
    },
    {
      'name': 'Stationary Bike',
      'muscle_group': 'Cardio',
      'secondary_muscles': ['Quads', 'Calves'],
      'equipment': 'Cardio Machine',
      'category': 'Endurance',
      'description': 'Low impact cardiovascular cycling conditioning.',
      'tips': 'Adjust saddle height so knee has slight bend at lowest pedal position.',
      'is_timed': true,
      'is_bodyweight': false,
    },
    {
      'name': 'Jump Rope',
      'muscle_group': 'Cardio',
      'secondary_muscles': ['Calves', 'Shoulders'],
      'equipment': 'Jump Rope',
      'category': 'HIIT',
      'description': 'High-intensity interval skipping building rhythm, coordination, and footwork.',
      'tips': 'Stay light on the balls of your feet, rotate rope from wrists.',
      'is_timed': true,
      'is_bodyweight': true,
    },
    {
      'name': 'Battle Ropes',
      'muscle_group': 'Cardio',
      'secondary_muscles': ['Shoulders', 'Arms', 'Core'],
      'equipment': 'Ropes',
      'category': 'HIIT',
      'description': 'Alternating or double wave rope slams for anaerobic endurance.',
      'tips': 'Slight bend in knees, brace core, drive power from shoulders and hips.',
      'is_timed': true,
      'is_bodyweight': false,
    },
    {
      'name': 'Rowing Machine',
      'muscle_group': 'Cardio',
      'secondary_muscles': ['Back', 'Legs'],
      'equipment': 'Cardio Machine',
      'category': 'Endurance',
      'description': 'Total-body cardiovascular ergometer engaging 85% of body musculature.',
      'tips': 'Push with legs first, swing hips back, then pull handle to sternum.',
      'is_timed': true,
      'is_bodyweight': false,
    },
  ];

  void _openExerciseDetail(Map<String, dynamic> exercise) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ExerciseDetailSheet(exercise: exercise),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              size: 20, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Exercise Library',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_filtered.length} exercises',
                style: GoogleFonts.inter(
                  fontSize: 12,
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
          // ── Search bar ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) {
                _searchQuery = v;
                _applyFilters();
              },
              style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search exercises...',
                hintStyle: GoogleFonts.inter(
                    fontSize: 14, color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: AppTheme.textMuted, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          _searchQuery = '';
                          _applyFilters();
                        },
                        child: const Icon(Icons.close_rounded,
                            color: AppTheme.textMuted, size: 18),
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.surfaceGray,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),

          // ── Muscle filter chips ──
          Container(
            color: Colors.white,
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _muscles.length,
              itemBuilder: (context, i) {
                final muscle = _muscles[i];
                final isSelected = _selectedMuscle == muscle;
                final chipColor = muscle == 'All'
                    ? AppTheme.primary
                    : (_muscleColors[muscle] ?? AppTheme.primary);
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedMuscle = muscle);
                    _applyFilters();
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? chipColor : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? chipColor : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      muscle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // ── Exercise list ──
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🏋️',
                                style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text(
                              'No exercises found',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'Try a different filter',
                              style: GoogleFonts.inter(
                                  fontSize: 13, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        physics: const BouncingScrollPhysics(),
                        itemCount: _filtered.length,
                        itemBuilder: (context, i) {
                          final ex = _filtered[i];
                          return _ExerciseCard(
                            exercise: ex,
                            muscleColors: _muscleColors,
                            onTap: () => _openExerciseDetail(ex),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final Map<String, dynamic> exercise;
  final Map<String, Color> muscleColors;
  final VoidCallback onTap;

  const _ExerciseCard({
    required this.exercise,
    required this.muscleColors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final muscle = exercise['muscle_group'] as String? ?? 'Other';
    final color = muscleColors[muscle] ?? AppTheme.primary;
    final isBodyweight = exercise['is_bodyweight'] as bool? ?? false;
    final isTimed = exercise['is_timed'] as bool? ?? false;
    final equipment = exercise['equipment'] as String? ?? 'Bodyweight';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Row(
          children: [
            // Muscle color indicator
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  _muscleEmoji(muscle),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exercise['name'] as String? ?? '',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _tag(muscle, color),
                      const SizedBox(width: 6),
                      _tag(equipment, AppTheme.textMuted),
                      if (isTimed) ...[
                        const SizedBox(width: 6),
                        _tag('⏱ Timed', AppTheme.info),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppTheme.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _muscleEmoji(String muscle) {
    return {
      'Chest': '🫁',
      'Back': '🔙',
      'Legs': '🦵',
      'Shoulders': '💪',
      'Arms': '💪',
      'Core': '🎯',
      'Cardio': '❤️',
    }[muscle] ?? '🏋️';
  }
}

// ─────────────────────────────────────────────────────────────
// Exercise Detail Bottom Sheet
// ─────────────────────────────────────────────────────────────
class _ExerciseDetailSheet extends StatelessWidget {
  final Map<String, dynamic> exercise;

  const _ExerciseDetailSheet({required this.exercise});

  @override
  Widget build(BuildContext context) {
    final muscle = exercise['muscle_group'] as String? ?? '';
    final name = exercise['name'] as String? ?? '';
    final desc = exercise['description'] as String? ?? '';
    final tips = exercise['tips'] as String? ?? '';
    final equipment = exercise['equipment'] as String? ?? 'Bodyweight';
    final isTimed = exercise['is_timed'] as bool? ?? false;
    final isBodyweight = exercise['is_bodyweight'] as bool? ?? false;
    final secondary = (exercise['secondary_muscles'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    return Container(
      margin: const EdgeInsets.only(top: 60),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _chipTag(muscle, AppTheme.primary),
                                _chipTag(equipment, AppTheme.textSecondary),
                                if (isTimed)
                                  _chipTag('⏱ Timed', AppTheme.info),
                                if (isBodyweight)
                                  _chipTag('Bodyweight', AppTheme.success),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            isTimed ? '⏱️' : (isBodyweight ? '🤸' : '🏋️'),
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (secondary.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Secondary Muscles',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: secondary
                          .map((m) => _chipTag(m, AppTheme.textSecondary))
                          .toList(),
                    ),
                  ],

                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      'About',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      desc,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                        height: 1.6,
                      ),
                    ),
                  ],

                  if (tips.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('💡', style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tips,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: const Color(0xFF166534),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // ── How to do it (generic based on type) ──
                  _howToSection(isTimed, isBodyweight),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _howToSection(bool isTimed, bool isBodyweight) {
    final steps = isTimed
        ? [
            'Get into position',
            'Engage your core',
            'Hold for the target duration',
            'Breathe steadily throughout',
          ]
        : isBodyweight
            ? [
                'Set up proper stance / grip',
                'Lower with control (2-3 secs)',
                'Push / pull explosively',
                'Full range of motion',
              ]
            : [
                'Set up the weight on equipment',
                'Grip firmly, brace your core',
                'Perform the movement with full ROM',
                'Control the negative (eccentric) phase',
              ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How to Perform',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...steps.asMap().entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${e.key + 1}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.value,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _chipTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
