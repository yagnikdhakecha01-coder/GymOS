import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/theme.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/local_storage.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/widgets/app_branding_header.dart';
import '../authentication/login_screen.dart';
import '../authentication/auth_viewmodel.dart';
import '../dashboard/main_navigation_holder.dart';
import '../staff/portal/staff_shell.dart';
import '../member_app/screens/member_shell.dart';

class WebQrLoginScreen extends StatefulWidget {
  const WebQrLoginScreen({super.key});

  @override
  State<WebQrLoginScreen> createState() => _WebQrLoginScreenState();
}

class _WebQrLoginScreenState extends State<WebQrLoginScreen> {
  String? _sessionToken;
  DateTime? _expiresAt;
  bool _isLoading = true;
  bool _isApproved = false;
  bool _isExpired = false;
  String? _approvedRole;
  String? _approvedGymName;
  String? _approvedUserEmail;

  RealtimeChannel? _realtimeChannel;
  Timer? _fallbackPollTimer;
  Timer? _expiryCountdownTimer;
  int _secondsRemaining = 600; // 10 minutes

  @override
  void initState() {
    super.initState();
    _initSession();
  }

  @override
  void dispose() {
    _cleanupRealtime();
    _fallbackPollTimer?.cancel();
    _expiryCountdownTimer?.cancel();
    super.dispose();
  }

  void _cleanupRealtime() {
    if (_realtimeChannel != null) {
      SupabaseService.client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
  }

  Future<void> _initSession() async {
    setState(() {
      _isLoading = true;
      _isExpired = false;
      _isApproved = false;
    });

    _cleanupRealtime();
    _fallbackPollTimer?.cancel();
    _expiryCountdownTimer?.cancel();

    try {
      final res = await SupabaseService.client.rpc(
        'create_web_qr_session',
        params: {
          'p_device_name': _detectClientDevice(),
        },
      );

      final data = res is String ? jsonDecode(res) : res;
      final token = data['token'] as String;
      final expiresStr = data['expires_at'] as String;
      final expires = DateTime.parse(expiresStr);

      if (mounted) {
        setState(() {
          _sessionToken = token;
          _expiresAt = expires;
          _secondsRemaining = expires.difference(DateTime.now()).inSeconds;
          _isLoading = false;
        });

        _startCountdown();
        _subscribeToRealtime(token);
        _startFallbackPolling(token);
      }
    } catch (e) {
      debugPrint('Error creating web QR session: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isExpired = true;
        });
      }
    }
  }

  String _detectClientDevice() {
    return 'Chrome on Desktop (GymOS Web)';
  }

  void _startCountdown() {
    _expiryCountdownTimer?.cancel();
    _expiryCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _secondsRemaining = 0;
          _isExpired = true;
        });
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  void _subscribeToRealtime(String token) {
    _cleanupRealtime();

    try {
      _realtimeChannel = SupabaseService.client
          .channel('web_login_$token')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'web_login_sessions',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'token',
              value: token,
            ),
            callback: (payload) {
              final newRecord = payload.newRecord;
              if (newRecord['status'] == 'approved') {
                _onSessionApproved(newRecord);
              }
            },
          )
          .subscribe();
    } catch (e) {
      debugPrint('Realtime subscription error (fallback polling will handle): $e');
    }
  }

  void _startFallbackPolling(String token) {
    _fallbackPollTimer?.cancel();
    _fallbackPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_isApproved || _isExpired || !mounted) {
        timer.cancel();
        return;
      }

      try {
        final res = await SupabaseService.client
            .from('web_login_sessions')
            .select('*')
            .eq('token', token)
            .maybeSingle();

        if (res != null && res['status'] == 'approved' && mounted) {
          timer.cancel();
          _onSessionApproved(res);
        }
      } catch (_) {}
    });
  }

  Future<void> _onSessionApproved(Map<String, dynamic> session) async {
    if (_isApproved) return;

    setState(() {
      _isApproved = true;
      _approvedRole = session['role'] as String?;
    });

    _cleanupRealtime();
    _fallbackPollTimer?.cancel();
    _expiryCountdownTimer?.cancel();

    final storage = LocalStorageService.instance;
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final repo = Provider.of<GymRepository>(context, listen: false);

    final role = (session['role'] as String? ?? 'owner').toLowerCase();
    final gymId = session['gym_id'] as String?;
    final userId = session['user_id'] as String?;

    // 1. Establish Supabase Auth session on web using refresh_token and accessToken
    final authPayload = (session['auth_payload'] ?? session['user_metadata']) as Map<String, dynamic>? ?? {};
    final refreshToken = authPayload['refresh_token'] as String?;
    final accessToken = authPayload['access_token'] as String?;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        if (accessToken != null && accessToken.isNotEmpty) {
          await SupabaseService.client.auth.setSession(refreshToken, accessToken: accessToken);
        } else {
          await SupabaseService.client.auth.setSession(refreshToken);
        }
      } catch (e) {
        debugPrint('Web setSession error: $e');
      }
    }

    if (storage != null) {
      await storage.setLoggedIn(true);
      await storage.setUserRole(role);
      await storage.setString('gymos_web_session_token', (session['token'] ?? session['session_token'] ?? '').toString());
      await storage.setBool('gymos_web_permanent_session', true);

      if (gymId != null) {
        try {
          final gymData = await SupabaseService.client
              .from('gyms')
              .select('*')
              .eq('id', gymId)
              .maybeSingle();
          if (gymData != null) {
            final realGymName = gymData['name'] ?? gymData['gym_name'] ?? 'Gym';
            gymData['name'] = realGymName;
            gymData['gym_name'] = realGymName;
            await storage.setGymInfo(gymData);
            _approvedGymName = realGymName.toString();
          }
        } catch (_) {}
      }

      if (storage.getGymInfo() == null) {
        await storage.setGymInfo({
          'id': gymId ?? 'gymos_primary',
          'gym_name': _approvedGymName ?? 'Gym',
          'name': _approvedGymName ?? 'Gym',
          'plan': 'Active',
          'attendanceMethod': 'QR Code',
        });
      }
    }

    // 2. Fetch authenticated profile and initial stats
    try {
      await authVm.loadCurrentProfile();
    } catch (_) {}

    // 3. Immediately sync gym data into repository so all views have real data
    final effectiveGymId = gymId ?? 
                          authVm.activeAssociation?.gymId ?? 
                          authVm.gymInfo?['id'] ?? 
                          storage?.getGymInfo()?['id'];
    if (effectiveGymId != null && effectiveGymId.toString().isNotEmpty) {
      try {
        await repo.performInitialSync(effectiveGymId.toString());
      } catch (e) {
        debugPrint('Error performing initial sync on web login: $e');
      }
    }

    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;

    Widget targetDashboard;
    if (role == 'staff') {
      targetDashboard = const StaffShell();
    } else if (role == 'member') {
      targetDashboard = const MemberShell();
    } else {
      targetDashboard = const MainNavigationHolder();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => targetDashboard),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FA),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F6FD),
              Color(0xFFF5F6FA),
              Color(0xFFEEF0F7),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 960),
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Instructions
          Expanded(
            flex: 6,
            child: _buildInstructionsContent(),
          ),
          const SizedBox(width: 48),
          Container(width: 1, height: 380, color: AppTheme.border),
          const SizedBox(width: 48),
          // Right: QR Code Card
          Expanded(
            flex: 5,
            child: _buildQrCard(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.12), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInstructionsHeaderOnly(),
          const SizedBox(height: 24),
          _buildQrCard(),
          const SizedBox(height: 24),
          _buildInstructionsStepsOnly(),
        ],
      ),
    );
  }

  Widget _buildInstructionsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppBrandingHeader(
          logoSize: 64,
          fontSize: 26,
          spacing: 16,
          welcomeText: false,
        ),
        const SizedBox(height: 20),
        Text(
          'Log in to GymOS Web',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Manage your gym, members, attendance and finances from any computer with zero session expiry.',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: AppTheme.textSecondary,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        _buildStepItem(1, 'Open GymOS app on your phone'),
        const SizedBox(height: 14),
        _buildStepItem(2, 'Tap the QR Scanner icon'),
        const SizedBox(height: 14),
        _buildStepItem(3, 'Point your camera at this screen to log in'),
        const SizedBox(height: 28),
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              'Permanent Session · Logged in until manual logout',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.primaryDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen(role: 'Gym Owner')),
            );
          },
          child: Text(
            'Or log in with Email & Password →',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInstructionsHeaderOnly() {
    return Column(
      children: [
        const AppBrandingHeader(
          logoSize: 56,
          fontSize: 22,
          spacing: 14,
          welcomeText: false,
        ),
        const SizedBox(height: 12),
        Text(
          'Log in to GymOS Web',
          style: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Scan with your GymOS mobile app',
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildInstructionsStepsOnly() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepItem(1, 'Open GymOS on your phone'),
        const SizedBox(height: 8),
        _buildStepItem(2, 'Tap the QR Scanner icon'),
        const SizedBox(height: 8),
        _buildStepItem(3, 'Scan this code to instantly log in'),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen(role: 'Gym Owner')),
              );
            },
            child: Text(
              'Login with Email & Password',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepItem(int stepNumber, String text) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppTheme.primaryLight,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$stepNumber',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryDark,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQrCard() {
    final qrData = _sessionToken != null ? 'gymos_web_login:$_sessionToken' : '';

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.16), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SizedBox(
            width: 210,
            height: 210,
            child: _buildQrContent(qrData),
          ),
        ),
        const SizedBox(height: 16),
        if (!_isApproved && !_isExpired && !_isLoading) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Ready to scan · Refreshes in ${_formatCountdown(_secondsRemaining)}',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildQrContent(String qrData) {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5),
            const SizedBox(height: 12),
            Text(
              'Generating QR Code...',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_isApproved) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppTheme.successLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 36),
            ),
            const SizedBox(height: 12),
            Text(
              'Login Approved!',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Opening dashboard...',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_isExpired) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.refresh_rounded, color: AppTheme.warning, size: 38),
            const SizedBox(height: 10),
            Text(
              'QR Code Expired',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _initSession,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text('Click to Reload', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    return QrImageView(
      data: qrData,
      version: QrVersions.auto,
      size: 210.0,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF1E1B4B),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF1E1B4B),
      ),
    );
  }

  String _formatCountdown(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
