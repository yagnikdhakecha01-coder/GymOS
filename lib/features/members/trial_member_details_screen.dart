import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/models/trial_member.dart';
import 'add_trial_member_screen.dart';
import 'add_member_wizard_screen.dart';

class TrialMemberDetailsScreen extends StatelessWidget {
  final TrialMember trial;

  const TrialMemberDetailsScreen({super.key, required this.trial});

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: text),
          const SizedBox(width: 6),
          Text(
            status,
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: text),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = trial.calculatedStatus;
    final startDateFormatted = DateFormat('dd MMM yyyy').format(DateTime.parse(trial.startDate));
    final endDateFormatted = DateFormat('dd MMM yyyy').format(DateTime.parse(trial.endDate));
    
    String? payDateFormatted;
    if (trial.paymentDate != null) {
      payDateFormatted = DateFormat('dd MMM yyyy').format(DateTime.parse(trial.paymentDate!));
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Trial Details', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Profile card
                    CustomCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Center(
                            child: CircleAvatar(
                              radius: 48,
                              backgroundColor: AppTheme.primaryLight,
                              backgroundImage: trial.avatar.isNotEmpty ? NetworkImage(trial.avatar) : null,
                              child: trial.avatar.isEmpty
                                  ? Icon(Icons.person, size: 48, color: AppTheme.primary)
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            trial.name,
                            style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            trial.phone,
                            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 12),
                          _getStatusBadge(status),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Trial details card
                    CustomCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TRIAL DETAILS',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
                          ),
                          const SizedBox(height: 8),
                          _buildDetailRow('Trial Type', trial.trialType == 'Paid' ? 'Paid Trial' : 'Free Trial', Icons.card_membership_outlined),
                          const Divider(height: 1),
                          _buildDetailRow('Trial Duration', '${trial.trialDays} Days', Icons.timer_outlined),
                          const Divider(height: 1),
                          _buildDetailRow('Start Date', startDateFormatted, Icons.calendar_today_outlined),
                          const Divider(height: 1),
                          _buildDetailRow('End Date', endDateFormatted, Icons.calendar_month_outlined),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Payment summary (Paid Trial only)
                    if (trial.trialType == 'Paid')
                      CustomCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PAYMENT SUMMARY',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 8),
                            _buildDetailRow('Trial Fee', '₹${trial.fee.toStringAsFixed(0)}', Icons.currency_rupee_outlined),
                            const Divider(height: 1),
                            _buildDetailRow('Discount', '₹${trial.discount.toStringAsFixed(0)}', Icons.percent_outlined),
                            const Divider(height: 1),
                            _buildDetailRow('Final Amount', '₹${trial.finalAmount.toStringAsFixed(0)}', Icons.account_balance_wallet_outlined),
                            const Divider(height: 1),
                            _buildDetailRow('Received Amount', '₹${trial.receivedAmount.toStringAsFixed(0)}', Icons.check_circle_outline_rounded),
                            const Divider(height: 1),
                            _buildDetailRow('Remaining Amount', '₹${trial.remainingAmount.toStringAsFixed(0)}', Icons.info_outline_rounded),
                            const Divider(height: 1),
                            _buildDetailRow('Payment Method', trial.paymentMethod ?? 'N/A', Icons.payment_outlined),
                            if (payDateFormatted != null) ...[
                              const Divider(height: 1),
                              _buildDetailRow('Payment Date', payDateFormatted, Icons.date_range_outlined),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Actions Bottom Bar
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: AppTheme.buttonHeight,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusButton)),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => AddTrialMemberScreen(editTrial: trial)),
                          );
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit Details'),
                      ),
                    ),
                  ),
                  if (status != 'Converted') ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: AppTheme.buttonHeight,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusButton)),
                          ),
                          onPressed: () {
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
                          },
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18, color: Colors.white),
                          label: const Text('Convert To Member', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
