import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../members/members_viewmodel.dart';
import '../../members/member_profile_screen.dart';
import '../../members/add_member_wizard_screen.dart';
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
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddMemberWizardScreen()),
                ).then((_) {
                  vm.logActivity('Member Added', 'members');
                  membersVm.fetchMembers();
                });
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

    final membersVm = Provider.of<MembersViewModel>(context, listen: false);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        final bool isActive = member.status.toLowerCase() == 'active';
        
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
              radius: 20,
              backgroundImage: NetworkImage(member.avatar.isNotEmpty ? member.avatar : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=200'),
            ),
            title: Text(
              member.name,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  member.phone,
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                ),
                Text(
                  'Membership: ${membersVm.getMemberPlan(member.membershipPlanId)?.title ?? 'None'}',
                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.primary, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isActive ? Colors.green : Colors.grey).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive ? 'Active' : member.status,
                style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: isActive ? Colors.green : Colors.grey),
              ),
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MemberProfileScreen(member: member),
                ),
              ).then((_) {
                // If they edit a member or take action, log it
                vm.logActivity('Member Profile Viewed', 'members', targetMember: member.name);
              });
            },
          ),
        );
      },
    );
  }
}
