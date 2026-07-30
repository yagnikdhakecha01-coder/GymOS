import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/theme.dart';

class OwnerAttendanceSuccessScreen extends StatefulWidget {
  final String name;
  final String role;
  final String time;
  final String date;
  final String status;
  final bool isCheckIn;

  const OwnerAttendanceSuccessScreen({
    super.key,
    required this.name,
    required this.role,
    required this.time,
    required this.date,
    required this.status,
    required this.isCheckIn,
  });

  @override
  State<OwnerAttendanceSuccessScreen> createState() => _OwnerAttendanceSuccessScreenState();
}

class _OwnerAttendanceSuccessScreenState extends State<OwnerAttendanceSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _checkAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _checkAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _scaleAnim = CurvedAnimation(parent: _checkAnim, curve: Curves.elasticOut);
    _checkAnim.forward();
  }

  @override
  void dispose() {
    _checkAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actionLabel = widget.isCheckIn ? 'Check In' : 'Check Out';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '$actionLabel Success',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 40),

                  // ── Green Checkmark Animation ──
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: const BoxDecoration(
                        color: Color(0xFFDCFCE7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF16A34A),
                        size: 52,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    '${widget.isCheckIn ? 'Checked In' : 'Checked Out'} Successfully!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 16),

                  // ── Time ──
                  Text(
                    widget.time,
                    style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.danger),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.date,
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 32),

                  // ── Details Card ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFF0F0F2)),
                    ),
                    child: Column(
                      children: [
                        _detailRow('Staff Name', widget.name),
                        _divider(),
                        _detailRow('Shift N', widget.role),
                        _divider(),
                        _detailRow('Check In Time', widget.time),
                        _divider(),
                        _detailRow('Total Working Hours', '09h 54m', valueColor: const Color(0xFF16A34A)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── OK, Got It Button ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  'OK, Got It',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() {
    return const Divider(height: 1, indent: 20, endIndent: 20, color: Color(0xFFF3F4F6));
  }
}
