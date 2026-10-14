import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/theme.dart';
import '../member_app_viewmodel.dart';
import 'member_training_screen.dart';
import 'member_diet_screen.dart';
import 'member_body_stats_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'member_notifications_screen.dart';
import '../../dashboard/gym_switcher_bottom_sheet.dart';
import '../widgets/workout_category_selector_sheet.dart';
import '../widgets/member_rules_agreement_dialog.dart';
import '../../../core/widgets/skeleton_shimmer.dart';
import '../../../core/widgets/app_cached_avatar.dart';
import 'member_shell.dart';

class MemberDashboardScreen extends StatefulWidget {
  const MemberDashboardScreen({super.key});

  @override
  State<MemberDashboardScreen> createState() => _MemberDashboardScreenState();
}

class _MemberDashboardScreenState extends State<MemberDashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MemberAppViewModel>(context, listen: false).loadMemberDataFromSupabase();
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Widget _animated(int i, Widget child) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Consumer<MemberAppViewModel>(
      builder: (context, vm, _) {
        if (vm.isLoadingMemberData && vm.memberName.isEmpty) {
          return const Scaffold(
            backgroundColor: AppTheme.background,
            body: SafeArea(
              child: DashboardSkeletonLoader(),
            ),
          );
        }

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
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () {
                                  GymSwitcherBottomSheet.show(context);
                                },
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Member • ${vm.gymName}',
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.arrow_drop_down_rounded,
                                        size: 16,
                                        color: AppTheme.primary,
                                      ),
                                    ],
                                  ),
                                ),
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
                        AppCachedAvatar(
                          imageUrl: vm.memberAvatar,
                          name: vm.memberName,
                          size: 40,
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3), width: 2),
                        ),
                      ],
                    ),
                  )),
                  const SizedBox(height: 16),

                  // ═══════ PENDING RULES AGREEMENT BANNER (For existing/old members) ═══════
                  if (!vm.hasAgreedRules) ...[
                    RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: InkWell(
                          onTap: () => MemberRulesAgreementDialog.show(context),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFEF2F2), Color(0xFFFFF1F2)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFFECDD3), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.shield_outlined, color: Color(0xFFDC2626), size: 24),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${vm.gymName.isNotEmpty && vm.gymName != 'GYMOS' ? vm.gymName : 'Gym'} Rules Agreement Pending',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF991B1B),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Please review and sign your gym rules to continue.',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: const Color(0xFFB91C1C),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Review',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

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

                  // ═══════ STATS GRID (Attendance, Membership Days Left, Pending Payment) ═══════
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
                    child: InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const MemberTrainingScreen()),
                        );
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFF1F0FB)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF5A4FCF).withValues(alpha: 0.06),
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
                                  // Left Section
                                  Expanded(
                                    flex: 7,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Header: Icon + Today's Training Day
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF3F0FF),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Transform.rotate(
                                                angle: -0.7853981633974483,
                                                child: const Icon(
                                                  Icons.fitness_center_rounded,
                                                  color: Color(0xFF7C3AED),
                                                  size: 16,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              "${DateFormat('EEEE').format(DateTime.now())}'s Training",
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF4B5563),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        // Title: Day + Muscle Group (Handles single or multiple splits cleanly)
                                        if (!vm.hasAssignedWorkout || vm.todayMuscleGroup == 'No Plan Assigned')
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'No Plan Assigned',
                                                style: GoogleFonts.inter(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w800,
                                                  color: const Color(0xFF111827),
                                                  letterSpacing: -0.5,
                                                ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                'Ask your gym to assign workout',
                                                style: GoogleFonts.inter(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: const Color(0xFF6B7280),
                                                ),
                                              ),
                                            ],
                                          )
                                        else if (vm.todaySplits.length <= 1)
                                          Text(
                                            vm.todayMuscleGroup,
                                            style: GoogleFonts.inter(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFF111827),
                                              letterSpacing: -0.5,
                                            ),
                                          )
                                        else
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              for (int s = 0; s < vm.todaySplits.length; s++) ...[
                                                if (s > 0) const SizedBox(height: 4),
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    if (s > 0)
                                                      Padding(
                                                        padding: const EdgeInsets.only(right: 6),
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: AppTheme.primaryLight.withValues(alpha: 0.6),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            '+',
                                                            style: GoogleFonts.inter(
                                                              fontSize: 11,
                                                              fontWeight: FontWeight.w800,
                                                              color: AppTheme.primary,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    Flexible(
                                                      child: Text(
                                                        vm.todaySplits[s],
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: GoogleFonts.inter(
                                                          fontSize: s == 0 ? 17 : 14,
                                                          fontWeight: s == 0 ? FontWeight.w800 : FontWeight.w700,
                                                          color: s == 0 ? const Color(0xFF111827) : const Color(0xFF4B5563),
                                                          letterSpacing: -0.3,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        const SizedBox(height: 8),
                                        // Status Badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: (!vm.hasAssignedWorkout || vm.todayMuscleGroup == 'No Plan Assigned')
                                                ? const Color(0xFFF1F5F9)
                                                : (vm.isRestDay
                                                    ? const Color(0xFFF3E8FF)
                                                    : (vm.isTrainingCompleted
                                                        ? const Color(0xFFDCFCE7)
                                                        : const Color(0xFFFEF3C7))),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            (!vm.hasAssignedWorkout || vm.todayMuscleGroup == 'No Plan Assigned')
                                                ? 'Plan Pending'
                                                : (vm.isRestDay
                                                    ? 'Rest & Recovery Day 🧘'
                                                    : (vm.isTrainingCompleted
                                                        ? 'Workout Completed 🎉'
                                                        : 'Not Completed Yet')),
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: (!vm.hasAssignedWorkout || vm.todayMuscleGroup == 'No Plan Assigned')
                                                  ? const Color(0xFF64748B)
                                                  : (vm.isRestDay
                                                      ? const Color(0xFF7C3AED)
                                                      : (vm.isTrainingCompleted
                                                          ? const Color(0xFF15803D)
                                                          : const Color(0xFFD97706))),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Right Section (Illustration - first split's image)
                                  Expanded(
                                    flex: 3,
                                    child: Center(
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        child: SizedBox(
                                          width: 110,
                                          height: 120,
                                          child: Image.asset(
                                            vm.todayWorkoutImage,
                                            fit: BoxFit.contain,
                                            cacheWidth: 350,
                                            cacheHeight: 350,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.fitness_center_rounded, size: 50, color: AppTheme.primary),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Divider(
                                color: Color(0xFFE5E7EB),
                                height: 1,
                                thickness: 1,
                              ),
                              const SizedBox(height: 16),
                              // Complete Workout button
                              GestureDetector(
                                onTap: () async {
                                  if (vm.isTrainingCompleted) return;
                                  final res = await vm.completeTodayWorkout(context);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(res['message']?.toString() ?? ''),
                                        backgroundColor: res['success'] == true ? AppTheme.success : AppTheme.danger,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: vm.isTrainingCompleted ? const Color(0xFFDCFCE7) : const Color(0xFF7C3AED),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        vm.isTrainingCompleted ? Icons.check_circle_rounded : Icons.task_alt_rounded,
                                        color: vm.isTrainingCompleted ? const Color(0xFF15803D) : Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        vm.isTrainingCompleted ? 'Workout Done 🎉' : 'Complete Workout',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: vm.isTrainingCompleted ? const Color(0xFF15803D) : Colors.white,
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
                    ),
                  )),
                  const SizedBox(height: 16),

                  // ═══════ QUICK ACCESS — Body Stats & Exercise Library ═══════
                  _animated(3, Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              onTap: () async {
                                final prefs = await SharedPreferences.getInstance();
                                final gymInfoStr = prefs.getString('gymos_gym_info');
                                String gymId = '';
                                if (gymInfoStr != null) {
                                  try {
                                    final gi = (jsonDecode(gymInfoStr) as Map<String, dynamic>);
                                    gymId = gi['id'] ?? '';
                                  } catch (_) {}
                                }
                                if (context.mounted) {
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => MemberBodyStatsScreen(
                                      memberId: vm.memberId,
                                      gymId: gymId,
                                    ),
                                  ));
                                }
                              },
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                height: 116,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
                                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF7C3AED).withValues(alpha: 0.25),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.monitor_weight_rounded, color: Colors.white, size: 20),
                                        ),
                                        const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 16),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Body Stats', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                                        const SizedBox(height: 3),
                                        Text('Track weight & goals', style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              onTap: () => WorkoutCategoryHelper.openCategoryFlow(
                                context,
                                splits: vm.todaySplits,
                                muscleGroup: vm.todayMuscleGroup,
                                memberId: vm.memberId,
                              ),
                              borderRadius: BorderRadius.circular(18),
                              child: Container(
                                height: 116,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF0284C7).withValues(alpha: 0.25),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.menu_book_rounded, color: Colors.white, size: 20),
                                        ),
                                        const Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 16),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Exercises', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                                        const SizedBox(height: 3),
                                        Text('50+ workout library', style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                        if (vm.isBiometricAttendanceOnly)
                          _buildQuickAction(Icons.calendar_month_rounded, 'Attendance', const Color(0xFF3B82F6), () {
                            MemberShell.switchToTab(context, 1);
                          })
                        else
                          _buildQuickAction(Icons.qr_code_scanner_rounded, 'Scan QR', const Color(0xFF3B82F6), () {
                            MemberShell.switchToTab(context, 2);
                          }),
                        _buildQuickAction(Icons.share_rounded, 'Share', const Color(0xFFF59E0B), () {
                          _showShareSheet(context, vm);
                        }),
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

  void _showShareSheet(BuildContext context, MemberAppViewModel vm) {
    final gymName = vm.gymName.isNotEmpty ? vm.gymName : 'GYMOS';
    final shareText = 'Join me at $gymName on GYMOS! Workout, track your daily progress, and smash your fitness goals together! 💪🔥';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
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
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Share $gymName',
              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Invite workout partners or share your fitness journey!',
              style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Share via WhatsApp
            ElevatedButton.icon(
              icon: const Text('💬', style: TextStyle(fontSize: 18)),
              label: Text('Share on WhatsApp', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                Navigator.pop(context);
                final uri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(shareText)}');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  await Clipboard.setData(ClipboardData(text: shareText));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('📋 Copied message to clipboard!'), backgroundColor: AppTheme.primary),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 10),

            // Copy Message Link
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text('Copy Referral Message', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () async {
                Navigator.pop(context);
                await Clipboard.setData(ClipboardData(text: shareText));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Message copied to clipboard!'), backgroundColor: AppTheme.success),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}
