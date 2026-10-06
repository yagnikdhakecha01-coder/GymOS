import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

class MotivationCard extends StatefulWidget {
  final String quote;

  const MotivationCard({
    super.key,
    required this.quote,
  });

  @override
  State<MotivationCard> createState() => _MotivationCardState();
}

class _MotivationCardState extends State<MotivationCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;

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
    _controller.forward();
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Quote content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Big quote marks
                  Text(
                    '\u201C\u201C',
                    style: GoogleFonts.inter(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primary.withValues(alpha: 0.2),
                      height: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.quote,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Dumbbell illustration
            SizedBox(
              width: 70,
              height: 70,
              child: Image.asset(
                'assets/images/member/dumbbell_illustration.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.fitness_center_rounded,
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  size: 40,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
