import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/sparkline.dart';
import 'members_viewmodel.dart';
import '../../core/models/member.dart';
import '../../core/navigation/app_router.dart';
import 'member_profile_screen.dart';
import 'add_member_wizard_screen.dart';
import '../attendance/attendance_viewmodel.dart';
import '../../core/theme/responsive.dart';

class MembersScreen extends StatelessWidget {
  const MembersScreen({super.key});

  void _showAddMemberSheet(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddMemberWizardScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final attendanceVm = Provider.of<AttendanceViewModel>(context);
    final allMembers = membersVm.filteredMembers;
    final totalCount = membersVm.allMembers.length;
    final activeCount = membersVm.allMembers.where((m) => m.status == 'Active').length;
    final inactiveCount = membersVm.allMembers.where((m) => m.status == 'Inactive').length;
    final trialCount = membersVm.allMembers.where((m) => m.status == 'Trial').length;

    final checkInRecords = attendanceVm.attendanceHistory.where((r) => r.status == 'Present').length;
    final totalPending = membersVm.allMembers.fold<double>(0, (sum, m) => sum + m.pendingAmount);
    final bool canScroll = allMembers.length >= 4;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: NestedScrollView(
          physics: canScroll ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    // Mockup Header Row
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppTheme.pagePadding, 16, AppTheme.pagePadding, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Members',
                                style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                              Text(
                                'All members overview',
                                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.search_rounded, color: AppTheme.textPrimary, size: 24),
                                onPressed: () {},
                              ),
                              IconButton(
                                icon: const Icon(Icons.filter_list_rounded, color: AppTheme.textPrimary, size: 24),
                                onPressed: () {},
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => _showAddMemberSheet(context),
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add, color: Colors.white, size: 22),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),

                    // Mockup 2x2 Sparkline Stat Grid
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
                      child: ResponsiveGrid(
                        crossAxisCountMobile: 2,
                        crossAxisCountTablet: 4,
                        spacing: 12,
                        runSpacing: 12,
                        childAspectRatio: context.selectValue(mobile: 1.35, smallMobile: 1.05, tablet: 1.6),
                        children: [
                          // Attendance stat
                          _buildSparklineStat(
                            title: 'Attendance',
                            value: '$checkInRecords',
                            subtitle: 'Check-ins today',
                            trend: '↑ 0%',
                            trendLabel: 'vs yesterday',
                            trendColor: AppTheme.success,
                            sparklineData: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, checkInRecords.toDouble()],
                            sparklineColor: AppTheme.primary,
                          ),
                          // Active Members stat
                          _buildSparklineStat(
                            title: 'Active Members',
                            value: '$activeCount',
                            subtitle: 'Total active members',
                            trend: '↑ 0%',
                            trendLabel: 'vs last month',
                            trendColor: AppTheme.success,
                            sparklineData: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, activeCount.toDouble()],
                            sparklineColor: AppTheme.success,
                          ),
                          // Pending Amount stat
                          _buildSparklineStat(
                            title: 'Pending Amount',
                            value: '₹ ${NumberFormat('#,##,###').format(totalPending)}',
                            subtitle: 'Total pending',
                            trend: '↑ 0%',
                            trendLabel: 'vs last month',
                            trendColor: AppTheme.danger,
                            sparklineData: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, totalPending.toDouble()],
                            sparklineColor: AppTheme.warning,
                          ),
                          // PT Members stat
                          _buildSparklineStat(
                            title: 'PT Members',
                            value: '$trialCount',
                            subtitle: 'Personal training',
                            trend: '↑ 0%',
                            trendLabel: 'vs last month',
                            trendColor: AppTheme.success,
                            sparklineData: [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, trialCount.toDouble()],
                            sparklineColor: AppTheme.info,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ];
          },
          body: Column(
            children: [
              // Tab bar switcher
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
                child: Row(
                  children: [
                    _buildMockTab('All ($totalCount)', membersVm.selectedFilter == 'All', () {
                      membersVm.setFilter('All');
                    }),
                    _buildMockTab('Active ($activeCount)', membersVm.selectedFilter == 'Active', () {
                      membersVm.setFilter('Active');
                    }),
                    _buildMockTab('Inactive ($inactiveCount)', membersVm.selectedFilter == 'Inactive', () {
                      membersVm.setFilter('Inactive');
                    }),
                    _buildMockTab('Trial ($trialCount)', membersVm.selectedFilter == 'Trial', () {
                      membersVm.setFilter('Trial');
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Member Cards List
              Expanded(
                child: allMembers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 48, color: AppTheme.textMuted.withOpacity(0.5)),
                            const SizedBox(height: 12),
                            Text(
                              'No Members Found',
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Members added to this category will appear here.',
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        physics: canScroll ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
                        itemCount: allMembers.length,
                        itemBuilder: (context, index) {
                          final member = allMembers[index];
                          final isTrial = member.status == 'Trial';
                          final bool isPaid = member.paymentStatus.toLowerCase() == 'paid' || member.pendingAmount <= 0;
                          
                          String nextDueStr = 'N/A';
                          final exp = member.extraFields['expiryDate'] as String?;
                          if (exp != null && exp.isNotEmpty) {
                            try {
                              final parsed = DateTime.parse(exp);
                              nextDueStr = DateFormat('dd MMM yyyy').format(parsed);
                            } catch (_) {
                              nextDueStr = exp;
                            }
                          }
                          
                          return CustomCard(
                            margin: const EdgeInsets.only(bottom: 12),
                            onTap: () {
                              Navigator.push(context, AppRouter.slideRoute(MemberProfileScreen(member: member)));
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        color: AppTheme.primaryLight,
                                        child: Image.network(
                                          member.avatar.isNotEmpty ? member.avatar : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=200',
                                          fit: BoxFit.cover,
                                          errorBuilder: (c, e, s) => Center(child: Text(member.name[0], style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary))),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            member.name,
                                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            member.phone,
                                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            isTrial ? 'Trial Subscription' : 'Next Due: $nextDueStr',
                                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isPaid
                                            ? AppTheme.successLight
                                            : Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isPaid ? '🟢 Payment Done' : '🔴 Pending Payment',
                                        style: TextStyle(
                                          color: isPaid
                                              ? AppTheme.success
                                              : Colors.redAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 20),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Member Status',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: member.status == 'Active'
                                            ? const Color(0xFFE6F4EA)
                                            : (member.status == 'Pending Activation'
                                                ? Colors.orange.withOpacity(0.1)
                                                : Colors.grey.withOpacity(0.1)),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            member.status == 'Active' ? Icons.check : Icons.circle,
                                            size: 10,
                                            color: member.status == 'Active'
                                                ? const Color(0xFF16A34A)
                                                : (member.status == 'Pending Activation'
                                                    ? Colors.orange
                                                    : Colors.grey),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            member.status,
                                            style: GoogleFonts.inter(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w700,
                                              color: member.status == 'Active' ? const Color(0xFF15803D) : AppTheme.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMockTab(String title, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppTheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildSparklineStat({
    required String title,
    required String value,
    required String subtitle,
    required String trend,
    required String trendLabel,
    required Color trendColor,
    required List<double> sparklineData,
    required Color sparklineColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Icon container placeholder resembling mockup
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: sparklineColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  title.contains('Attendance') 
                      ? Icons.calendar_today_rounded 
                      : (title.contains('Active') 
                          ? Icons.people_rounded 
                          : (title.contains('Pending') ? Icons.currency_rupee_rounded : Icons.person_add_alt_1_rounded)),
                  color: sparklineColor,
                  size: 16,
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: Text(
                    title,
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Sparkline curve
              MiniSparkline(data: sparklineData, color: sparklineColor),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Text(
                trend,
                style: GoogleFonts.inter(fontSize: 10, color: trendColor, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  trendLabel,
                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AddMemberSheet extends StatefulWidget {
  const AddMemberSheet({super.key});

  @override
  State<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<AddMemberSheet> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  String _selectedPlanId = '1';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context, listen: false);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Register New Member', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            Text('Full Name', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _nameController, decoration: const InputDecoration(hintText: 'e.g. Aman Gupta')),
            const SizedBox(height: 12),

            Text('Email Address', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _emailController, decoration: const InputDecoration(hintText: 'e.g. aman@gmail.com')),
            const SizedBox(height: 12),

            Text('Phone Number', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _phoneController, decoration: const InputDecoration(hintText: 'e.g. 98234 56789')),
            const SizedBox(height: 12),

            Text('Membership Plan', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedPlanId,
              items: const [
                DropdownMenuItem(value: '1', child: Text('Silver Monthly Plan (₹1,500)')),
                DropdownMenuItem(value: '2', child: Text('Gold Quarterly Plan (₹4,000)')),
                DropdownMenuItem(value: '3', child: Text('Platinum Annual Plan (₹12,000)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedPlanId = val);
              },
            ),
            const SizedBox(height: 20),

            CustomButton(
              text: 'Save Member',
              onPressed: () async {
                if (_nameController.text.isEmpty || _emailController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter name and email'), backgroundColor: AppTheme.danger),
                  );
                  return;
                }
                await membersVm.addMember(
                  name: _nameController.text,
                  email: _emailController.text,
                  phone: _phoneController.text,
                  joinDate: '16 Jul 2026',
                  membershipPlanId: _selectedPlanId,
                  ptMember: false,
                  ptTrainer: '',
                  medicalDetails: 'None',
                  notes: '',
                  pendingAmount: 0.0,
                );

                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Member added successfully!'), backgroundColor: AppTheme.success),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
