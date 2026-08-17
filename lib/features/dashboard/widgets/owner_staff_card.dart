import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/models/staff.dart';
import '../../../core/widgets/app_cached_avatar.dart';

class OwnerStaffCard extends StatelessWidget {
  final Map<String, dynamic> staffData;
  final VoidCallback? onTap;

  const OwnerStaffCard({
    super.key,
    required this.staffData,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final String name = staffData['name'] ?? 'Staff Member';
    final String role = staffData['role'] ?? 'Staff';
    final String avatar = staffData['avatar'] ?? '';
    final String status = staffData['status'] ?? 'Active';
    final double salaryPending = (staffData['salary_pending'] as num?)?.toDouble() ?? 0.0;
    final int presentDays = (staffData['present_days'] as num?)?.toInt() ?? 0;
    final int leaveDays = (staffData['leave_days'] as num?)?.toInt() ?? 0;
    final int earlyExitCount = (staffData['early_exit_count'] as num?)?.toInt() ?? 0;
    final String lastCheckIn = staffData['last_check_in'] ?? 'N/A';
    final bool isCheckedIn = staffData['is_checked_in'] == true;
    final String currentDateStr = staffData['current_date_str'] ?? DateFormat('dd MMM yyyy').format(DateTime.now());
    final bool isSalaryPaid = staffData['is_salary_paid'] == true;
    final double paidAmount = (staffData['paid_amount'] as num?)?.toDouble() ?? 0.0;

    final formattedSalary = NumberFormat('#,##,###').format(isSalaryPaid ? paidAmount : salaryPending);
    final bool isSmallScreen = MediaQuery.of(context).size.width <= 360;

    Widget buildSalaryBadge() {
      final Color badgeBg = isSalaryPaid ? const Color(0xFFE6FDF4) : const Color(0xFFFFF0F0);
      final Color badgeBorder = isSalaryPaid ? const Color(0xFFA7F3D0) : const Color(0xFFFFD4D4);
      final Color iconColor = isSalaryPaid ? const Color(0xFF10B981) : const Color(0xFFDC2626);
      final Color amountColor = isSalaryPaid ? const Color(0xFF047857) : const Color(0xFFDC2626);
      final Color labelColor = isSalaryPaid ? const Color(0xFF059669) : const Color(0xFFEF4444);
      final String labelText = isSalaryPaid ? 'Salary Paid' : 'Salary Pending';
      final IconData badgeIcon = isSalaryPaid ? Icons.check_circle_outline : Icons.account_balance_wallet_outlined;

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: badgeBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: badgeBorder, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              badgeIcon,
              size: 12,
              color: iconColor,
            ),
            const SizedBox(width: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '₹$formattedSalary',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: amountColor,
                  ),
                ),
                if (!isSmallScreen)
                  Text(
                    labelText,
                    style: GoogleFonts.inter(
                      fontSize: 8,
                      fontWeight: FontWeight.w500,
                      color: labelColor,
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.6), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── TOP SECTION: Avatar, Name/Role & Salary Pending Badge ──
            Row(
              children: [
                // Avatar Circle (Instant cached render)
                AppCachedAvatar(
                  imageUrl: avatar,
                  name: name,
                  size: 54,
                ),
                const SizedBox(width: 14),

                // Name & Role
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.person_outline_rounded,
                            size: 15,
                            color: Color(0xFF7C3AED),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              role,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if ((salaryPending > 0 || isSalaryPaid) && isSmallScreen) ...[
                        const SizedBox(height: 6),
                        buildSalaryBadge(),
                      ],
                    ],
                  ),
                ),

                // Salary Pending/Paid Badge Container (only on big screens)
                if ((salaryPending > 0 || isSalaryPaid) && !isSmallScreen) ...[
                  buildSalaryBadge(),
                  const SizedBox(width: 8),
                ],

                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textMuted,
                  size: 22,
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 14),

            // ── MIDDLE METRICS ROW ──
            Row(
              children: [
                // 1. Present Days
                Expanded(
                  child: _buildMetricTile(
                    iconBg: const Color(0xFFE6F4EA),
                    iconColor: const Color(0xFF16A34A),
                    icon: Icons.calendar_month_rounded,
                    value: '$presentDays',
                    valueColor: const Color(0xFF15803D),
                    label: 'Present Days',
                  ),
                ),
                _buildVerticalDivider(),

                // 2. Leave Days
                Expanded(
                  child: _buildMetricTile(
                    iconBg: const Color(0xFFFFF7ED),
                    iconColor: const Color(0xFFEA580C),
                    icon: Icons.beach_access_rounded,
                    value: '$leaveDays',
                    valueColor: const Color(0xFFC2410C),
                    label: 'Leave',
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 12),

            // ── BOTTOM FOOTER: Attendance Dot | Date & Active Status ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Attendance Status
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCheckedIn ? const Color(0xFF16A34A) : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isCheckedIn ? 'Checked In' : 'Not Checked In',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isCheckedIn ? const Color(0xFF15803D) : AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Active Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: status.toLowerCase() == 'active' ? const Color(0xFFE6F4EA) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        status.toLowerCase() == 'active' ? Icons.check : Icons.circle,
                        size: 10,
                        color: status.toLowerCase() == 'active' ? const Color(0xFF16A34A) : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 90),
                        child: Text(
                          status,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: status.toLowerCase() == 'active' ? const Color(0xFF15803D) : AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required Color iconBg,
    required Color iconColor,
    required IconData icon,
    required String value,
    required Color valueColor,
    required String label,
    bool isValueSmall = false,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: isValueSmall ? 11.5 : 15,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 28,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFFE2E8F0),
    );
  }
}
