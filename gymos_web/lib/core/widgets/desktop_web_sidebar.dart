import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../theme/theme.dart';
import '../services/local_storage.dart';
import '../widgets/app_cached_gym_logo.dart';
import '../../features/authentication/auth_viewmodel.dart';
import '../../features/auth/web_qr_login_screen.dart';
import '../../features/workout/workout_plans_screen.dart';
import '../../features/diet/diet_plans_screen.dart';
import '../../features/more/reports_screen.dart';
import '../../features/subscription/owner_subscription_screen.dart';
import '../../features/dashboard/gym_switcher_bottom_sheet.dart';

class DesktopWebSidebar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTabSelected;
  final int activeMembersCount;
  final int pendingAlertsCount;

  const DesktopWebSidebar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    this.activeMembersCount = 0,
    this.pendingAlertsCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final gymInfo = authVm.gymInfo ?? authVm.storage.getGymInfo() ?? {};
    final gymName = gymInfo['name'] ?? gymInfo['gym_name'] ?? 'GymOS';
    final gymLogo = gymInfo['logo_url'] ?? gymInfo['logo'] ?? '';
    final plan = (gymInfo['plan'] ?? 'Pro').toString().toUpperCase();
    final profileName = authVm.currentProfile?.fullName;
    final String userName = (profileName != null && profileName.isNotEmpty)
        ? profileName
        : (authVm.currentUser?.email?.split('@').first ?? 'Owner');
    final userEmail = authVm.currentProfile?.email ?? authVm.currentUser?.email ?? '';

    return Container(
      width: 260,
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A), // Premium sleek slate-dark sidebar
        border: Border(
          right: BorderSide(color: Color(0xFF1E293B), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. GymOS Branding & Gym Switcher Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7C3AED).withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.fitness_center_rounded, color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'Gym',
                                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
                              ),
                              TextSpan(
                                text: 'OS',
                                style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: const Color(0xFF8B5CF6)),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'Web Portal',
                          style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600, letterSpacing: 0.5),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Active Gym Card with Switcher
                InkWell(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => const GymSwitcherBottomSheet(),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      children: [
                        if (gymLogo.toString().isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: AppCachedGymLogo(
                                gymName: gymName.toString(),
                                logoUrl: gymLogo.toString(),
                                size: 32,
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Text(
                                gymName.isNotEmpty ? gymName[0].toUpperCase() : 'G',
                                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFFA78BFA)),
                              ),
                            ),
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                gymName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C3AED).withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      plan,
                                      style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w700, color: const Color(0xFFA78BFA)),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Owner',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.unfold_more_rounded, size: 18, color: Color(0xFF94A3B8)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFF1E293B)),
          const SizedBox(height: 12),

          // 2. Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildNavItem(
                  context,
                  index: 0,
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  isSelected: currentIndex == 0,
                ),
                _buildNavItem(
                  context,
                  index: 1,
                  icon: Icons.people_rounded,
                  label: 'Members',
                  badge: activeMembersCount > 0 ? '$activeMembersCount' : null,
                  isSelected: currentIndex == 1,
                ),
                _buildNavItem(
                  context,
                  index: 2,
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Finance',
                  isSelected: currentIndex == 2,
                ),
                _buildNavItem(
                  context,
                  index: 3,
                  icon: Icons.badge_rounded,
                  label: 'Staff',
                  isSelected: currentIndex == 3,
                ),
                _buildNavItem(
                  context,
                  index: 4,
                  icon: Icons.grid_view_rounded,
                  label: 'More & Settings',
                  isSelected: currentIndex == 4,
                ),

                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    'MANAGEMENT',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),

                _buildSubItem(
                  context,
                  icon: Icons.fitness_center_outlined,
                  label: 'Workout Plans',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WorkoutPlansScreen())),
                ),
                _buildSubItem(
                  context,
                  icon: Icons.restaurant_menu_outlined,
                  label: 'Diet Plans',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DietPlansScreen())),
                ),
                _buildSubItem(
                  context,
                  icon: Icons.insights_rounded,
                  label: 'Analytics & Reports',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
                ),
                _buildSubItem(
                  context,
                  icon: Icons.stars_rounded,
                  label: 'Subscription & Billing',
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OwnerSubscriptionScreen())),
                ),
              ],
            ),
          ),

          // 3. User Profile & Quick Logout Footer
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: Color(0xFF090D16),
              border: Border(top: BorderSide(color: Color(0xFF1E293B))),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFF7C3AED),
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'O',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      Text(
                        userEmail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 10.5, color: const Color(0xFF94A3B8)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Logout from Web',
                  icon: const Icon(Icons.logout_rounded, size: 18, color: Color(0xFFEF4444)),
                  onPressed: () async {
                    await authVm.storage.setBool('gymos_web_permanent_session', false);
                    await authVm.logout();
                    if (context.mounted) {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(builder: (_) => const WebQrLoginScreen()),
                        (route) => false,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String label,
    required bool isSelected,
    String? badge,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF7C3AED).withOpacity(0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isSelected ? Border.all(color: const Color(0xFF7C3AED).withOpacity(0.35)) : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onTap: () => onTabSelected(index),
        leading: Icon(
          icon,
          size: 20,
          color: isSelected ? const Color(0xFFA78BFA) : const Color(0xFF94A3B8),
        ),
        title: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : const Color(0xFFCBD5E1),
          ),
        ),
        trailing: badge != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF7C3AED) : const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildSubItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        onTap: onTap,
        leading: Icon(icon, size: 18, color: const Color(0xFF64748B)),
        title: Text(
          label,
          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500, color: const Color(0xFF94A3B8)),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFF475569)),
      ),
    );
  }
}
