import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────
// GymOS Exercise Library Screen
// Powered by openGym & ExerciseDB Dataset (1,324 exercises with animations)
// ─────────────────────────────────────────────────────────────

class MemberExerciseLibraryScreen extends StatefulWidget {
  const MemberExerciseLibraryScreen({super.key});

  @override
  State<MemberExerciseLibraryScreen> createState() =>
      _MemberExerciseLibraryScreenState();
}

class _MemberExerciseLibraryScreenState
    extends State<MemberExerciseLibraryScreen> {
  List<Map<String, dynamic>> _allExercises = [];
  List<Map<String, dynamic>> _filtered = [];
  String _searchQuery = '';
  String _selectedBodyPart = 'All';
  String _selectedEquipment = 'Any equipment';
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  static const String _imgBase =
      'https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@7455efae41b330c265e7cd4b78dfa848e7ce5ebd/images/';
  static const String _gifBase =
      'https://cdn.jsdelivr.net/gh/hasaneyldrm/exercises-dataset@7455efae41b330c265e7cd4b78dfa848e7ce5ebd/videos/';

  static const List<String> _bodyParts = [
    'All',
    'Chest',
    'Back',
    'Upper Legs',
    'Lower Legs',
    'Upper Arms',
    'Lower Arms',
    'Shoulders',
    'Waist',
    'Cardio',
    'Neck',
  ];

  static const List<String> _equipments = [
    'Any equipment',
    'Body Weight',
    'Dumbbell',
    'Barbell',
    'Cable',
    'Leverage Machine',
    'Band',
    'Kettlebell',
    'Medicine Ball',
    'Stability Ball',
    'Ez Barbell',
    'Smith Machine',
    'Rope',
  ];

  @override
  void initState() {
    super.initState();
    _loadExercises();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExercises() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      // 1. Load full 1,324 openGym exercise database from bundled asset
      final jsonStr =
          await rootBundle.loadString('assets/data/exercises.json');
      final List rawList = jsonDecode(jsonStr);
      final List<Map<String, dynamic>> exercises = rawList
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      // 2. Load any custom exercises created by user/gym
      final customStr = prefs.getString('gymos_custom_exercises');
      if (customStr != null) {
        try {
          final List customList = jsonDecode(customStr);
          for (final c in customList.reversed) {
            exercises.insert(0, Map<String, dynamic>.from(c as Map));
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _allExercises = exercises;
          _isLoading = false;
          _applyFilters();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    // 3. Background sync custom exercises from Supabase if online
    if (SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client
            .from('exercises')
            .select()
            .order('name');
        if (res is List && res.isNotEmpty && mounted) {
          bool updated = false;
          for (final row in res) {
            final rowName =
                (row['name'] as String? ?? '').trim().toLowerCase();
            if (rowName.isEmpty) continue;
            // Do not prepend if exercise already exists in openGym dataset
            final exists = _allExercises.any((e) =>
                (e['n'] as String? ?? '').trim().toLowerCase() == rowName);
            if (!exists) {
              _allExercises.add({
                'id': row['id'].toString(),
                'n': row['name'] ?? '',
                'bp': row['muscle_group'] ?? 'Chest',
                'eq': row['equipment'] ?? 'Dumbbell',
                'tg': row['muscle_group'] ?? '',
                'sm': row['secondary_muscles'] ?? [],
                'st': [row['description'] ?? '', row['tips'] ?? '']
                    .where((s) => (s as String).isNotEmpty)
                    .toList(),
                'img': '',
                'gif': '',
              });
              updated = true;
            }
          }
          if (updated && mounted) {
            setState(() => _applyFilters());
          }
        }
      } catch (_) {}
    }
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    final bp = _selectedBodyPart.toLowerCase();
    final eq = _selectedEquipment.toLowerCase();

    setState(() {
      _filtered = _allExercises.where((e) {
        // Body part filter
        if (bp != 'all') {
          final itemBp = (e['bp'] as String? ?? '').toLowerCase();
          final itemTg = (e['tg'] as String? ?? '').toLowerCase();
          if (itemBp != bp && !itemTg.contains(bp) && !bp.contains(itemBp)) {
            return false;
          }
        }

        // Equipment filter
        if (eq != 'any equipment') {
          final itemEq = (e['eq'] as String? ?? '').toLowerCase();
          if (!itemEq.contains(eq) && !eq.contains(itemEq)) {
            return false;
          }
        }

        // Search query
        if (q.isNotEmpty) {
          final name = (e['n'] as String? ?? '').toLowerCase();
          final target = (e['tg'] as String? ?? '').toLowerCase();
          final itemEq = (e['eq'] as String? ?? '').toLowerCase();
          final itemBp = (e['bp'] as String? ?? '').toLowerCase();
          return name.contains(q) ||
              target.contains(q) ||
              itemEq.contains(q) ||
              itemBp.contains(q);
        }

        return true;
      }).toList();
    });
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return '';
    return s.split(' ').map((word) {
      if (word.isEmpty) return '';
      return word[0].toUpperCase() + word.substring(1);
    }).join(' ');
  }

  void _openExerciseDetail(Map<String, dynamic> exercise) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OpenGymExerciseDetailSheet(
        exercise: exercise,
        imgBase: _imgBase,
        gifBase: _gifBase,
      ),
    );
  }

  void _openCreateCustomExercise() {
    final nameCtrl = TextEditingController();
    String bodyPart = 'Chest';
    String equipment = 'Dumbbell';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Create Your Own Exercise',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Add custom exercise to your personal library',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: nameCtrl,
                autofocus: true,
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Exercise Name',
                  hintText: 'e.g. Dumbbell Floor Press',
                  labelStyle: GoogleFonts.inter(color: AppTheme.primary),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: bodyPart,
                decoration: InputDecoration(
                  labelText: 'Body Part / Muscle',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _bodyParts
                    .where((bp) => bp != 'All')
                    .map((bp) => DropdownMenuItem(value: bp, child: Text(bp)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => bodyPart = val);
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: equipment,
                decoration: InputDecoration(
                  labelText: 'Equipment',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: _equipments
                    .where((eq) => eq != 'Any equipment')
                    .map((eq) => DropdownMenuItem(value: eq, child: Text(eq)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setModalState(() => equipment = val);
                },
              ),
              const SizedBox(height: 22),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final newEx = {
                    'id': 'custom_${DateTime.now().millisecondsSinceEpoch}',
                    'n': name,
                    'bp': bodyPart.toLowerCase(),
                    'eq': equipment.toLowerCase(),
                    'tg': bodyPart.toLowerCase(),
                    'sm': [],
                    'st': ['Perform with proper form and control.'],
                    'img': '',
                    'gif': '',
                  };

                  final prefs = await SharedPreferences.getInstance();
                  final customStr = prefs.getString('gymos_custom_exercises');
                  List customList = [];
                  if (customStr != null) {
                    try {
                      customList = jsonDecode(customStr);
                    } catch (_) {}
                  }
                  customList.add(newEx);
                  await prefs.setString(
                      'gymos_custom_exercises', jsonEncode(customList));

                  setState(() {
                    _allExercises.insert(0, newEx);
                    _applyFilters();
                  });

                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Custom exercise added! 💪'),
                        backgroundColor: AppTheme.primary,
                      ),
                    );
                  }
                },
                child: Text(
                  'Add Exercise',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          'Exercise Library',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_allExercises.length} with animations',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Search & Dual Filter Header Panel ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) {
                      _searchQuery = v;
                      _applyFilters();
                    },
                    style: GoogleFonts.inter(
                        fontSize: 14, color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Search 1300+ exercises, muscles, equipment...',
                      hintStyle: GoogleFonts.inter(
                          fontSize: 13.5, color: const Color(0xFF94A3B8)),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: Color(0xFF94A3B8), size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchCtrl.clear();
                                _searchQuery = '';
                                _applyFilters();
                              },
                              child: const Icon(Icons.close_rounded,
                                  color: Color(0xFF94A3B8), size: 18),
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),

                // 2. Row 1: Target / Body Part Chips
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Text(
                        'BODY PART',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      if (_selectedBodyPart != 'All') ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() => _selectedBodyPart = 'All');
                            _applyFilters();
                          },
                          child: Text(
                            'Reset',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _bodyParts.length,
                    itemBuilder: (context, i) {
                      final bp = _bodyParts[i];
                      final isSelected = _selectedBodyPart == bp;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedBodyPart = bp);
                          _applyFilters();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? const LinearGradient(
                                    colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                                  )
                                : null,
                            color: isSelected ? null : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.transparent
                                  : const Color(0xFFE2E8F0),
                              width: 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    )
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              bp,
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),

                // 3. Row 2: Equipment Chips
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Text(
                        'EQUIPMENT',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      if (_selectedEquipment != 'Any equipment') ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            setState(() => _selectedEquipment = 'Any equipment');
                            _applyFilters();
                          },
                          child: Text(
                            'Reset',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 38,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _equipments.length,
                    itemBuilder: (context, i) {
                      final eq = _equipments[i];
                      final isSelected = _selectedEquipment == eq;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedEquipment = eq);
                          _applyFilters();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: isSelected
                                ? const LinearGradient(
                                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                                  )
                                : null,
                            color: isSelected ? null : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.transparent
                                  : const Color(0xFFE2E8F0),
                              width: 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: Text(
                              eq,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                color: isSelected ? Colors.white : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── Exercise List ──
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _filtered.length + 1, // +1 for Custom Ex card
                    itemBuilder: (context, i) {
                      // Top Banner: Create Your Own Exercise (Screenshot 2)
                      if (i == 0) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: InkWell(
                            onTap: _openCreateCustomExercise,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF1E1B4B),
                                    const Color(0xFF312E81),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1E1B4B)
                                        .withValues(alpha: 0.18),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Center(
                                      child: Text('✨',
                                          style: TextStyle(fontSize: 20)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Create your own exercise',
                                          style: GoogleFonts.inter(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'name + body part, custom exercise',
                                          style: GoogleFonts.inter(
                                            fontSize: 11.5,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.add_rounded,
                                      color: Colors.white, size: 22),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      final ex = _filtered[i - 1];
                      final name = _capitalize(ex['n'] as String? ?? '');
                      final target =
                          _capitalize(ex['tg'] as String? ?? ex['bp'] ?? '');
                      final equipment =
                          _capitalize(ex['eq'] as String? ?? '');
                      final imgUrl = ex['img'] != null &&
                              (ex['img'] as String).isNotEmpty
                          ? '$_imgBase${ex['img']}'
                          : '';

                      return Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFE2E8F0), width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: () => _openExerciseDetail(ex),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // Left: Anatomical Exercise Illustration
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: 58,
                                      height: 58,
                                      color: const Color(0xFFF8FAFC),
                                      child: imgUrl.isNotEmpty
                                          ? Image.network(
                                              imgUrl,
                                              fit: BoxFit.contain,
                                              loadingBuilder: (context,
                                                  child, progress) {
                                                if (progress == null)
                                                  return child;
                                                return const Center(
                                                  child: SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: AppTheme.primary,
                                                    ),
                                                  ),
                                                );
                                              },
                                              errorBuilder:
                                                  (_, __, ___) => Center(
                                                child: Icon(
                                                  Icons.fitness_center_rounded,
                                                  color: AppTheme.primary.withValues(alpha: 0.5),
                                                  size: 24,
                                                ),
                                              ),
                                            )
                                          : Center(
                                              child: Icon(
                                                Icons.fitness_center_rounded,
                                                color: AppTheme.primary.withValues(alpha: 0.5),
                                                size: 24,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Center: Title + Target Muscle & Equipment
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: GoogleFonts.inter(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF0F172A),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$target · $equipment',
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFF64748B),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Right: + Plan Action Button
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.add_rounded,
                                            size: 15,
                                            color: AppTheme.primary),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Plan',
                                          style: GoogleFonts.inter(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppTheme.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Rich Exercise Detail Sheet with High-Res Animated GIF (Screenshot 3)
// ─────────────────────────────────────────────────────────────

class _OpenGymExerciseDetailSheet extends StatefulWidget {
  final Map<String, dynamic> exercise;
  final String imgBase;
  final String gifBase;

  const _OpenGymExerciseDetailSheet({
    required this.exercise,
    required this.imgBase,
    required this.gifBase,
  });

  @override
  State<_OpenGymExerciseDetailSheet> createState() =>
      _OpenGymExerciseDetailSheetState();
}

class _OpenGymExerciseDetailSheetState
    extends State<_OpenGymExerciseDetailSheet> {
  double _weightKg = 20.0;
  int _reps = 5;

  double get _estimated1RM {
    // Epley formula: 1RM = w * (1 + r / 30)
    if (_reps == 1) return _weightKg;
    return _weightKg * (1.0 + (_reps / 30.0));
  }

  static String _cap(String s) {
    if (s.isEmpty) return '';
    return s.split(' ').map((w) {
      if (w.isEmpty) return '';
      return w[0].toUpperCase() + w.substring(1);
    }).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.exercise;
    final name = _cap(ex['n'] as String? ?? '');
    final bp = _cap(ex['bp'] as String? ?? '');
    final tg = _cap(ex['tg'] as String? ?? '');
    final eq = _cap(ex['eq'] as String? ?? '');
    final sm = (ex['sm'] as List? ?? []).map((e) => _cap(e.toString())).toList();
    final st = (ex['st'] as List? ?? []).map((e) => e.toString()).toList();

    final gifUrl = ex['gif'] != null && (ex['gif'] as String).isNotEmpty
        ? '${widget.gifBase}${ex['gif']}'
        : '';
    final imgUrl = ex['img'] != null && (ex['img'] as String).isNotEmpty
        ? '${widget.imgBase}${ex['img']}'
        : '';

    return Container(
      margin: const EdgeInsets.only(top: 40),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Top handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Scrollable detail content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    name,
                    style: GoogleFonts.inter(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── High-Res Animated GIF Container (Screenshot 3) ──
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: double.infinity,
                      height: 280,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                          width: 1.5,
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: gifUrl.isNotEmpty
                                ? Image.network(
                                    gifUrl,
                                    fit: BoxFit.contain,
                                    loadingBuilder:
                                        (context, child, progress) {
                                      if (progress == null) return child;
                                      return Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const CircularProgressIndicator(
                                              color: AppTheme.primary,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Loading animation...',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: const Color(0xFF94A3B8),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    errorBuilder: (_, __, ___) {
                                      // Fallback to static illustration if gif errors
                                      if (imgUrl.isNotEmpty) {
                                        return Image.network(imgUrl,
                                            fit: BoxFit.contain);
                                      }
                                      return const Center(
                                        child: Text('🏋️',
                                            style: TextStyle(fontSize: 48)),
                                      );
                                    },
                                  )
                                : (imgUrl.isNotEmpty
                                    ? Image.network(imgUrl, fit: BoxFit.contain)
                                    : const Center(
                                        child: Text('🏋️',
                                            style: TextStyle(fontSize: 48)))),
                          ),

                          // Overlay badge: Animated demonstration
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.play_circle_fill_rounded,
                                      color: Colors.white, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Animated Guide',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Muscle & Equipment Tags (Screenshot 3) ──
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (bp.isNotEmpty)
                        _buildTag(bp, AppTheme.primary, Colors.white),
                      if (tg.isNotEmpty && tg != bp)
                        _buildTag('🎯 $tg', const Color(0xFFF1F5F9),
                            const Color(0xFF334155)),
                      if (eq.isNotEmpty)
                        _buildTag('🏋️ $eq', const Color(0xFFF1F5F9),
                            const Color(0xFF334155)),
                      ...sm.map((m) => _buildTag(
                          m, const Color(0xFFF8FAFC), const Color(0xFF64748B))),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Primary Action Button: + Add to my plan (Screenshot 3) ──
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: Text(
                      'Add to my plan',
                      style: GoogleFonts.inter(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Added $name to your workout routine! 💪',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                          ),
                          backgroundColor: AppTheme.primary,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // ── Estimated 1RM Calculator (Screenshot 3) ──
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estimated 1RM Calculator',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Steppers: Weight & Reps
                        Row(
                          children: [
                            // Weight (kg)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Weight (kg)',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove_rounded,
                                              size: 18),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(6),
                                          onPressed: () {
                                            if (_weightKg > 2.5) {
                                              setState(() => _weightKg -= 2.5);
                                            }
                                          },
                                        ),
                                        Text(
                                          _weightKg % 1 == 0
                                              ? _weightKg.toInt().toString()
                                              : _weightKg.toStringAsFixed(1),
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_rounded,
                                              size: 18),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(6),
                                          onPressed: () {
                                            setState(() => _weightKg += 2.5);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Reps
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Reps',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: const Color(0xFFCBD5E1)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove_rounded,
                                              size: 18),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(6),
                                          onPressed: () {
                                            if (_reps > 1) {
                                              setState(() => _reps -= 1);
                                            }
                                          },
                                        ),
                                        Text(
                                          '$_reps',
                                          style: GoogleFonts.inter(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF0F172A),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_rounded,
                                              size: 18),
                                          constraints: const BoxConstraints(),
                                          padding: const EdgeInsets.all(6),
                                          onPressed: () {
                                            setState(() => _reps += 1);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // Result
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Estimate',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF64748B),
                              ),
                            ),
                            Text(
                              '${_estimated1RM.toStringAsFixed(1)} kg',
                              style: GoogleFonts.inter(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Epley formula — a calculation from one set, not a tested max.',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Step-by-Step Instructions ("How to") (Screenshot 3) ──
                  if (st.isNotEmpty) ...[
                    Text(
                      'How to Perform',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...st.asMap().entries.map((entry) {
                      final idx = entry.key + 1;
                      final step = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '$idx',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                step,
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  color: const Color(0xFF334155),
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textCol,
        ),
      ),
    );
  }
}
