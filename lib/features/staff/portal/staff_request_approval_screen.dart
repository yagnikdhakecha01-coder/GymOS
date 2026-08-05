import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import '../../../core/repository/gym_repository.dart';
import '../../authentication/auth_viewmodel.dart';
import '../staff_viewmodel.dart';
import '../../../core/models/staff.dart';

class StaffRequestApprovalScreen extends StatefulWidget {
  final int initialTabIndex; // 0 for Leaves, 1 for Advances
  const StaffRequestApprovalScreen({super.key, this.initialTabIndex = 0});

  @override
  State<StaffRequestApprovalScreen> createState() => _StaffRequestApprovalScreenState();
}

class _StaffRequestApprovalScreenState extends State<StaffRequestApprovalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _loadGymRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadGymRequests() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final repo = Provider.of<GymRepository>(context, listen: false);
      final staffVm = Provider.of<StaffViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];

      if (gymId != null) {
        await Future.wait([
          repo.fetchGymLeaveRequestsFromSupabase(gymId),
          repo.fetchGymSalaryAdvancesFromSupabase(gymId),
          staffVm.fetchStaff(),
        ]);
      }
    } catch (e) {
      print('Error loading gym request approvals: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = Provider.of<GymRepository>(context);
    final staffVm = Provider.of<StaffViewModel>(context);

    // Filter pending leaves
    final pendingLeaves = repo.leaveRequests.where((l) => l['status'] == 'Pending').toList();

    // Filter pending advances
    final pendingAdvances = repo.salaryAdvances.where((a) => a['status'] == 'Pending').toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Request Approvals',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary),
            onPressed: _loadGymRequests,
          ),
        ],
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
          tabs: [
            Tab(text: 'Leaves (${pendingLeaves.length})'),
            Tab(text: 'Advances (${pendingAdvances.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildLeavesTab(context, repo, staffVm, pendingLeaves),
                _buildAdvancesTab(context, repo, staffVm, pendingAdvances),
              ],
            ),
    );
  }

  Widget _buildLeavesTab(
    BuildContext context,
    GymRepository repo,
    StaffViewModel staffVm,
    List<Map<String, dynamic>> pendingLeaves,
  ) {
    if (pendingLeaves.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadGymRequests,
        color: AppTheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: _buildEmptyState('No pending leave requests'),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGymRequests,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: pendingLeaves.length,
        itemBuilder: (context, index) {
          final leave = pendingLeaves[index];
          final staffId = leave['staff_id'];
          final matchingStaff = repo.getStaff().where((s) => s.id == staffId || s.userId == staffId).toList();
          final Staff? staff = matchingStaff.isNotEmpty ? matchingStaff.first : null;

          final start = DateTime.tryParse(leave['start_date'] ?? '');
          final end = DateTime.tryParse(leave['end_date'] ?? '');
          final dateStr = (start != null && end != null)
              ? '${DateFormat('dd MMM yyyy').format(start)} - ${DateFormat('dd MMM yyyy').format(end)}'
              : 'Unknown Date';
          final totalDays = (start != null && end != null)
              ? end.difference(start).inDays + 1
              : 1;

          return CustomCard(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(
                        (staff?.avatar != null && staff!.avatar.isNotEmpty)
                            ? staff.avatar
                            : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            staff?.name ?? 'Staff Member',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          Text(
                            staff?.role ?? 'Staff',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '$totalDays ${totalDays == 1 ? 'Day' : 'Days'}',
                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: AppTheme.border, height: 1),
                const SizedBox(height: 12),
                Text(
                  'Leave Type: ${leave['leave_type'] ?? 'Casual'}',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.primary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Duration: $dateStr',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Reason:',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                ),
                Text(
                  leave['reason'] ?? 'N/A',
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _updateLeave(staffVm, leave['id'], 'Rejected'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(color: AppTheme.danger),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Reject', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _updateLeave(staffVm, leave['id'], 'Approved'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Approve', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAdvancesTab(
    BuildContext context,
    GymRepository repo,
    StaffViewModel staffVm,
    List<Map<String, dynamic>> pendingAdvances,
  ) {
    if (pendingAdvances.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadGymRequests,
        color: AppTheme.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: _buildEmptyState('No pending salary advances'),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadGymRequests,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: pendingAdvances.length,
        itemBuilder: (context, index) {
          final adv = pendingAdvances[index];
          final staffId = adv['staff_id'];
          final matchingStaff = repo.getStaff().where((s) => s.id == staffId || s.userId == staffId).toList();
          final Staff? staff = matchingStaff.isNotEmpty ? matchingStaff.first : null;

          final amt = (adv['advance_amount'] as num?)?.toDouble() ?? (adv['amount'] as num?)?.toDouble() ?? 0.0;
          final dateStr = adv['given_date'] != null
              ? DateFormat('dd MMM yyyy').format(DateTime.parse(adv['given_date']))
              : 'Unknown Date';

          return CustomCard(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(
                        (staff?.avatar != null && staff!.avatar.isNotEmpty)
                            ? staff.avatar
                            : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=100',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            staff?.name ?? 'Staff Member',
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          Text(
                            staff?.role ?? 'Staff',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${amt.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: AppTheme.border, height: 1),
                const SizedBox(height: 12),
                Text(
                  'Month: ${adv['salary_month'] ?? 'Current Month'}',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Requested Date: $dateStr',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Reason:',
                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                ),
                Text(
                  adv['reason'] ?? 'N/A',
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _updateAdvance(staffVm, adv['id'], 'Rejected'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.danger,
                          side: const BorderSide(color: AppTheme.danger),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Reject', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _updateAdvance(staffVm, adv['id'], 'Approved'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text('Approve', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.mark_email_read_outlined, size: 48, color: AppTheme.textMuted),
          const SizedBox(height: 16),
          Text(
            message,
            style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> _updateLeave(StaffViewModel vm, String id, String status) async {
    setState(() => _isLoading = true);
    try {
      await vm.updateLeaveStatus(id, status);
      if (mounted) {
        final repo = Provider.of<GymRepository>(context, listen: false);
        repo.triggerBackgroundSync();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Leave request $status successfully!'), backgroundColor: AppTheme.success),
        );
      }
      await _loadGymRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateAdvance(StaffViewModel vm, String id, String status) async {
    setState(() => _isLoading = true);
    try {
      await vm.updateSalaryAdvanceStatus(id, status);
      if (mounted) {
        final repo = Provider.of<GymRepository>(context, listen: false);
        repo.triggerBackgroundSync();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Advance request $status successfully!'), backgroundColor: AppTheme.success),
        );
      }
      await _loadGymRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
