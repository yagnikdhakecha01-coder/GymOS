import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/models/trial_member.dart';
import 'trial_members_viewmodel.dart';
import 'add_trial_member_screen.dart';
import 'trial_member_details_screen.dart';
import 'add_member_wizard_screen.dart';
import '../authentication/auth_viewmodel.dart';

class TrialMembersScreen extends StatefulWidget {
  final String? initialFilter;
  const TrialMembersScreen({super.key, this.initialFilter});

  @override
  State<TrialMembersScreen> createState() => _TrialMembersScreenState();
}

class _TrialMembersScreenState extends State<TrialMembersScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialFilter != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Provider.of<TrialMembersViewModel>(context, listen: false).setFilter(widget.initialFilter!);
        }
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddTrialScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddTrialMemberScreen()),
    );
  }

  Widget _buildFilterChip(String label, TrialMembersViewModel vm) {
    final isSelected = vm.selectedFilter == label;
    return GestureDetector(
      onTap: () => vm.setFilter(label),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : Colors.white,
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _getStatusBadge(String status) {
    Color bg;
    Color text;
    IconData icon;

    switch (status) {
      case 'Converted':
        bg = const Color(0xFFEEF2FF);
        text = const Color(0xFF4F46E5);
        icon = Icons.swap_horiz_rounded;
        break;
      case 'Expired':
        bg = const Color(0xFFFEF2F2);
        text = const Color(0xFFEF4444);
        icon = Icons.cancel_outlined;
        break;
      default: // Active
        bg = const Color(0xFFE6F4EA);
        text = const Color(0xFF16A34A);
        icon = Icons.check_circle_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bg, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: text),
          const SizedBox(width: 4),
          Text(
            status,
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: text),
          ),
        ],
      ),
    );
  }

  void _convertTrialToMember(BuildContext context, TrialMember trial) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddMemberWizardScreen(
          initialName: trial.name,
          initialPhone: trial.phone,
          initialAvatarUrl: trial.avatar,
          sourceTrialId: trial.id,
          trialPaymentAmount: trial.trialType == 'Paid' ? trial.receivedAmount : 0.0,
          trialStartDate: trial.startDate,
          trialStartTime: trial.createdAt,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<TrialMembersViewModel>(context);
    final allTrials = vm.filteredTrials;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Trial Members', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded, color: AppTheme.primary, size: 24),
            onPressed: () => _showAddTrialScreen(context),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              color: Colors.white,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                  border: Border.all(color: AppTheme.border),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: vm.setSearchQuery,
                  decoration: const InputDecoration(
                    hintText: 'Search by name or mobile number...',
                    prefixIcon: Icon(Icons.search, size: 20, color: AppTheme.textSecondary),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),

            // Filters horizontal list
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildFilterChip('All', vm),
                    _buildFilterChip('Expiring / Expired', vm),
                    _buildFilterChip('Active', vm),
                    _buildFilterChip('Expired', vm),
                    _buildFilterChip('Converted', vm),
                    _buildFilterChip('Free Trial', vm),
                    _buildFilterChip('Paid Trial', vm),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // Trial Members List
            Expanded(
              child: allTrials.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.assignment_ind_outlined, size: 48, color: AppTheme.textMuted.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No Trials Found',
                            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try adjusting your filters or query.',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: allTrials.length,
                      itemBuilder: (context, index) {
                        final trial = allTrials[index];
                        final startText = DateFormat('dd MMM').format(DateTime.parse(trial.startDate));
                        final endText = DateFormat('dd MMM yyyy').format(DateTime.parse(trial.endDate));
                        final status = trial.calculatedStatus;

                        return CustomCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => TrialMemberDetailsScreen(trial: trial)),
                            );
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Profile image
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      color: AppTheme.primaryLight,
                                      child: Image.network(
                                        trial.avatar.isNotEmpty ? trial.avatar : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=200',
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Center(
                                          child: Text(
                                            trial.name.isNotEmpty ? trial.name[0].toUpperCase() : '?',
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Basic Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          trial.name,
                                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          trial.phone,
                                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.calendar_month_outlined, size: 12, color: AppTheme.textMuted),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$startText - $endText (${trial.trialDays} days)',
                                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Status & Type Badges
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      _getStatusBadge(status),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: trial.trialType == 'Paid' ? const Color(0xFFFFF7ED) : const Color(0xFFF0FDF4),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: trial.trialType == 'Paid' ? const Color(0xFFFED7AA) : const Color(0xFFBBF7D0),
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Text(
                                          trial.trialType == 'Paid' ? 'Paid (₹${trial.receivedAmount.toStringAsFixed(0)})' : 'Free Trial',
                                          style: GoogleFonts.inter(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: trial.trialType == 'Paid' ? const Color(0xFFC2410C) : const Color(0xFF15803D),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              const SizedBox(height: 8),

                              // Quick Actions
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AddTrialMemberScreen(editTrial: trial),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.edit_outlined, size: 14),
                                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.textSecondary,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (status != 'Converted')
                                    ElevatedButton.icon(
                                      onPressed: () => _convertTrialToMember(context, trial),
                                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 14, color: Colors.white),
                                      label: const Text('Convert To Member', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.primary,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                        minimumSize: const Size(0, 32),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    );
  }
}
