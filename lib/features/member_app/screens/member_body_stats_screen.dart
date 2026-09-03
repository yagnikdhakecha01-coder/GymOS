import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  double _goalWeight = 0.0;

  late TabController _tabController;

  // Form controllers
  final _weightCtrl = TextEditingController();
  final _bodyFatCtrl = TextEditingController();
  final _chestCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _armsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

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
    setState(() {
      _goalWeight =
          prefs.getDouble('member_goal_weight_${widget.memberId}') ?? 75.0;
    });
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
      if (result is List && result.isNotEmpty) {
        logs = result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }

      // 3. If no body logs yet, check if Owner or Staff entered weight in members profile!
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
    if (_weightCtrl.text.isEmpty && log['weight_kg'] != null) {
      _weightCtrl.text = log['weight_kg'].toString();
    }
    if (_bodyFatCtrl.text.isEmpty && log['body_fat_pct'] != null) {
      _bodyFatCtrl.text = log['body_fat_pct'].toString();
    }
    if (_chestCtrl.text.isEmpty && log['chest_cm'] != null) {
      _chestCtrl.text = log['chest_cm'].toString();
    }
    if (_waistCtrl.text.isEmpty && log['waist_cm'] != null) {
      _waistCtrl.text = log['waist_cm'].toString();
    }
    if (_armsCtrl.text.isEmpty && log['arms_cm'] != null) {
      _armsCtrl.text = log['arms_cm'].toString();
    }
  }

  Future<void> _saveLog() async {
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

    // Offline-first: update local list
    _logs.removeWhere(
        (l) => (l['logged_date'] as String? ?? '') == todayStr);
    _logs.insert(0, logEntry);
    _latestLog = logEntry;

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
          content: Text('Stats saved! 💪',
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

    if (_logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('⚖️', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              'No stats logged yet',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Log today\'s stats to start tracking',
              style: GoogleFonts.inter(
                  fontSize: 14, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _tabController.animateTo(1),
              child: const Text('Log Now'),
            ),
          ],
        ),
      );
    }

    final progress = _weightProgress;
    final latestWeight =
        ((_latestLog?['weight_kg']) as num?)?.toDouble() ?? 0.0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  '${_goalWeight}kg',
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
                  _measureRow(
                      '🎯 Waist', _latestLog!['waist_cm'], 'cm'),
                  _measureRow(
                      '📊 Body Fat', _latestLog!['body_fat_pct'], '%'),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

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
      ),
    );
  }

  Widget _statCard(
      String emoji, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.inter(
                fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _measureRow(String label, dynamic value, String unit) {
    final hasValue = value != null && value.toString() != 'null';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppTheme.textSecondary)),
          Text(
            hasValue ? '${value}$unit' : '—',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: hasValue
                  ? AppTheme.textPrimary
                  : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(Map<String, dynamic> log) {
    final date = log['logged_date'] as String? ?? '';
    final weight = log['weight_kg'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              date,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppTheme.textSecondary),
            ),
          ),
          Text(
            weight != null ? '${weight}kg' : '—',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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
                      'Log Today\'s Stats',
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

          const SizedBox(height: 20),

          // Form
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

          const SizedBox(height: 16),

          _inputSection(
            title: 'Body Measurements (cm)',
            children: [
              _formField(
                  controller: _chestCtrl,
                  label: 'Chest',
                  icon: '🫁'),
              const SizedBox(height: 12),
              _formField(
                  controller: _waistCtrl,
                  label: 'Waist',
                  icon: '🎯'),
              const SizedBox(height: 12),
              _formField(
                  controller: _armsCtrl,
                  label: 'Arms (bicep)',
                  icon: '💪'),
            ],
          ),

          const SizedBox(height: 16),

          _inputSection(
            title: 'Notes (optional)',
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

          const SizedBox(height: 24),

          // Goal weight setter
          Row(
            children: [
              Expanded(
                child: Text(
                  'Goal Weight: ${_goalWeight}kg',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: _setGoalWeight,
                child: Text(
                  'Set Goal',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

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
                    'Save Stats 💾',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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

  Future<void> _setGoalWeight() async {
    final ctrl = TextEditingController(text: '$_goalWeight');
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Set Goal Weight',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        content: TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Goal weight (kg)',
            labelStyle:
                GoogleFonts.inter(color: AppTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () async {
              final g = double.tryParse(ctrl.text);
              if (g != null) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setDouble(
                    'member_goal_weight_${widget.memberId}', g);
                if (mounted) setState(() => _goalWeight = g);
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
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
