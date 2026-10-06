import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';

class TrainingCard extends StatefulWidget {
  final String muscleGroup;
  final bool isCompleted;
  final VoidCallback? onAskTrainer;
  final VoidCallback? onTap;

  const TrainingCard({
    super.key,
    required this.muscleGroup,
    required this.isCompleted,
    this.onAskTrainer,
    this.onTap,
  });

  @override
  State<TrainingCard> createState() => _TrainingCardState();
}

class _TrainingCardState extends State<TrainingCard> with SingleTickerProviderStateMixin {
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
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
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
    final String muscle = widget.muscleGroup.toLowerCase().replaceAll(' ', '_');
    final String illustrationPath = 'assets/images/member/$muscle.png';

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
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
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.fitness_center_rounded,
                            color: AppTheme.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Today's Training",
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.muscleGroup,
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: widget.isCompleted
                                      ? AppTheme.successLight
                                      : AppTheme.warningLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.isCompleted ? 'Completed' : 'Not Completed',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: widget.isCompleted
                                        ? AppTheme.success
                                        : const Color(0xFFD97706),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Ask your trainer for today\'s exercises.',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Premium Muscle Illustration based on Muscle day
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceGray,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              illustrationPath,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Icon(
                                    Icons.accessibility_new_rounded,
                                    color: AppTheme.primary.withOpacity(0.4),
                                    size: 32,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(height: 0.5, color: AppTheme.border),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onAskTrainer,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Ask Trainer',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
