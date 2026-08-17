import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';

class PaymentResultScreen extends StatefulWidget {
  final bool isSuccess;
  final String title;
  final String message;
  final String memberName;
  final String? memberCode;
  final double amount;
  final String paymentMethod;
  final String? transactionDate;
  final String? referenceNo;
  final double? remainingPending;
  final String? planName;
  final String? errorMessage;

  const PaymentResultScreen({
    super.key,
    required this.isSuccess,
    required this.title,
    required this.message,
    required this.memberName,
    this.memberCode,
    required this.amount,
    required this.paymentMethod,
    this.transactionDate,
    this.referenceNo,
    this.remainingPending,
    this.planName,
    this.errorMessage,
  });

  static Future<void> show(
    BuildContext context, {
    required bool isSuccess,
    required String title,
    required String message,
    required String memberName,
    String? memberCode,
    required double amount,
    required String paymentMethod,
    String? transactionDate,
    String? referenceNo,
    double? remainingPending,
    String? planName,
    String? errorMessage,
  }) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentResultScreen(
          isSuccess: isSuccess,
          title: title,
          message: message,
          memberName: memberName,
          memberCode: memberCode,
          amount: amount,
          paymentMethod: paymentMethod,
          transactionDate: transactionDate,
          referenceNo: referenceNo,
          remainingPending: remainingPending,
          planName: planName,
          errorMessage: errorMessage,
        ),
      ),
    );
  }

  @override
  State<PaymentResultScreen> createState() => _PaymentResultScreenState();
}

class _PaymentResultScreenState extends State<PaymentResultScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.elasticOut,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
    );

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSuccess = widget.isSuccess;
    final currencyFormatter = NumberFormat('#,##,###');
    final formattedAmount = '₹ ${currencyFormatter.format(widget.amount)}';
    final dateDisplay = widget.transactionDate != null && widget.transactionDate!.isNotEmpty
        ? widget.transactionDate!
        : DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context);
        return false;
      },
      child: Scaffold(
        backgroundColor: isSuccess ? const Color(0xFFF8FAFC) : const Color(0xFFFEF2F2),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 24),
                        // Animated Badge Icon
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSuccess
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFFEE2E2),
                              border: Border.all(
                                color: isSuccess
                                    ? const Color(0xFF86EFAC)
                                    : const Color(0xFFFCA5A5),
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isSuccess ? const Color(0xFF22C55E) : const Color(0xFFEF4444)).withOpacity(0.2),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Icon(
                                isSuccess ? Icons.check_rounded : Icons.close_rounded,
                                size: 56,
                                color: isSuccess ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Title
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Text(
                            widget.title,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: isSuccess ? const Color(0xFF0F172A) : const Color(0xFF991B1B),
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Message / Subtitle
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Text(
                            widget.message,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Amount Card
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.border.withOpacity(0.7)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'AMOUNT RECEIVED',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  formattedAmount,
                                  style: GoogleFonts.inter(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w800,
                                    color: isSuccess ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                                    letterSpacing: -1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Details Breakdown Card
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppTheme.border.withOpacity(0.7)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 16,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                _buildDetailRow('Member Name', widget.memberName),
                                if (widget.memberCode != null && widget.memberCode!.isNotEmpty) ...[
                                  const Divider(height: 20),
                                  _buildDetailRow('Member ID', widget.memberCode!),
                                ],
                                if (widget.planName != null && widget.planName!.isNotEmpty) ...[
                                  const Divider(height: 20),
                                  _buildDetailRow('Membership Plan', widget.planName!),
                                ],
                                const Divider(height: 20),
                                _buildDetailRow('Payment Mode', widget.paymentMethod),
                                const Divider(height: 20),
                                _buildDetailRow('Date & Time', dateDisplay),
                                if (widget.referenceNo != null && widget.referenceNo!.isNotEmpty) ...[
                                  const Divider(height: 20),
                                  _buildDetailRow('Reference No.', widget.referenceNo!),
                                ],
                                if (widget.remainingPending != null) ...[
                                  const Divider(height: 20),
                                  _buildDetailRow(
                                    'Remaining Pending',
                                    widget.remainingPending! <= 0
                                        ? '₹ 0 (Paid in Full)'
                                        : '₹ ${currencyFormatter.format(widget.remainingPending)}',
                                    valueColor: widget.remainingPending! <= 0 ? const Color(0xFF16A34A) : const Color(0xFFEF4444),
                                    isBold: true,
                                  ),
                                ],
                                if (!isSuccess && widget.errorMessage != null) ...[
                                  const Divider(height: 20),
                                  _buildDetailRow(
                                    'Error Details',
                                    widget.errorMessage!,
                                    valueColor: const Color(0xFFDC2626),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),

                // Bottom Action Buttons
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSuccess ? AppTheme.primary : const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        isSuccess ? 'Done' : 'Dismiss',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
