import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/models/member.dart';
import '../../core/models/membership_plan.dart';
import '../../core/models/finance.dart';
import '../members/members_viewmodel.dart';
import '../finance/finance_viewmodel.dart';
import '../member_app/member_app_viewmodel.dart';

class PaymentDetailScreen extends StatefulWidget {
  final Member member;
  const PaymentDetailScreen({super.key, required this.member});

  @override
  State<PaymentDetailScreen> createState() => _PaymentDetailScreenState();
}

class _PaymentDetailScreenState extends State<PaymentDetailScreen> {
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  String _paymentMethod = 'UPI';
  bool _isProcessing = false;

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _recordPayment() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    setState(() => _isProcessing = true);

    final membersVm = Provider.of<MembersViewModel>(context, listen: false);
    final financeVm = Provider.of<FinanceViewModel>(context, listen: false);

    await membersVm.recordPayment(
      memberId: widget.member.id,
      amount: amount,
      paymentMethod: _paymentMethod,
      category: 'Membership',
      notes: _notesController.text.trim(),
    );

    // Refresh finance statistics/graphs
    financeVm.refresh();

    // Live update the member app payment history
    try {
      final memberAppVm = Provider.of<MemberAppViewModel>(context, listen: false);
      memberAppVm.addPaymentHistoryEntry(
        amount: amount,
        method: _paymentMethod,
        notes: _notesController.text.trim(),
      );
    } catch (_) {}

    setState(() => _isProcessing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Payment of ₹${amount.toStringAsFixed(0)} recorded successfully!'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    // Get fresh member data
    final freshMember = membersVm.allMembers.firstWhere(
      (m) => m.id == widget.member.id,
      orElse: () => widget.member,
    );
    final plan = membersVm.getMemberPlan(freshMember.membershipPlanId);
    final totalFees = (freshMember.extraFields['fees'] as num?)?.toDouble() ?? plan?.price ?? 0.0;
    final paidAmount = totalFees - freshMember.pendingAmount;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Payment Details', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Member info header
            CustomCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppTheme.primaryLight,
                    backgroundImage: freshMember.avatar.isNotEmpty ? NetworkImage(freshMember.avatar) : null,
                    child: freshMember.avatar.isEmpty
                        ? Text(freshMember.name.isNotEmpty ? freshMember.name[0].toUpperCase() : '?', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.primary))
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(freshMember.name, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                        const SizedBox(height: 2),
                        Text(freshMember.phone, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: freshMember.status == 'Active' ? AppTheme.successLight : AppTheme.dangerLight,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      freshMember.status,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: freshMember.status == 'Active' ? AppTheme.success : AppTheme.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Membership Breakdown
            CustomCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Membership Details', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                  const SizedBox(height: 14),
                  _infoRow('Plan', plan?.title ?? 'N/A'),
                  _infoRow('Start Date', freshMember.joinDate),
                  _infoRow('End Date', _getExpiryDate(freshMember, plan)),
                  const Divider(height: 24),
                  _amountRow('Total Amount', '₹${totalFees.toStringAsFixed(0)}', AppTheme.textPrimary),
                  _amountRow('Paid Amount', '₹${paidAmount.toStringAsFixed(0)}', AppTheme.success),
                  _amountRow('Remaining', '₹${freshMember.pendingAmount.toStringAsFixed(0)}', AppTheme.danger),
                  const SizedBox(height: 10),
                  // Progress
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: totalFees > 0 ? (paidAmount / totalFees).clamp(0.0, 1.0) : 0.0,
                      backgroundColor: AppTheme.border,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.success),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${(totalFees > 0 ? (paidAmount / totalFees * 100) : 0).toStringAsFixed(0)}% paid',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Payment History
            CustomCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Payment History', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(12)),
                        child: Text('${paidAmount > 0 ? 1 : 0} Payments', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (paidAmount > 0)
                    _paymentHistoryItem(
                      date: freshMember.joinDate,
                      amount: paidAmount,
                      method: (freshMember.extraFields['paymentMethod'] as String?) ?? 'Cash',
                      notes: 'Initial payment at joining',
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text('No payment history', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Record new payment
            Text('RECORD NEW PAYMENT', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 1)),
            const SizedBox(height: 8),
            CustomCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Amount (₹) *', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Enter payment amount',
                      prefixIcon: const Icon(Icons.currency_rupee, size: 18),
                      suffixIcon: TextButton(
                        onPressed: () {
                          _amountController.text = freshMember.pendingAmount.toStringAsFixed(0);
                        },
                        child: Text('Full Amount', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Text('Payment Method *', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: ['Cash', 'UPI', 'Card', 'Bank Transfer'].map((method) {
                      final isSelected = _paymentMethod == method;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: method != 'Bank Transfer' ? 6 : 0),
                          child: InkWell(
                            onTap: () => setState(() => _paymentMethod = method),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primary : Colors.white,
                                border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                method,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  Text('Notes', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'Add any notes (optional)...'),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _recordPayment,
                      icon: _isProcessing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle_outline, size: 20),
                      label: Text(_isProcessing ? 'Processing...' : 'Add Payment', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  String _getExpiryDate(Member member, MembershipPlan? plan) {
    final exp = member.extraFields['expiryDate'] as String?;
    if (exp != null && exp.isNotEmpty) {
      try {
        return DateFormat('dd MMM yyyy').format(DateTime.parse(exp));
      } catch (_) {}
    }
    if (plan != null && member.joinDate.isNotEmpty) {
      try {
        final join = DateFormat('dd MMM yyyy').parse(member.joinDate);
        return DateFormat('dd MMM yyyy').format(join.add(Duration(days: plan.durationDays)));
      } catch (_) {}
    }
    return 'N/A';
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
          Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _amountRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
          Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: valueColor)),
        ],
      ),
    );
  }

  Widget _paymentHistoryItem({required String date, required double amount, required String method, required String notes}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGray,
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_circle, size: 18, color: AppTheme.success),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('₹${amount.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Text('$method • $notes', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Text(date, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}
