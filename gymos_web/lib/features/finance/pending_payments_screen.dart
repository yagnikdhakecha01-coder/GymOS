import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/models/member.dart';
import '../../core/models/membership_plan.dart';
import '../members/members_viewmodel.dart';
import 'payment_detail_screen.dart';

class PendingPaymentsScreen extends StatefulWidget {
  const PendingPaymentsScreen({super.key});

  @override
  State<PendingPaymentsScreen> createState() => _PendingPaymentsScreenState();
}

class _PendingPaymentsScreenState extends State<PendingPaymentsScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All';

  final List<String> _filters = ['All', 'Due Today', 'Overdue', 'This Week'];

  List<Member> _filterMembers(List<Member> members) {
    var filtered = members.where((m) => m.pendingAmount > 0).toList();

    // Search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((m) =>
        m.name.toLowerCase().contains(q) ||
        m.phone.contains(q) ||
        m.email.toLowerCase().contains(q)
      ).toList();
    }

    // Sort by highest pending first
    filtered.sort((a, b) => b.pendingAmount.compareTo(a.pendingAmount));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final allMembers = membersVm.allMembers;
    final pendingMembers = _filterMembers(allMembers);
    final totalPending = pendingMembers.fold<double>(0.0, (sum, m) => sum + m.pendingAmount);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Pending Payments', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Summary card
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C3AED), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Pending', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text('₹${totalPending.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${pendingMembers.length} Members', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ],
            ),
          ),

          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextFormField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search member...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTheme.radiusInput), borderSide: const BorderSide(color: AppTheme.border)),
              ),
            ),
          ),

          // Filter chips
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = filter == _selectedFilter;
                return ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedFilter = filter),
                  selectedColor: AppTheme.primary,
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppTheme.textSecondary,
                  ),
                  backgroundColor: Colors.white,
                  side: BorderSide(color: isSelected ? AppTheme.primary : AppTheme.border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Member list
          Expanded(
            child: pendingMembers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline, size: 56, color: AppTheme.success.withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text('No Pending Payments', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        const SizedBox(height: 4),
                        Text('All members are up to date!', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted)),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: pendingMembers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final member = pendingMembers[index];
                      final plan = membersVm.getMemberPlan(member.membershipPlanId);
                      return _buildMemberPaymentCard(member, plan);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberPaymentCard(Member member, MembershipPlan? plan) {
    final totalFees = (member.extraFields['fees'] as num?)?.toDouble() ?? plan?.price ?? 0.0;
    final paidAmount = totalFees - member.pendingAmount;

    return CustomCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PaymentDetailScreen(member: member)),
          );
        },
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primaryLight,
                    backgroundImage: member.avatar.isNotEmpty ? NetworkImage(member.avatar) : null,
                    child: member.avatar.isEmpty
                        ? Text(member.name.isNotEmpty ? member.name[0].toUpperCase() : '?', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppTheme.primary))
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(member.name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          plan?.title ?? 'No Plan',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  // Pending badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.dangerLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '₹${member.pendingAmount.toStringAsFixed(0)}',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.danger),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: totalFees > 0 ? (paidAmount / totalFees).clamp(0.0, 1.0) : 0.0,
                  backgroundColor: AppTheme.border,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    paidAmount / (totalFees > 0 ? totalFees : 1) > 0.7 ? AppTheme.success : AppTheme.warning,
                  ),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _miniStat('Total', '₹${totalFees.toStringAsFixed(0)}'),
                  _miniStat('Paid', '₹${paidAmount.toStringAsFixed(0)}'),
                  _miniStat('Remaining', '₹${member.pendingAmount.toStringAsFixed(0)}'),
                  Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
        Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
      ],
    );
  }
}
