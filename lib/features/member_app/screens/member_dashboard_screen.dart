import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../member_app_viewmodel.dart';
import 'member_training_screen.dart';
import 'member_diet_screen.dart';

import 'member_notifications_screen.dart';

class MemberDashboardScreen extends StatefulWidget {
  const MemberDashboardScreen({super.key});

  @override
  State<MemberDashboardScreen> createState() => _MemberDashboardScreenState();
}

class _MemberDashboardScreenState extends State<MemberDashboardScreen>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _fadeAnims;
  late List<Animation<Offset>> _slideAnims;
  static const int _sectionCount = 5;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      _sectionCount,
      (i) => AnimationController(vsync: this, duration: const Duration(milliseconds: 500)),
    );
    _fadeAnims = _controllers.map((c) =>
      Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: c, curve: Curves.easeOut))
    ).toList();
    _slideAnims = _controllers.map((c) =>
      Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
          .animate(CurvedAnimation(parent: c, curve: Curves.easeOutCubic))
    ).toList();
    _startAnimations();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MemberAppViewModel>(context, listen: false).loadMemberDataFromSupabase();
    });
  }

  void _startAnimations() {
    for (int i = 0; i < _sectionCount; i++) {
      Future.delayed(Duration(milliseconds: 80 + (i * 80)), () {
        if (mounted) _controllers[i].forward();
      });
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) { c.dispose(); }
    super.dispose();
  }

  Widget _animated(int i, Widget child) {
    if (i >= _sectionCount) return child;
    return FadeTransition(opacity: _fadeAnims[i], child: SlideTransition(position: _slideAnims[i], child: child));
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Consumer<MemberAppViewModel>(
      builder: (context, vm, _) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),

                  // ═══════ HEADER: Hello, Jigar 👋 (Image 4 top) ═══════
                  _animated(0, Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello, ${vm.memberName} 👋',
                                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    'Membership: ${vm.membershipPlan} ',
                                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: vm.membershipStatus == 'Active' ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      vm.membershipStatus,
                                      style: GoogleFonts.inter(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: vm.membershipStatus == 'Active' ? Colors.green : Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Notification bell
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const MemberNotificationsScreen()),
                            );
                          },
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Stack(
                              children: [
                                const Center(child: Icon(Icons.notifications_outlined, color: AppTheme.textPrimary, size: 22)),
                                if (vm.notificationCount > 0)
                                  Positioned(
                                    top: 6, right: 6,
                                    child: Container(
                                      width: 8, height: 8,
                                      decoration: const BoxDecoration(color: AppTheme.danger, shape: BoxShape.circle),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Profile avatar
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 2),
                          ),
                          child: ClipOval(
                            child: vm.memberAvatar.startsWith('http')
                                ? Image.network(
                                    vm.memberAvatar,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: AppTheme.primaryLight,
                                      child: const Icon(Icons.person_rounded, color: AppTheme.primary, size: 22),
                                    ),
                                  )
                                : Image.asset(
                                    'assets/images/member/avatar_default.png',
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: AppTheme.primaryLight,
                                      child: const Icon(Icons.person_rounded, color: AppTheme.primary, size: 22),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 20),

                  // ═══════ STREAK CARD (Image 4 - purple gradient) ═══════
                  _animated(1, Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: AppTheme.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Current Streak', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white70)),
                              const Spacer(),
                              const Icon(Icons.local_fire_department_rounded, color: Colors.orangeAccent, size: 20),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${vm.currentStreak} Days',
                            style: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            vm.currentStreak == 0
                                ? "Last Streak: ${vm.lastStreak} Days"
                                : "Don't break your streak!",
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
                          ),
                          const SizedBox(height: 16),
                          // Week day circles
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: List.generate(vm.weekDays.length, (i) {
                              final attended = vm.weekAttendance[i];
                              return Column(
                                children: [
                                  Text(vm.weekDays[i], style: GoogleFonts.inter(fontSize: 10, color: Colors.white60, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 6),
                                  Container(
                                    width: 32, height: 32,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: attended ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
                                      border: attended ? Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5) : null,
                                    ),
                                    child: Center(
                                      child: attended
                                          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                                          : Text('${vm.weekDates[i]}', style: GoogleFonts.inter(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w600)),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  )),
                  const SizedBox(height: 20),

                  // ═══════ STATS GRID 2x2 (Image 4 - 4 stat cards) ═══════
                  _animated(2, Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _buildStatCard('🏋️', 'Attendance', '${vm.attendancePercentage}%', 'This Month', const Color(0xFF7C3AED))),
                            const SizedBox(width: 12),
                            Expanded(child: _buildStatCard('💎', 'Membership', '${vm.membershipDaysLeft}', 'Days Left', const Color(0xFF16A34A))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: _buildStatCard('🏆', 'PT Sessions', '${vm.ptSessionsLeft}', 'Sessions Left', const Color(0xFF3B82F6))),
                            const SizedBox(width: 12),
                            Expanded(child: _buildStatCard('💳', 'Pending Payment', '₹${vm.pendingAmount.toStringAsFixed(0)}', vm.pendingAmount > 0 ? 'Pending' : 'All Clear', const Color(0xFFF59E0B))),
                          ],
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 20),

                  // ═══════ TODAY'S TRAINING CARD ═══════
                  _animated(3, Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFF1F0FB)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF5A4FCF).withOpacity(0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Left Section: 70% width
                                Expanded(
                                  flex: 7,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Header: Icon + Today's Training
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3F0FF),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Transform.rotate(
                                              angle: -0.7853981633974483, // Rotate 45 degrees counterclockwise to make horizontal
                                              child: const Icon(
                                                Icons.fitness_center_rounded,
                                                color: Color(0xFF7C3AED),
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Today's Training",
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF4B5563),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      // Title: Chest Day / Plan Title
                                      Text(
                                        vm.assignedWorkoutId.isNotEmpty
                                            ? (vm.assignedWorkoutTitle.isNotEmpty ? vm.assignedWorkoutTitle : vm.todayMuscleGroup)
                                            : 'No Workout Assigned',
                                        style: GoogleFonts.inter(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF111827),
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      if (vm.assignedWorkoutId.isNotEmpty) ...[
                                        // Status Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: vm.isTrainingCompleted
                                                ? const Color(0xFFDCFCE7)
                                                : const Color(0xFFFEF3C7),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            vm.isTrainingCompleted ? 'Completed' : 'Not Completed',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: vm.isTrainingCompleted
                                                  ? const Color(0xFF15803D)
                                                  : const Color(0xFFD97706),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        // Subtitle/Description
                                        Text(
                                          "Ask your trainer for today's exercises & plan.",
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: const Color(0xFF4B5563),
                                            height: 1.4,
                                          ),
                                        ),
                                      ] else ...[
                                        Text(
                                          "Ask your gym owner to assign a workout plan.",
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: AppTheme.danger,
                                            fontWeight: FontWeight.bold,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Right Section: 30% width (Illustration)
                                if (vm.assignedWorkoutId.isNotEmpty)
                                  Expanded(
                                    flex: 3,
                                    child: Center(
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        child: SizedBox(
                                          width: vm.todayMuscleGroup.toLowerCase().contains('chest') ? 150 : 100,
                                          height: vm.todayMuscleGroup.toLowerCase().contains('chest') ? 150 : 150,
                                          child: Image.asset(
                                            vm.todayWorkoutImage,
                                            fit: vm.todayMuscleGroup.toLowerCase().contains('chest')
                                                ? BoxFit.cover
                                                : BoxFit.contain,
                                            errorBuilder: (_, __, ___) => const SizedBox(),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (vm.assignedWorkoutId.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Divider(
                                color: Color(0xFFE5E7EB),
                                height: 1,
                                thickness: 1,
                              ),
                              const SizedBox(height: 16),
                              // Ask Trainer button
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const MemberTrainingScreen()),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: const Color(0xFF7C3AED), width: 1.2),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.sms_outlined,
                                            color: Color(0xFF7C3AED),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Ask Trainer',
                                            style: GoogleFonts.inter(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF7C3AED),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Align(
                                        alignment: Alignment.centerRight,
                                        child: Padding(
                                          padding: EdgeInsets.only(right: 16),
                                          child: Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            color: Color(0xFF7C3AED),
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )),
                  const SizedBox(height: 20),

                  // ═══════ TODAY'S DIET CARD ═══════
                  _animated(3, Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFF1F0FB)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF16A34A).withOpacity(0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  flex: 7,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDCFCE7),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Icon(
                                              Icons.restaurant_menu_rounded,
                                              color: Color(0xFF16A34A),
                                              size: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            "Today's Diet",
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF4B5563),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        vm.assignedDietId.isNotEmpty
                                            ? (vm.assignedDietTitle.isNotEmpty ? vm.assignedDietTitle : vm.membershipPlan)
                                            : 'No Diet Assigned',
                                        style: GoogleFonts.inter(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF111827),
                                          letterSpacing: -0.5,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      if (vm.assignedDietId.isNotEmpty) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDCFCE7),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'Active Diet Plan',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF15803D),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          "View your custom macro and meal plan details.",
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: const Color(0xFF4B5563),
                                            height: 1.4,
                                          ),
                                        ),
                                      ] else ...[
                                        Text(
                                          "Ask your gym owner to assign a diet plan.",
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: AppTheme.danger,
                                            fontWeight: FontWeight.bold,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (vm.assignedDietId.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Divider(
                                color: Color(0xFFE5E7EB),
                                height: 1,
                                thickness: 1,
                              ),
                              const SizedBox(height: 16),
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const MemberDietScreen()),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: const Color(0xFF16A34A), width: 1.2),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.restaurant,
                                            color: Color(0xFF16A34A),
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'View Diet Plan',
                                            style: GoogleFonts.inter(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF16A34A),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Align(
                                        alignment: Alignment.centerRight,
                                        child: Padding(
                                          padding: EdgeInsets.only(right: 16),
                                          child: Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            color: Color(0xFF16A34A),
                                            size: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  )),
                  const SizedBox(height: 20),

                  // ═══════ QUICK ACTIONS ROW (Image 4 bottom icons) ═══════
                  _animated(4, Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildQuickAction(Icons.restaurant_menu_rounded, 'Diet Plan', const Color(0xFF16A34A), () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberDietScreen()));
                        }),
                        _buildQuickAction(Icons.fitness_center_rounded, 'Training', AppTheme.primary, () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const MemberTrainingScreen()));
                        }),
                        _buildQuickAction(Icons.qr_code_scanner_rounded, 'Scan QR', const Color(0xFF3B82F6), () {}),
                        _buildQuickAction(Icons.share_rounded, 'Share', const Color(0xFFF59E0B), () {}),
                      ],
                    ),
                  )),
                  const SizedBox(height: 30),

                  Center(
                    child: Text('Powered by GYMOS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted)),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(String emoji, String label, String value, String subtitle, Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(14),
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
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const Spacer(),
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }
}
