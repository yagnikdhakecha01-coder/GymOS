import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import '../../../core/navigation/app_router.dart';
import '../../../core/models/member.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../members/members_viewmodel.dart';
import '../../members/member_profile_screen.dart';
import '../../members/add_member_wizard_screen.dart';
import '../../members/add_trial_member_screen.dart';
import '../../members/trial_members_viewmodel.dart';
import '../../../core/widgets/add_member_selection_sheet.dart';
import '../receptionist_viewmodel.dart';

class ReceptionistMembersScreen extends StatefulWidget {
  const ReceptionistMembersScreen({super.key});

  @override
  State<ReceptionistMembersScreen> createState() => _ReceptionistMembersScreenState();
}

class _ReceptionistMembersScreenState extends State<ReceptionistMembersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<MembersViewModel>(context, listen: false).fetchMembers();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<ReceptionistViewModel>(context);
    final membersVm = Provider.of<MembersViewModel>(context);
    final allMembers = membersVm.allMembers;

    // Filter members based on search
    final query = _searchQuery.trim().toLowerCase();
    final searchedMembers = allMembers.where((m) {
      return m.name.toLowerCase().contains(query) || m.phone.contains(query);
    }).toList();

    // Counts
    final total = searchedMembers.length;
    final active = searchedMembers.where((m) => m.status.toLowerCase() == 'active').length;
    final inactive = searchedMembers.where((m) => m.status.toLowerCase() == 'inactive' || m.status.toLowerCase() == 'expired').length;
    final trial = searchedMembers.where((m) => m.status.toLowerCase() == 'trial' || m.status.toLowerCase() == 'pending activation').length;

    final canAddMember = vm.hasPermission('add_member');

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Members',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
        actions: [
          if (canAddMember)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primary, size: 24),
              onPressed: () {
                AddMemberSelectionSheet.show(
                  context,
                  onNormalSelected: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddMemberWizardScreen()),
                    ).then((_) {
                      vm.logActivity('Member Added', 'members');
                      membersVm.fetchMembers();
                    });
                  },
                  onTrialSelected: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddTrialMemberScreen()),
                    ).then((_) {
                      vm.logActivity('Trial Member Added', 'members');
                      Provider.of<TrialMembersViewModel>(context, listen: false).fetchTrialMembers();
                    });
                  },
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Search & Filter header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                      },
                      decoration: const InputDecoration(
                        hintText: 'Search members...',
                        prefixIcon: Icon(Icons.search, size: 20, color: AppTheme.textSecondary),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.filter_list_rounded, color: AppTheme.textPrimary),
                ),
              ],
            ),
          ),

          // Dynamic Stats Summary Cards
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: _buildSmallStatCard(
                    title: 'Total Members',
                    value: '$total',
                    label: 'All Members',
                    color: AppTheme.primary,
                    icon: Icons.people_outline_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSmallStatCard(
                    title: 'Active Members',
                    value: '$active',
                    label: 'Active',
                    color: Colors.green,
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ),
              ],
            ),
          ),

          // Tab Bar Headers
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: AppTheme.primary,
              unselectedLabelColor: AppTheme.textSecondary,
              indicatorColor: AppTheme.primary,
              indicatorWeight: 2,
              tabs: [
                Tab(text: 'All ($total)'),
                Tab(text: 'Active ($active)'),
                Tab(text: 'Inactive ($inactive)'),
                Tab(text: 'Trial ($trial)'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMembersList(context, searchedMembers, vm),
                _buildMembersList(context, searchedMembers.where((m) => m.status.toLowerCase() == 'active').toList(), vm),
                _buildMembersList(context, searchedMembers.where((m) => m.status.toLowerCase() == 'inactive' || m.status.toLowerCase() == 'expired').toList(), vm),
                _buildMembersList(context, searchedMembers.where((m) => m.status.toLowerCase() == 'trial' || m.status.toLowerCase() == 'pending activation').toList(), vm),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallStatCard({
    required String title,
    required String value,
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ),
                Text(
                  title,
                  style: GoogleFonts.inter(fontSize: 9, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMemberPaymentBadge(Member member) {
    final double pending = member.pendingAmount;
    final bool isPaid = pending <= 0 || member.paymentStatus.toLowerCase() == 'paid';
    final Color badgeBg = isPaid ? const Color(0xFFE6FDF4) : const Color(0xFFFFF0F0);
    final Color badgeBorder = isPaid ? const Color(0xFFA7F3D0) : const Color(0xFFFFD4D4);
    final Color iconColor = isPaid ? const Color(0xFF10B981) : const Color(0xFFDC2626);
    final Color amountColor = isPaid ? const Color(0xFF047857) : const Color(0xFFDC2626);
    final Color labelColor = isPaid ? const Color(0xFF059669) : const Color(0xFFEF4444);
    final String labelText = isPaid ? 'Fees Paid' : 'Fees Pending';
    final IconData badgeIcon = isPaid ? Icons.check_circle_outline : Icons.account_balance_wallet_outlined;
    final String formattedAmount = isPaid ? 'Done' : '₹${NumberFormat('#,##,###').format(pending.abs())}';

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
                formattedAmount,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                ),
              ),
              Text(
                labelText,
                style: GoogleFonts.inter(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: labelColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMembersList(BuildContext context, List members, ReceptionistViewModel vm) {
    if (members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline_rounded, size: 48, color: AppTheme.textSecondary.withOpacity(0.5)),
              const SizedBox(height: 12),
              Text(
                'No members found.',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index] as Member;
        final isTrial = member.status == 'Trial';

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
                        errorBuilder: (c, e, s) => Center(child: Text(member.name.isNotEmpty ? member.name[0] : 'M', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary))),
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
                  const SizedBox(width: 8),
                  if (!isTrial) ...[
                    _buildMemberPaymentBadge(member),
                    const SizedBox(width: 6),
                  ],
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
                    child: Text(
                      member.status,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: member.status == 'Active'
                            ? const Color(0xFF137333)
                            : (member.status == 'Pending Activation'
                                ? Colors.orange
                                : Colors.grey.shade700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
