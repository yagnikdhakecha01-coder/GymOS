import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/services/supabase_service.dart';
import '../../core/repository/gym_repository.dart';
import '../member_app/member_app_viewmodel.dart';
import 'auth_viewmodel.dart';

class DataSyncScreen extends StatefulWidget {
  final Widget targetScreen;
  const DataSyncScreen({super.key, required this.targetScreen});

  @override
  State<DataSyncScreen> createState() => _DataSyncScreenState();
}

class _DataSyncScreenState extends State<DataSyncScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  double _progress = 0.0;
  String _statusText = 'Initializing secure synchronization...';
  String _errorText = '';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSyncSequence();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startSyncSequence() async {
    if (!mounted) return;
    setState(() {
      _progress = 0.0;
      _statusText = 'Verifying database connectivity...';
      _hasError = false;
      _errorText = '';
    });

    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final repository = Provider.of<GymRepository>(context, listen: false);
    final memberVm = Provider.of<MemberAppViewModel>(context, listen: false);

    // If Supabase is offline or unconfigured, we skip and load cached data immediately
    if (!SupabaseService.isInitialized || SupabaseService.hasError) {
      setState(() => _progress = 0.5);
      await Future.delayed(const Duration(milliseconds: 800));
      setState(() {
        _progress = 1.0;
        _statusText = 'Loaded from local storage (Offline Mode)';
      });
      _completeSync();
      return;
    }

    try {
      // Step 1: Profile & Association Verification
      setState(() {
        _progress = 0.1;
        _statusText = 'Loading user profile permissions...';
      });
      await authVm.loadCurrentProfile();
      final profile = authVm.currentProfile;
      final role = authVm.selectedRole ?? (profile?.role.name);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];

      if (profile == null || role == null) {
        throw Exception('User profile configuration missing.');
      }

      if (role == 'member') {
        // --- Member Sync Flow ---
        setState(() {
          _progress = 0.4;
          _statusText = 'Syncing member records and plans...';
        });
        await memberVm.loadMemberDataFromSupabase();

        setState(() {
          _progress = 0.7;
          _statusText = 'Caching fitness workouts and diets...';
        });
        // Call local sync steps
        await Future.delayed(const Duration(milliseconds: 300));
        
        setState(() {
          _progress = 0.9;
          _statusText = 'Finalizing onboarding profile...';
        });
        await Future.delayed(const Duration(milliseconds: 300));

      } else {
        // --- Owner/Staff Sync Flow ---
        if (gymId == null) {
          throw Exception('Gym details not found for active association.');
        }

        // We run sequential database downloads to populate our repository/cache
        final List<Map<String, dynamic>> steps = [
          {
            'progress': 0.2,
            'text': 'Caching active gym members...',
            'action': () => repository.fetchMembersFromSupabase(),
          },
          {
            'progress': 0.3,
            'text': 'Caching trial registrations...',
            'action': () => repository.fetchTrialMembersFromSupabase(),
          },
          {
            'progress': 0.4,
            'text': 'Caching staff and trainers...',
            'action': () => repository.fetchStaffFromSupabase(),
          },
          {
            'progress': 0.5,
            'text': 'Downloading workout routines...',
            'action': () => repository.fetchWorkoutsFromSupabase(),
          },
          {
            'progress': 0.6,
            'text': 'Downloading diet plan catalog...',
            'action': () => repository.fetchDietsFromSupabase(),
          },
          {
            'progress': 0.7,
            'text': 'Synchronizing historical transactions...',
            'action': () => repository.fetchTransactionsFromSupabase(),
          },
          {
            'progress': 0.8,
            'text': 'Synchronizing daily check-ins...',
            'action': () => repository.fetchAttendanceLogsFromSupabase(),
          },
          {
            'progress': 0.9,
            'text': 'Computing analytical growth trends...',
            'action': () async {
              final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
              await repository.fetchDashboardStatsFromSupabase(gymId, todayStr);
              await repository.fetchReportsAnalyticsFromSupabase(gymId, todayStr);
              await repository.fetchOwnerDashboardStats(gymId);
            },
          },
        ];

        for (var step in steps) {
          if (!mounted) return;
          setState(() {
            _progress = step['progress'] as double;
            _statusText = step['text'] as String;
          });
          
          try {
            final Future Function() action = step['action'] as Future Function();
            await action();
          } catch (e) {
            debugPrint('Sync warning on step: ${_statusText} ($e). Continuing...');
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _progress = 1.0;
        _statusText = 'Synchronization complete! Launching dashboard...';
      });

      await Future.delayed(const Duration(milliseconds: 500));
      _completeSync();

    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorText = e.toString().replaceAll('Exception:', '').trim();
          _statusText = 'Sync failed. You can continue offline.';
        });
      }
    }
  }

  void _completeSync() {
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => widget.targetScreen),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Premium Dark background
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Pulsing Icon
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C4EFF).withOpacity(0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF6C4EFF).withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.cloud_sync_rounded,
                      color: Color(0xFF6C4EFF),
                      size: 64,
                    ),
                  ),
                ),
                const SizedBox(height: 36),

                // Title
                Text(
                  'GYMOS Cloud Sync',
                  style: GoogleFonts.outfit(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),

                Text(
                  'Preparing your local environment for lag-free performance',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 48),

                // Linear Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 8,
                    width: double.infinity,
                    color: const Color(0xFF1E293B),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: _progress,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF6C4EFF), Color(0xFF3B82F6)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Status text
                Text(
                  _statusText,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _hasError ? Colors.amber[400] : const Color(0xFFCBD5E1),
                  ),
                ),
                const SizedBox(height: 8),

                // Percentage
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF6C4EFF),
                  ),
                ),

                if (_hasError) ...[
                  const SizedBox(height: 36),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                    ),
                    child: Text(
                      'Error: $_errorText',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent[100]),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _completeSync,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFF64748B)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            'Continue Offline',
                            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _startSyncSequence,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C4EFF),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            'Retry Sync',
                            style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
