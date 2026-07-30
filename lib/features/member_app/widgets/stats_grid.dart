import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

class StatsGrid extends StatelessWidget {
  final int attendancePercentage;
  final int membershipDaysLeft;
  final int ptSessionsLeft;
  final String pendingPayment;

  const StatsGrid({
    super.key,
    required this.attendancePercentage,
    required this.membershipDaysLeft,
    required this.ptSessionsLeft,
    this.pendingPayment = '₹0',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.bar_chart_rounded,
                  iconBgColor: const Color(0xFFEDE9FE),
                  iconColor: AppTheme.primary,
                  title: 'Attendance',
                  value: '$attendancePercentage%',
                  subtitle: 'This Month',
                  delay: 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.calendar_month_rounded,
                  iconBgColor: const Color(0xFFDCFCE7),
                  iconColor: AppTheme.success,
                  title: 'Membership',
                  value: '$membershipDaysLeft',
                  subtitle: 'Days Left',
                  delay: 100,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  icon: Icons.fitness_center_rounded,
                  iconBgColor: const Color(0xFFDBEAFE),
                  iconColor: const Color(0xFF3B82F6),
                  title: 'PT Sessions',
                  value: '$ptSessionsLeft',
                  subtitle: 'Sessions Left',
                  delay: 200,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  icon: Icons.payment_rounded,
                  iconBgColor: const Color(0xFFFEF3C7),
                  iconColor: const Color(0xFFD97706),
                  title: 'Pending Payment',
                  value: pendingPayment,
                  subtitle: 'All Clear',
                  delay: 300,
                  isWarning: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatefulWidget {
  final IconData icon;
  final Color iconBgColor;
  final Color iconColor;
  final String title;
  final String value;
  final String subtitle;
  final int delay;
  final bool isWarning;

  const _StatCard({
    required this.icon,
    required this.iconBgColor,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.delay,
    this.isWarning = false,
  });

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: widget.iconBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        widget.value,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: widget.isWarning ? const Color(0xFFD97706) : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
