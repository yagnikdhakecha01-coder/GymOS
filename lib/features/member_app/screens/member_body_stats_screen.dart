import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme.dart';
import '../../../core/services/supabase_service.dart';

// ─────────────────────────────────────────────────────────────
// Member Body Stats Screen
// Track weight, body measurements, with line chart visualization.
// Goal line + progress indicators. Offline-first with Supabase sync.
// ─────────────────────────────────────────────────────────────

class MemberBodyStatsScreen extends StatefulWidget {
  final String memberId;
  final String gymId;

  const MemberBodyStatsScreen({
    super.key,
    required this.memberId,
    required this.gymId,
  });

  @override
  State<MemberBodyStatsScreen> createState() => _MemberBodyStatsScreenState();
}

class _MemberBodyStatsScreenState extends State<MemberBodyStatsScreen>
    with TickerProviderStateMixin {
  List<Map<String, dynamic>> _logs = [];
  Map<String, dynamic>? _latestLog;
  bool _isLoading = true;
  bool _isSaving = false;

  // ── Goal State ──
  double _goalWeight = 0.0;
  String _goalType = 'Weight Loss';
  double? _goalBodyFat;
  int _weeklyGymDays = 5;
  bool _hasSetGoal = false;

  // ── Daily Log Gating ──
  bool _isEditingTodayLog = false;

  late TabController _tabController;

  // Form controllers
  final _weightCtrl = TextEditingController();
  final _bodyFatCtrl = TextEditingController();
  final _chestCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _armsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _showMeasurements = false;
  bool _showNotes = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBodyLogs();
    _loadGoal();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _weightCtrl.dispose();
    _bodyFatCtrl.dispose();
    _chestCtrl.dispose();
    _waistCtrl.dispose();
    _armsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedWeight = prefs.getDouble('member_goal_weight_${widget.memberId}');
    final cachedType = prefs.getString('member_goal_type_${widget.memberId}');
    final cachedHasGoal = prefs.getBool('member_has_set_goal_${widget.memberId}') ?? false;

    if (cachedHasGoal && cachedWeight != null && cachedWeight > 0) {
      if (mounted) {
        setState(() {
          _goalWeight = cachedWeight;
          _goalType = cachedType ?? 'Weight Loss';
          _hasSetGoal = true;
        });
      }
    }

    if (SupabaseService.isInitialized && widget.memberId.isNotEmpty) {
      try {
        final res = await SupabaseService.client
            .from('member_fitness_goals')
            .select()
            .eq('member_id', widget.memberId)
            .maybeSingle();

        if (res != null) {
          final gWeight = (res['goal_weight_kg'] as num?)?.toDouble() ?? 0.0;
          final gType = res['goal_type']?.toString() ?? 'Weight Loss';
          final gBodyFat = (res['goal_body_fat'] as num?)?.toDouble();
          final gDays = (res['weekly_gym_days'] as num?)?.toInt() ?? 5;

          await prefs.setDouble('member_goal_weight_${widget.memberId}', gWeight);
          await prefs.setString('member_goal_type_${widget.memberId}', gType);
          await prefs.setBool('member_has_set_goal_${widget.memberId}', gWeight > 0);

          if (mounted) {
            setState(() {
              _goalWeight = gWeight;
              _goalType = gType;
              _goalBodyFat = gBodyFat;
              _weeklyGymDays = gDays;
              _hasSetGoal = gWeight > 0;
            });
          }
        }
      } catch (_) {}
    }

    // First time opening Body Stats: if no goal is set, prompt goal dialog immediately
    if (mounted && (!_hasSetGoal || _goalWeight <= 0)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (!_hasSetGoal || _goalWeight <= 0)) {
          _showSetGoalDialog(isFirstTime: true);
        }
      });
    }
  }

  Future<void> _loadBodyLogs() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Load from cache
    final cached = prefs.getString('member_body_logs_${widget.memberId}');
    if (cached != null) {
      try {
        final list = (jsonDecode(cached) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        setState(() {
          _logs = list;
          if (list.isNotEmpty) {
            _latestLog = list.first;
            _prefillControllers(_latestLog!);
          }
          _isLoading = false;
        });
      } catch (_) {}
    }

    if (!SupabaseService.isInitialized || widget.memberId.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // 2. Fetch directly from member_body_logs table
      final result = await SupabaseService.client
          .from('member_body_logs')
          .select()
          .eq('member_id', widget.memberId)
          .order('logged_date', ascending: false)
          .limit(180);

      List<Map<String, dynamic>> logs = [];
      if (result.isNotEmpty) {
        logs = result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      // 3. If no body logs yet, check if Owner or Staff entered weight in members profile
      if (logs.isEmpty) {
        try {
          final memberDoc = await SupabaseService.client
              .from('members')
              .select('extra_fields, gym_id')
              .eq('id', widget.memberId)
              .maybeSingle();

          if (memberDoc != null) {
            final extra = (memberDoc['extra_fields'] as Map<String, dynamic>?) ?? {};
            final measurements = (extra['measurements'] as Map<String, dynamic>?) ?? {};
            final rawWeight = extra['weight'] ?? measurements['weight'];

            if (rawWeight != null) {
              final double? parsedWeight = (rawWeight is num)
                  ? rawWeight.toDouble()
                  : double.tryParse(rawWeight.toString());
              if (parsedWeight != null) {
                final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                final initialLog = {
                  'logged_date': todayStr,
                  'weight_kg': parsedWeight,
                  'body_fat_pct': extra['body_fat'] != null ? double.tryParse(extra['body_fat'].toString()) : null,
                  'chest_cm': measurements['chest'] != null ? (double.tryParse(measurements['chest'].toString()) ?? 0) : null,
                  'waist_cm': measurements['waist'] != null ? (double.tryParse(measurements['waist'].toString()) ?? 0) : null,
                  'arms_cm': measurements['biceps'] != null ? (double.tryParse(measurements['biceps'].toString()) ?? 0) : null,
                  'notes': 'Recorded by Gym Trainer',
                };
                logs.add(initialLog);
              }
            }
          }
        } catch (_) {}
      }

      await prefs.setString(
          'member_body_logs_${widget.memberId}', jsonEncode(logs));

      if (mounted) {
        setState(() {
          _logs = logs;
          if (logs.isNotEmpty) {
            _latestLog = logs.first;
            _prefillControllers(_latestLog!);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _prefillControllers(Map<String, dynamic> log) {
    if (log['weight_kg'] != null) {
      _weightCtrl.text = log['weight_kg'].toString();
    }
    if (log['body_fat_pct'] != null) {
      _bodyFatCtrl.text = log['body_fat_pct'].toString();
    }
    if (log['chest_cm'] != null) {
      _chestCtrl.text = log['chest_cm'].toString();
    }
    if (log['waist_cm'] != null) {
      _waistCtrl.text = log['waist_cm'].toString();
    }
    if (log['arms_cm'] != null) {
      _armsCtrl.text = log['arms_cm'].toString();
    }
    if (log['notes'] != null) {
      _notesCtrl.text = log['notes'].toString();
    }
    _showMeasurements = (log['chest_cm'] != null || log['waist_cm'] != null || log['arms_cm'] != null);
    _showNotes = (log['notes'] != null && log['notes'].toString().trim().isNotEmpty);
  }

  Map<String, dynamic>? get _todayLog {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    for (final l in _logs) {
      if ((l['logged_date'] as String? ?? '') == todayStr) {
        return l;
      }
    }
    return null;
  }

  Future<void> _saveLog() async {
    if (!_hasSetGoal || _goalWeight <= 0) {
      _showSetGoalDialog(isFirstTime: true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please set your fitness goal first before logging.',
              style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: AppTheme.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    final weightStr = _weightCtrl.text.trim();
    if (weightStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enter your weight to log.',
              style: GoogleFonts.inter(fontSize: 13)),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final prefs = await SharedPreferences.getInstance();
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final logEntry = {
      'logged_date': todayStr,
      'weight_kg': double.tryParse(weightStr),
      'body_fat_pct': double.tryParse(_bodyFatCtrl.text),
      'chest_cm': double.tryParse(_chestCtrl.text),
      'waist_cm': double.tryParse(_waistCtrl.text),
      'arms_cm': double.tryParse(_armsCtrl.text),
      'notes': _notesCtrl.text.trim(),
    };

    // Offline-first: update local list (1 log per day enforced)
    _logs.removeWhere(
        (l) => (l['logged_date'] as String? ?? '') == todayStr);
    _logs.insert(0, logEntry);
    _latestLog = logEntry;
    _isEditingTodayLog = false;

    await prefs.setString(
        'member_body_logs_${widget.memberId}', jsonEncode(_logs));

    // Resolve gymId if empty
    String effectiveGymId = widget.gymId;
    if (effectiveGymId.isEmpty) {
      final gymInfoStr = prefs.getString('gymos_gym_info');
      if (gymInfoStr != null) {
        try {
          final gi = jsonDecode(gymInfoStr) as Map<String, dynamic>;
          effectiveGymId = gi['id'] ?? '';
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
      _tabController.animateTo(0); // Switch to chart view
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Today\'s stats saved! 💪',
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }

    // Background sync to Supabase
    if (SupabaseService.isInitialized && widget.memberId.isNotEmpty) {
      try {
        if (effectiveGymId.isEmpty) {
          final mDoc = await SupabaseService.client
              .from('members')
              .select('gym_id')
              .eq('id', widget.memberId)
              .maybeSingle();
          effectiveGymId = mDoc?['gym_id']?.toString() ?? '';
        }

        if (effectiveGymId.isNotEmpty) {
          await SupabaseService.client.from('member_body_logs').upsert({
            'gym_id': effectiveGymId,
            'member_id': widget.memberId,
            'logged_date': todayStr,
            'weight_kg': logEntry['weight_kg'],
            'body_fat_pct': logEntry['body_fat_pct'],
            'chest_cm': logEntry['chest_cm'],
            'waist_cm': logEntry['waist_cm'],
            'arms_cm': logEntry['arms_cm'],
            'notes': logEntry['notes'],
          }, onConflict: 'member_id, logged_date');
        }

        // Also update members.extra_fields so owner/trainer sees latest weight in staff portal
        final mDoc = await SupabaseService.client
            .from('members')
            .select('extra_fields')
            .eq('id', widget.memberId)
            .maybeSingle();
        final currentExtra = Map<String, dynamic>.from((mDoc?['extra_fields'] as Map?) ?? {});
        currentExtra['weight'] = logEntry['weight_kg'];
        final currentMeasurements = Map<String, dynamic>.from((currentExtra['measurements'] as Map?) ?? {});
        if (logEntry['chest_cm'] != null) currentMeasurements['chest'] = logEntry['chest_cm'];
        if (logEntry['waist_cm'] != null) currentMeasurements['waist'] = logEntry['waist_cm'];
        if (logEntry['arms_cm'] != null) currentMeasurements['biceps'] = logEntry['arms_cm'];
        currentExtra['measurements'] = currentMeasurements;

        await SupabaseService.client
            .from('members')
            .update({'extra_fields': currentExtra})
            .eq('id', widget.memberId);
      } catch (e) {
        // Queue for later offline sync
        final queue = prefs.getStringList('gymos_crud_queue') ?? [];
        queue.add(jsonEncode({
          'type': 'body_log',
          'data': {
            ...logEntry,
            'gym_id': effectiveGymId,
            'member_id': widget.memberId,
          },
        }));
        await prefs.setStringList('gymos_crud_queue', queue);
      }
    }
  }

  // Compute weight progress (first vs latest)
  Map<String, dynamic> get _weightProgress {
    if (_logs.length < 2) {
      return {'change': 0.0, 'direction': 'none'};
    }
    final first = ((_logs.last['weight_kg']) as num?)?.toDouble() ?? 0.0;
    final latest = ((_logs.first['weight_kg']) as num?)?.toDouble() ?? 0.0;
    final change = latest - first;
    return {
      'change': change.abs(),
      'direction': change < 0 ? 'down' : change > 0 ? 'up' : 'same',
    };
  }

  // ─────────────────────────────────────────────────────────────
  // Top Goal Header Card (Prompted on top as requested)
  // ─────────────────────────────────────────────────────────────
  Widget _buildTopGoalCard(double latestWeight) {
    if (!_hasSetGoal || _goalWeight <= 0) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Text('🎯', style: TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Set Your Fitness Goal',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Set target weight & goal to unlock daily logging',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: Colors.white.withValues(alpha: 0.85),
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: () => _showSetGoalDialog(isFirstTime: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(
                'Set Goal',
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }

    final diff = latestWeight > 0 ? (latestWeight - _goalWeight) : 0.0;
    String statusText;
    Color statusColor;

    if (_goalType == 'Weight Loss') {
      if (latestWeight <= 0) {
        statusText = 'Target: ${_goalWeight.toStringAsFixed(1)} kg';
        statusColor = AppTheme.primary;
      } else if (diff <= 0) {
        statusText = 'Goal Achieved! 🎉';
        statusColor = AppTheme.success;
      } else {
        statusText = '${diff.abs().toStringAsFixed(1)} kg to lose';
        statusColor = const Color(0xFFD97706);
      }
    } else if (_goalType.contains('Muscle') || _goalType == 'Weight Gain') {
      if (latestWeight <= 0) {
        statusText = 'Target: ${_goalWeight.toStringAsFixed(1)} kg';
        statusColor = AppTheme.primary;
      } else if (diff >= 0) {
        statusText = 'Goal Achieved! 🎉';
        statusColor = AppTheme.success;
      } else {
        statusText = '${diff.abs().toStringAsFixed(1)} kg to gain';
        statusColor = AppTheme.info;
      }
    } else {
      statusText = latestWeight > 0
          ? '${diff.abs().toStringAsFixed(1)} kg from target'
          : 'Target: ${_goalWeight.toStringAsFixed(1)} kg';
      statusColor = AppTheme.primary;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.cardShadow,
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '🎯 $_goalType',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      statusText,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => _showSetGoalDialog(isFirstTime: false),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 14, color: AppTheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Edit',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Goal Weight',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_goalWeight.toStringAsFixed(1)} kg',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Current Weight',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    latestWeight > 0 ? '${latestWeight.toStringAsFixed(1)} kg' : '—',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: latestWeight > 0 ? AppTheme.primary : AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
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
          'Body Stats',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.track_changes_rounded, color: AppTheme.primary),
            tooltip: 'Update Goal',
            onPressed: () => _showSetGoalDialog(isFirstTime: false),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle:
              GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle:
              GoogleFonts.inter(fontSize: 13),
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.primary,
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: AppTheme.border,
          tabs: const [
            Tab(text: 'Progress'),
            Tab(text: 'Log Today'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildProgressTab(),
          _buildLogTab(),
        ],
      ),
    );
  }

  Widget _buildProgressTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    final latestWeight =
        ((_latestLog?['weight_kg']) as num?)?.toDouble() ?? 0.0;
    final progress = _weightProgress;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Prominent Goal Card at Top ──
          _buildTopGoalCard(latestWeight),

          if (_logs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('⚖️', style: TextStyle(fontSize: 56)),
                    const SizedBox(height: 14),
                    Text(
                      'No stats logged yet',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Log today\'s stats to start tracking progress',
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () => _tabController.animateTo(1),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Log Today Now'),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // ── Current stats cards ──
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    '⚖️',
                    latestWeight > 0 ? '${latestWeight}kg' : '—',
                    'Current Weight',
                    AppTheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    '🎯',
                    _goalWeight > 0 ? '${_goalWeight}kg' : 'Not Set',
                    'Goal Weight',
                    AppTheme.success,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Progress vs goal ──
            if (latestWeight > 0 && _goalWeight > 0) ...[
              Container(
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Progress to Goal',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          progress['direction'] == 'down'
                              ? '⬇️ -${progress['change'].toStringAsFixed(1)}kg'
                              : progress['direction'] == 'up'
                                  ? '⬆️ +${progress['change'].toStringAsFixed(1)}kg'
                                  : '—',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: progress['direction'] == 'down'
                                ? AppTheme.success
                                : AppTheme.warning,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (_goalWeight > 0)
                            ? (latestWeight / _goalWeight).clamp(0.0, 1.0)
                            : 0.0,
                        backgroundColor: AppTheme.surfaceGray,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          latestWeight <= _goalWeight
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Start: ${(_logs.isNotEmpty ? (_logs.last['weight_kg'] ?? 0).toString() : '—')}kg',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: AppTheme.textMuted),
                        ),
                        Text(
                          'Goal: ${_goalWeight}kg',
                          style: GoogleFonts.inter(
                              fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Mini weight chart (bar-style) ──
            if (_logs.length >= 2) ...[
              Container(
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
                    Text(
                      'Weight Trend (last ${_logs.length} entries)',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 100,
                      child: _WeightMiniChart(
                        logs: _logs,
                        goalWeight: _goalWeight,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Measurements ──
            if (_latestLog != null) ...[
              Text(
                'LATEST MEASUREMENTS',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textMuted,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: AppTheme.cardShadow,
                ),
                child: Column(
                  children: [
                    _measureRow('💪 Arms', _latestLog!['arms_cm'], 'cm'),
                    _measureRow('🫁 Chest', _latestLog!['chest_cm'], 'cm'),
                    _measureRow('🎯 Waist', _latestLog!['waist_cm'], 'cm'),
                    _measureRow('📊 Body Fat', _latestLog!['body_fat_pct'], '%'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Log history ──
            Text(
              'HISTORY',
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            ..._logs.take(10).map((log) => _historyTile(log)),
          ],
        ],
      ),
    );
  }

  Widget _buildLogTab() {
    final latestWeight =
        ((_latestLog?['weight_kg']) as num?)?.toDouble() ?? 0.0;
    final todayLog = _todayLog;
    final bool alreadyLoggedToday = todayLog != null && !_isEditingTodayLog;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Prominent Goal Card at Top ──
          _buildTopGoalCard(latestWeight),

          // ── Goal Gating: Must set goal before logging ──
          if (!_hasSetGoal || _goalWeight <= 0) ...[
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.border),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.flag_rounded, color: AppTheme.primary, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Set Your Goal to Start Logging',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Setting a target weight & goal allows accurate tracking, progress analytics, and daily milestones.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_task_rounded, size: 18),
                    label: const Text('Set Fitness Goal Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _showSetGoalDialog(isFirstTime: true),
                  ),
                ],
              ),
            ),
          ] else if (alreadyLoggedToday) ...[
            // ── Once Per Day Gating: Already logged today card ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
                boxShadow: AppTheme.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Stats Logged for Today! 🎉',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            Text(
                              DateFormat('EEEE, d MMM yyyy').format(DateTime.now()),
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        _measureRow('⚖️ Logged Weight', todayLog['weight_kg'], 'kg'),
                        _measureRow('📊 Body Fat', todayLog['body_fat_pct'], '%'),
                        _measureRow('🫁 Chest', todayLog['chest_cm'], 'cm'),
                        _measureRow('🎯 Waist', todayLog['waist_cm'], 'cm'),
                        _measureRow('💪 Arms', todayLog['arms_cm'], 'cm'),
                        if (todayLog['notes'] != null && todayLog['notes'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('📝 Notes: ', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted)),
                                Expanded(
                                  child: Text(
                                    todayLog['notes'].toString(),
                                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit_rounded, size: 16),
                          label: const Text('Edit Today\'s Stats'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            setState(() {
                              _isEditingTodayLog = true;
                              _prefillControllers(todayLog);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.insights_rounded, size: 16),
                          label: const Text('View Progress'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          onPressed: () => _tabController.animateTo(0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            // ── Log Form ──
            if (_isEditingTodayLog)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_note_rounded, color: Color(0xFFD97706), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Editing Today\'s Stats',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF92400E),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() => _isEditingTodayLog = false);
                      },
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFD97706),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Header Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Text('⚖️', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isEditingTodayLog ? 'Update Today\'s Stats' : 'Log Today\'s Stats',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        DateFormat('EEEE, d MMM').format(DateTime.now()),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Form sections: Weight & Body Composition (Prominently visible)
            _inputSection(
              title: 'Weight & Body Composition',
              children: [
                _formField(
                    controller: _weightCtrl,
                    label: 'Weight (kg)',
                    icon: '⚖️',
                    required: true),
                const SizedBox(height: 12),
                _formField(
                    controller: _bodyFatCtrl,
                    label: 'Body Fat %',
                    icon: '📊'),
              ],
            ),

            const SizedBox(height: 12),

            // Collapsible Body Measurements (cm)
            _accordionSection(
              title: 'Body Measurements (cm)',
              subtitle: _showMeasurements
                  ? 'Chest, Waist, Arms'
                  : (_chestCtrl.text.isNotEmpty || _waistCtrl.text.isNotEmpty || _armsCtrl.text.isNotEmpty)
                      ? 'Values entered • Tap to edit'
                      : 'Optional • Tap to enter',
              icon: '📏',
              isExpanded: _showMeasurements,
              onToggle: () => setState(() => _showMeasurements = !_showMeasurements),
              children: [
                _formField(
                    controller: _chestCtrl,
                    label: 'Chest (cm)',
                    icon: '🫁'),
                const SizedBox(height: 12),
                _formField(
                    controller: _waistCtrl,
                    label: 'Waist (cm)',
                    icon: '🎯'),
                const SizedBox(height: 12),
                _formField(
                    controller: _armsCtrl,
                    label: 'Arms / Bicep (cm)',
                    icon: '💪'),
              ],
            ),

            const SizedBox(height: 12),

            // Collapsible Notes (Optional)
            _accordionSection(
              title: 'Daily Notes (Optional)',
              subtitle: _showNotes
                  ? null
                  : _notesCtrl.text.isNotEmpty
                      ? 'Note entered • Tap to view/edit'
                      : 'Tap to add how you feel today',
              icon: '📝',
              isExpanded: _showNotes,
              onToggle: () => setState(() => _showNotes = !_showNotes),
              children: [
                TextField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  style: GoogleFonts.inter(
                      fontSize: 14, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'How are you feeling today?',
                    hintStyle: GoogleFonts.inter(
                        fontSize: 14, color: AppTheme.textMuted),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isSaving ? null : _saveLog,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                backgroundColor: AppTheme.primary,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(
                      _isEditingTodayLog ? 'Update Stats 💾' : 'Save Stats 💾',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statCard(String emoji, String value, String label, Color accentColor) {
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22)),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _measureRow(String label, dynamic value, String unit) {
    if (value == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
          Text('$value $unit', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> log) {
    final dateStr = (log['logged_date'] ?? log['created_at'] ?? '').toString();
    DateTime? date;
    if (dateStr.isNotEmpty) {
      try {
        date = DateTime.parse(dateStr);
      } catch (_) {}
    }
    final formattedDate = date != null ? DateFormat('d MMM yyyy').format(date) : dateStr;
    final weight = (log['weight_kg'] as num?)?.toDouble();
    final bodyFat = (log['body_fat_pct'] as num?)?.toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('⚖️', style: TextStyle(fontSize: 14)),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    weight != null ? '${weight}kg' : '—',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    formattedDate,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (bodyFat != null && bodyFat > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'BF ${bodyFat.toStringAsFixed(1)}%',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _inputSection({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
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
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _accordionSection({
    required String title,
    required String icon,
    required bool isExpanded,
    required VoidCallback onToggle,
    required List<Widget> children,
    String? subtitle,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.border,
        ),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isExpanded
                          ? AppTheme.primary.withValues(alpha: 0.1)
                          : const Color(0xFFF1F5F9),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: isExpanded ? AppTheme.primary : AppTheme.textSecondary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: AppTheme.border),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _formField({
    required TextEditingController controller,
    required String label,
    required String icon,
    bool required = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.inter(
          fontSize: 14, color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: '$icon  $label${required ? ' *' : ''}',
        labelStyle:
            GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary),
        floatingLabelStyle:
            GoogleFonts.inter(fontSize: 13, color: AppTheme.primary),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Interactive Modal: Set or Update Fitness Goal
  // ─────────────────────────────────────────────────────────────
  Future<void> _showSetGoalDialog({bool isFirstTime = false}) async {
    final weightCtrl = TextEditingController(
        text: _goalWeight > 0 ? '$_goalWeight' : '');
    final bodyFatCtrl = TextEditingController(
        text: _goalBodyFat != null ? '$_goalBodyFat' : '');
    String selectedType = _goalType;
    int selectedDays = _weeklyGymDays;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('🎯', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isFirstTime ? 'Set Your Fitness Goal' : 'Update Fitness Goal',
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isFirstTime
                                ? 'Set your goal to unlock daily body tracking'
                                : 'Adjust your target weight and plan',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Goal Type Chips
                Text(
                  'PRIMARY GOAL',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    'Weight Loss',
                    'Lean Muscle Gain',
                    'Weight Gain',
                    'General Fitness'
                  ].map((type) {
                    final isSel = selectedType == type;
                    return ChoiceChip(
                      label: Text(type),
                      selected: isSel,
                      selectedColor: AppTheme.primary,
                      backgroundColor: const Color(0xFFF1F5F9),
                      labelStyle: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                        color: isSel ? Colors.white : const Color(0xFF334155),
                      ),
                      onSelected: (_) {
                        setModalState(() => selectedType = type);
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 16),

                // Target Weight
                TextField(
                  controller: weightCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Target Weight (kg) *',
                    hintText: 'e.g. 70.0',
                    labelStyle: GoogleFonts.inter(color: AppTheme.primary),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.scale_rounded, size: 20),
                  ),
                ),

                const SizedBox(height: 12),

                // Optional Body Fat
                TextField(
                  controller: bodyFatCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Target Body Fat % (optional)',
                    hintText: 'e.g. 15.0',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.percent_rounded, size: 20),
                  ),
                ),

                const SizedBox(height: 16),

                // Weekly Gym Days
                Text(
                  'WEEKLY WORKOUT FREQUENCY',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textMuted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [3, 4, 5, 6, 7].map((days) {
                    final isSel = selectedDays == days;
                    return InkWell(
                      onTap: () => setModalState(() => selectedDays = days),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSel ? AppTheme.primary : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$days d',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                            color: isSel ? Colors.white : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 22),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    final w = double.tryParse(weightCtrl.text.trim());
                    if (w == null || w <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a valid target weight in kg.'),
                          backgroundColor: AppTheme.danger,
                        ),
                      );
                      return;
                    }

                    final bf = double.tryParse(bodyFatCtrl.text.trim());

                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setDouble('member_goal_weight_${widget.memberId}', w);
                    await prefs.setString('member_goal_type_${widget.memberId}', selectedType);
                    await prefs.setBool('member_has_set_goal_${widget.memberId}', true);

                    if (mounted) {
                      setState(() {
                        _goalWeight = w;
                        _goalType = selectedType;
                        _goalBodyFat = bf;
                        _weeklyGymDays = selectedDays;
                        _hasSetGoal = true;
                      });
                    }

                    if (ctx.mounted) Navigator.pop(ctx);

                    // Sync goal to Supabase
                    if (SupabaseService.isInitialized && widget.memberId.isNotEmpty) {
                      try {
                        String gymId = widget.gymId;
                        if (gymId.isEmpty) {
                          final gymInfoStr = prefs.getString('gymos_gym_info');
                          if (gymInfoStr != null) {
                            final gi = jsonDecode(gymInfoStr);
                            gymId = gi['id'] ?? '';
                          }
                        }
                        if (gymId.isEmpty) {
                          final mDoc = await SupabaseService.client
                              .from('members')
                              .select('gym_id')
                              .eq('id', widget.memberId)
                              .maybeSingle();
                          gymId = mDoc?['gym_id']?.toString() ?? '';
                        }

                        if (gymId.isNotEmpty) {
                          await SupabaseService.client.from('member_fitness_goals').upsert({
                            'gym_id': gymId,
                            'member_id': widget.memberId,
                            'goal_type': selectedType,
                            'goal_weight_kg': w,
                            'goal_body_fat': bf,
                            'weekly_gym_days': selectedDays,
                            'updated_at': DateTime.now().toIso8601String(),
                          }, onConflict: 'member_id');
                        }
                      } catch (_) {}
                    }

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Fitness goal set to $w kg ($selectedType)! 💪 You can now log your stats.'),
                          backgroundColor: AppTheme.success,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: Text(
                    isFirstTime ? 'Save Goal & Start Tracking' : 'Save Fitness Goal',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Simple weight mini-chart widget (custom painter)
// ─────────────────────────────────────────────────────────────
class _WeightMiniChart extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  final double goalWeight;

  const _WeightMiniChart({required this.logs, required this.goalWeight});

  @override
  Widget build(BuildContext context) {
    final weights = logs
        .map((l) => (l['weight_kg'] as num?)?.toDouble())
        .where((w) => w != null)
        .cast<double>()
        .toList()
        .reversed
        .toList();

    if (weights.isEmpty) return const SizedBox();

    return CustomPaint(
      painter: _WeightChartPainter(
        weights: weights,
        goalWeight: goalWeight,
        lineColor: AppTheme.primary,
        goalColor: AppTheme.success,
      ),
      size: Size.infinite,
    );
  }
}

class _WeightChartPainter extends CustomPainter {
  final List<double> weights;
  final double goalWeight;
  final Color lineColor;
  final Color goalColor;

  _WeightChartPainter({
    required this.weights,
    required this.goalWeight,
    required this.lineColor,
    required this.goalColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (weights.isEmpty) return;

    final allValues = [...weights, goalWeight];
    final minW = allValues.reduce((a, b) => a < b ? a : b) - 2;
    final maxW = allValues.reduce((a, b) => a > b ? a : b) + 2;

    double xStep = weights.length > 1
        ? size.width / (weights.length - 1)
        : size.width;

    // Draw goal line
    final goalY = size.height -
        ((goalWeight - minW) / (maxW - minW)) * size.height;
    final goalPaint = Paint()
      ..color = goalColor.withValues(alpha: 0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
        Offset(0, goalY), Offset(size.width, goalY), goalPaint);

    // Draw weight line
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < weights.length; i++) {
      final x = i * xStep;
      final y = size.height -
          ((weights[i] - minW) / (maxW - minW)) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      // Dot
      canvas.drawCircle(
          Offset(x, y),
          4,
          Paint()
            ..color = lineColor
            ..style = PaintingStyle.fill);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
