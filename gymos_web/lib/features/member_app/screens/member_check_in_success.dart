import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../member_app_viewmodel.dart';

class MemberCheckInSuccess extends StatefulWidget {
  final VoidCallback? onDone;
  final bool alreadyMarked;

  const MemberCheckInSuccess({
    super.key,
    this.onDone,
    this.alreadyMarked = false,
  });

  @override
  State<MemberCheckInSuccess> createState() => _MemberCheckInSuccessState();
}

class _MemberCheckInSuccessState extends State<MemberCheckInSuccess>
    with TickerProviderStateMixin {
  late AnimationController _checkController;
  late Animation<double> _checkScaleAnim;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _checkScaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _checkController, curve: Curves.elasticOut),
    );
    _checkController.forward();
  }

  @override
  void dispose() {
    _checkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MemberAppViewModel>(
      builder: (context, vm, _) {
        final displayTime = vm.checkInTime.isNotEmpty ? vm.checkInTime : '07:32 AM';
        final displayDate = vm.checkInDate.isNotEmpty ? vm.checkInDate : '15 May 2025';

        return Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            title: Text(
              widget.alreadyMarked ? 'Attendance Status' : 'Attendance Success',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 32),

                  // ═══════ DYNAMIC ICON CIRCLE ═══════
                  ScaleTransition(
                    scale: _checkScaleAnim,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: widget.alreadyMarked ? const Color(0xFFEFF6FF) : const Color(0xFFDCFCE7),
                      ),
                      child: Center(
                        child: Icon(
                          widget.alreadyMarked ? Icons.info_outline_rounded : Icons.check_circle_rounded,
                          color: widget.alreadyMarked ? Colors.blue : AppTheme.success,
                          size: widget.alreadyMarked ? 60 : 90,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Header Title
                  Text(
                    widget.alreadyMarked ? 'Your Attendance is Already Done!' : 'Attendance Successful!!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "You're all set for today.",
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ═══════ USER DETAILS CARD (Image 7) ═══════
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: Column(
                      children: [
                        // User Profile Row
                        Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2), width: 2),
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/member/avatar_default.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: AppTheme.primaryLight,
                                    child: const Icon(Icons.person, color: AppTheme.primary, size: 24),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    vm.memberName,
                                    style: GoogleFonts.inter(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Member ID: ${vm.memberId.length > 8 ? vm.memberId.substring(0, 8) : vm.memberId}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Container(height: 0.5, color: AppTheme.border),
                        const SizedBox(height: 16),

                        // Details Rows
                        _infoRow('Check-in Time', displayTime),
                        const SizedBox(height: 12),
                        _infoRow('Date', displayDate),
                        const SizedBox(height: 12),
                        _infoRow('Status', 'Present', isStatus: true),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // ═══════ DONE BUTTON (Image 7 bottom) ═══════
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: widget.onDone ?? () {
                        // Safely pop or go back - if can't pop, just do nothing (tab will handle it)
                        if (Navigator.canPop(context)) {
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Done',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value, {bool isStatus = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        if (isStatus)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFDCFCE7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.success,
              ),
            ),
          )
        else
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
      ],
    );
  }
}
