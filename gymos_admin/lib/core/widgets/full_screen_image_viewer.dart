import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/admin_theme.dart';

/// Opens an interactive full-screen image viewer dialog with smooth zoom, pan, and controls.
void showFullScreenImageViewer(
  BuildContext context, {
  required String imageUrl,
  String? title,
  String? subtitle,
  String? heroTag,
}) {
  if (imageUrl.trim().isEmpty) return;

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'FullScreenImage',
    barrierColor: Colors.black.withValues(alpha: 0.88),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return FullScreenImageViewer(
        imageUrl: imageUrl,
        title: title,
        subtitle: subtitle,
        heroTag: heroTag,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedValue = Curves.easeOutCubic.transform(animation.value);
      return Transform.scale(
        scale: 0.95 + (0.05 * curvedValue),
        child: Opacity(
          opacity: animation.value,
          child: child,
        ),
      );
    },
  );
}

class FullScreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? title;
  final String? subtitle;
  final String? heroTag;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrl,
    this.title,
    this.subtitle,
    this.heroTag,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final TransformationController _transformController = TransformationController();
  final FocusNode _focusNode = FocusNode();
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_onTransformChanged);
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    if ((scale - _currentScale).abs() > 0.05) {
      setState(() {
        _currentScale = scale;
      });
    }
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _resetZoom() {
    setState(() {
      _transformController.value = Matrix4.identity();
      _currentScale = 1.0;
    });
  }

  void _zoomIn() {
    final newScale = (_currentScale * 1.3).clamp(0.5, 5.0);
    _animateToScale(newScale);
  }

  void _zoomOut() {
    final newScale = (_currentScale / 1.3).clamp(0.5, 5.0);
    _animateToScale(newScale);
  }

  void _animateToScale(double targetScale) {
    setState(() {
      _transformController.value = Matrix4.diagonal3Values(targetScale, targetScale, 1.0);
      _currentScale = targetScale;
    });
  }

  void _handleDoubleTap() {
    if (_currentScale > 1.2) {
      _resetZoom();
    } else {
      _animateToScale(2.5);
    }
  }

  Future<void> _openOriginal() async {
    final uri = Uri.tryParse(widget.imageUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Dark Backdrop with blur filter
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ),

            // Main Interactive Image Viewer Area
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: GestureDetector(
                    onDoubleTap: _handleDoubleTap,
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 0.5,
                      maxScale: 5.0,
                      clipBehavior: Clip.none,
                      boundaryMargin: const EdgeInsets.all(120),
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.90,
                          maxHeight: MediaQuery.of(context).size.height * 0.78,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.6),
                              blurRadius: 40,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: widget.heroTag != null
                              ? Hero(
                                  tag: widget.heroTag!,
                                  child: _buildImage(),
                                )
                              : _buildImage(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Top Header Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.75),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      // Avatar Thumbnail
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white24, width: 2),
                          image: DecorationImage(
                            image: NetworkImage(widget.imageUrl),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Title & Subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.title != null)
                              Text(
                                widget.title!,
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            Text(
                              widget.subtitle ?? 'Full Screen Photo Viewer',
                              style: GoogleFonts.inter(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),

                      // Action: Open Original URL in New Tab
                      Tooltip(
                        message: 'Open Original in Browser',
                        child: InkWell(
                          onTap: _openOriginal,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Action: Close Button
                      Tooltip(
                        message: 'Close (Esc)',
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom Floating Controls Toolbar
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Floating zoom controls pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Zoom Out
                            _ControlButton(
                              icon: Icons.zoom_out_rounded,
                              tooltip: 'Zoom Out',
                              onPressed: _zoomOut,
                            ),
                            const SizedBox(width: 8),

                            // Scale Text / Reset
                            Tooltip(
                              message: 'Reset Zoom (1:1)',
                              child: InkWell(
                                onTap: _resetZoom,
                                borderRadius: BorderRadius.circular(20),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  child: Text(
                                    '${(_currentScale * 100).toInt()}%',
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Zoom In
                            _ControlButton(
                              icon: Icons.zoom_in_rounded,
                              tooltip: 'Zoom In',
                              onPressed: _zoomIn,
                            ),
                            const SizedBox(width: 8),

                            Container(
                              height: 18,
                              width: 1,
                              color: Colors.white24,
                            ),
                            const SizedBox(width: 8),

                            // Reset Button
                            _ControlButton(
                              icon: Icons.refresh_rounded,
                              tooltip: 'Reset (100%)',
                              onPressed: _resetZoom,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // User Navigation Hint
                      Text(
                        'Scroll to zoom • Double click to zoom in/out • Drag to pan • ESC to exit',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    return Image.network(
      widget.imageUrl,
      fit: BoxFit.contain,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Container(
          width: 320,
          height: 320,
          color: Colors.black26,
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                  : null,
              color: AdminTheme.primary,
              strokeWidth: 3,
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: 320,
          height: 320,
          color: Colors.black45,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 56),
              const SizedBox(height: 12),
              Text(
                'Unable to display image',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _openOriginal,
                icon: const Icon(Icons.open_in_new_rounded, size: 16, color: Colors.white),
                label: Text('Open link directly', style: GoogleFonts.inter(color: Colors.white, fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white30),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

/// An interactive wrapper around any Avatar widget that provides hover mouse feedback
/// and opens the full-screen photo viewer when clicked.
class InteractiveAvatarWrapper extends StatelessWidget {
  final String? imageUrl;
  final String title;
  final String? subtitle;
  final Widget child;
  final double radius;
  final bool showZoomBadge;

  const InteractiveAvatarWrapper({
    super.key,
    required this.imageUrl,
    required this.title,
    this.subtitle,
    required this.child,
    this.radius = 24,
    this.showZoomBadge = true,
  });

  bool get hasValidImage => imageUrl != null && imageUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!hasValidImage) {
      return child;
    }

    return Tooltip(
      message: 'Click to view photo full screen',
      waitDuration: const Duration(milliseconds: 300),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            showFullScreenImageViewer(
              context,
              imageUrl: imageUrl!.trim(),
              title: title,
              subtitle: subtitle,
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              child,
              if (showZoomBadge)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: BoxDecoration(
                      color: AdminTheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.fullscreen_rounded,
                      size: 11,
                      color: Colors.white,
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
