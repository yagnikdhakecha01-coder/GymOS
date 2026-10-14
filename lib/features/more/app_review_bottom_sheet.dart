import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/theme.dart';
import '../../core/services/app_review_service.dart';

/// Premium in-app Play Store review bottom sheet.
///
/// Flow:
///   1. Stars-only view → user taps stars
///   2. Review text field slides in (pre-filled with role-based suggestion)
///   3. Submit → Play Store opens; Maybe Later → dismiss
class AppReviewBottomSheet extends StatefulWidget {
  final String role;   // 'owner' | 'staff' | 'member'
  final String? gymId;

  const AppReviewBottomSheet._({
    required this.role,
    this.gymId,
  });

  /// Opens the review bottom sheet.
  static Future<void> show(
    BuildContext context, {
    required String role,
    String? gymId,
  }) {
    if (!kIsWeb && Platform.isIOS) {
      return Future.value();
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AppReviewBottomSheet._(role: role, gymId: gymId),
    );
  }

  @override
  State<AppReviewBottomSheet> createState() => _AppReviewBottomSheetState();
}

class _AppReviewBottomSheetState extends State<AppReviewBottomSheet>
    with TickerProviderStateMixin {
  int _selectedStars = 0;
  bool _showReviewSection = false;
  bool _isSubmitting = false;
  late final TextEditingController _reviewController;

  // Per-star scale animation controllers
  late final List<AnimationController> _starControllers;
  late final List<Animation<double>> _starScales;

  @override
  void initState() {
    super.initState();
    _reviewController = TextEditingController();
    _starControllers = List.generate(
      5,
      (_) => AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 150),
      ),
    );
    _starScales = _starControllers.map((ctrl) {
      return TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 50),
        TweenSequenceItem(tween: Tween(begin: 1.35, end: 1.0), weight: 50),
      ]).animate(CurvedAnimation(parent: ctrl, curve: Curves.easeInOut));
    }).toList();
  }

  @override
  void dispose() {
    _reviewController.dispose();
    for (final ctrl in _starControllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _onStarTap(int starIndex) {
    // starIndex is 0-based; displayed star = starIndex + 1
    final tappedStars = starIndex + 1;
    setState(() {
      _selectedStars = tappedStars;
      _showReviewSection = true;
      _reviewController.text =
          AppReviewService.getSuggestedReview(widget.role, tappedStars);
    });

    // Animate all filled stars
    for (int i = 0; i <= starIndex; i++) {
      _starControllers[i].forward(from: 0);
    }

    // Haptic feedback
    HapticFeedback.lightImpact();
  }

  Future<void> _onSubmit() async {
    if (_selectedStars == 0 || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    // 1. Log analytics
    await AppReviewService.logReviewEvent(
      role: widget.role,
      stars: _selectedStars,
      submitted: true,
      gymId: widget.gymId,
    );

    // 2. Mark as reviewed
    await AppReviewService.markReviewed();

    if (!mounted) return;

    // 3. Dismiss sheet
    Navigator.of(context).pop();

    // 4. Open Store
    if (!kIsWeb && Platform.isIOS) {
      final iosUri = Uri.parse(AppReviewService.appStoreUrl);
      if (await canLaunchUrl(iosUri)) {
        await launchUrl(iosUri, mode: LaunchMode.externalApplication);
      }
    } else {
      final uri = Uri.parse(AppReviewService.playStoreUrl);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(
          Uri.parse(AppReviewService.playStoreFallbackUrl),
          mode: LaunchMode.externalApplication,
        );
      }
    }

    // 5. Show success snackbar (on parent context — called after pop)
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '🎉 Thank you for your review! It helps GymOS grow 🚀',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _onMaybeLater() async {
    // Log "skipped" only if stars were selected
    if (_selectedStars > 0) {
      await AppReviewService.logReviewEvent(
        role: widget.role,
        stars: _selectedStars,
        submitted: false,
        gymId: widget.gymId,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag Handle ─────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Header Icon ──────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
              const SizedBox(height: 20),

              // ── Title ────────────────────────────────────
              Text(
                'Enjoying GymOS?',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),

              // ── Subtitle ─────────────────────────────────
              Text(
                (!kIsWeb && Platform.isIOS)
                    ? 'Your review helps other gym owners\ndiscover GymOS.'
                    : 'Your review helps other gym owners\ndiscover us on Play Store.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // ── Stars Row ────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < _selectedStars;
                  return AnimatedBuilder(
                    animation: _starScales[i],
                    builder: (_, child) {
                      return Transform.scale(
                        scale: _starScales[i].value,
                        child: GestureDetector(
                          onTap: () => _onStarTap(i),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              filled
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 48,
                              color: filled
                                  ? const Color(0xFFF59E0B)
                                  : AppTheme.textMuted,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              ),

              // ── Review Section (animated slide-in) ───────
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: _showReviewSection
                    ? _buildReviewSection()
                    : const SizedBox.shrink(),
              ),

              const SizedBox(height: 16),

              // ── Maybe Later ──────────────────────────────
              if (!_showReviewSection)
                TextButton(
                  onPressed: _onMaybeLater,
                  child: Text(
                    'Maybe Later',
                    style: GoogleFonts.inter(
                      color: AppTheme.textMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),

        // Label
        Text(
          'Your Review',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),

        // Text field
        TextField(
          controller: _reviewController,
          maxLines: 5,
          minLines: 3,
          style: GoogleFonts.inter(fontSize: 13.5, color: AppTheme.textPrimary, height: 1.5),
          decoration: InputDecoration(
            hintText: 'Share your experience with GymOS...',
            hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusInput),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusInput),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusInput),
              borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Feel free to edit this suggestion before submitting.',
          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 20),

        // Submit Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _onSubmit,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(
              _isSubmitting
                  ? ((!kIsWeb && Platform.isIOS) ? 'Opening Store...' : 'Opening Play Store...')
                  : ((!kIsWeb && Platform.isIOS) ? 'Submit Review' : 'Submit Review on Play Store'),
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
              elevation: 0,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Maybe Later
        Center(
          child: TextButton(
            onPressed: _onMaybeLater,
            child: Text(
              'Maybe Later',
              style: GoogleFonts.inter(
                color: AppTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
