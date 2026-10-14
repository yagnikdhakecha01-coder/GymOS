import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/image_security_service.dart';
import '../authentication/auth_viewmodel.dart';
import '../subscription/owner_subscription_screen.dart';

class CustomBrandingScreen extends StatefulWidget {
  const CustomBrandingScreen({super.key});

  @override
  State<CustomBrandingScreen> createState() => _CustomBrandingScreenState();
}

class _CustomBrandingScreenState extends State<CustomBrandingScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  String _logoUrl = '';
  bool _isSaving = false;
  bool _isUploadingImage = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final initialName = authVm.customBrandingName == 'GYMOS' ? (authVm.gymInfo?['name'] ?? '') : authVm.customBrandingName;
    _logoUrl = authVm.customBrandingLogoUrl ?? '';
    _nameController = TextEditingController(text: initialName);

    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadLogo(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final bytes = await file.readAsBytes();

      if (mounted) {
        setState(() => _isUploadingImage = true);
      }

      // ── Virus & Malware Security Verification ──
      final validation = await ImageSecurityService.validateImageBytes(bytes);
      if (!validation.isValid) {
        if (mounted) {
          setState(() => _isUploadingImage = false);
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.security_rounded, color: AppTheme.danger, size: 24),
                  const SizedBox(width: 8),
                  Text('Security Check Failed', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: Text(
                validation.errorMessage ?? 'Invalid or unsafe image file detected.',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (!mounted) return;
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? 'branding_gym';

      // Secure upload to 'branding' bucket
      final uploadedUrl = await ImageSecurityService.uploadSecureImage(
        bucket: 'branding',
        directoryPath: '$gymId',
        bytes: bytes,
      );

      if (mounted) {
        setState(() {
          _logoUrl = uploadedUrl;
          _isUploadingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Logo uploaded & verified securely!'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[Branding] Image upload error: $e');
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload logo: $e'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showImagePickerSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upload Gym Logo',
                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'Select logo image (JPG, PNG, WebP • Max 5MB). Files are auto-scanned for safety.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 18),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
                  child: const Icon(Icons.photo_library_rounded, color: AppTheme.primary),
                ),
                title: Text('Choose from Gallery', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadLogo(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(color: AppTheme.primaryLight, shape: BoxShape.circle),
                  child: const Icon(Icons.camera_alt_rounded, color: AppTheme.primary),
                ),
                title: Text('Take Photo with Camera', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadLogo(ImageSource.camera);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveBranding() async {
    if (!_formKey.currentState!.validate()) return;

    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final hasAccess = authVm.isCustomBrandingEnabled;

    if (!hasAccess) {
      _showUpgradeDialog();
      return;
    }

    setState(() => _isSaving = true);
    try {
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId == null) throw Exception('No active gym found');

      // Update Supabase Database
      await SupabaseService.client
          .from('gyms')
          .update({
            'name': _nameController.text.trim(),
            'logo_url': _logoUrl.trim(),
          })
          .eq('id', gymId);

      // Sync and cache locally
      await authVm.updateCustomBranding(
        enabled: true,
        name: _nameController.text.trim(),
        logoUrl: _logoUrl.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Custom branding updated successfully!'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update branding: $e'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showUpgradeDialog() {
    final isIOS = !kIsWeb && Platform.isIOS;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        title: Row(
          children: [
            const Icon(Icons.lock_rounded, color: AppTheme.warning, size: 28),
            const SizedBox(width: 10),
            Text(isIOS ? 'Branding Configuration' : 'Upgrade Required', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          isIOS
              ? 'Custom whitelabel branding is managed by your account administrator.'
              : 'Custom whitelabel branding is a Premium feature. Upgrade to Pro or Business Plan to activate custom branding for all your members and staff.',
          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          if (isIOS)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('OK', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold)),
            )
          else ...[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const OwnerSubscriptionScreen()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusButton)),
              ),
              child: Text('View Plan Details', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final hasAccess = authVm.isCustomBrandingEnabled;

    final previewName = _nameController.text.trim().isEmpty ? 'Your Gym Name' : _nameController.text.trim();
    final previewLogo = _logoUrl.trim();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Custom App Branding'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!hasAccess) ...[
                  // Premium Upgrade Banner
                  CustomCard(
                    color: AppTheme.warningLight,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, color: AppTheme.warning, size: 24),
                            const SizedBox(width: 10),
                            Text(
                              (!kIsWeb && Platform.isIOS) ? 'Branding Information' : 'Premium Feature Locked',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.warning.withAlpha(200)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (!kIsWeb && Platform.isIOS)
                              ? 'Custom whitelabel branding is managed by your account administrator. You can customize details below to preview how it looks.'
                              : 'Your current plan does not include whitelabel custom branding. You can customize details below to preview how it looks, but you must upgrade your subscription to save and apply the custom name and logo across the member/staff apps.',
                          style: GoogleFonts.inter(fontSize: 12.5, color: Colors.amber[900], height: 1.4),
                        ),
                        if (kIsWeb || !Platform.isIOS) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 38,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const OwnerSubscriptionScreen()),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.warning,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              ),
                              icon: const Icon(Icons.upgrade_rounded, size: 18),
                              label: Text('View Plan Details', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Branding Form Fields
                CustomCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('App Gym Name *', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameController,
                        validator: (value) => value == null || value.trim().isEmpty ? 'Please enter branding name' : null,
                        decoration: const InputDecoration(
                          hintText: 'e.g. FitZone Pro Gym',
                          prefixIcon: Icon(Icons.edit_note_rounded),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // ── Direct Logo Upload from Phone (URL is hidden from user) ──
                      Text('App Logo *', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),

                      if (_isUploadingImage) ...[
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9F9FB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.primary),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  'Scanning & uploading logo securely...',
                                  style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_logoUrl.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9F9FB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  _logoUrl,
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => _buildDefaultPreviewLogo(),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.verified_rounded, size: 16, color: Color(0xFF10B981)),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Logo Ready & Verified',
                                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Virus scan passed • High quality',
                                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Change Logo',
                                icon: const Icon(Icons.edit_outlined, color: AppTheme.primary, size: 20),
                                onPressed: _showImagePickerSheet,
                              ),
                              IconButton(
                                tooltip: 'Remove Logo',
                                icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                                onPressed: () => setState(() => _logoUrl = ''),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        InkWell(
                          onTap: _showImagePickerSheet,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF9F9FB),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4), width: 1.5),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primaryLight,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add_photo_alternate_rounded, color: AppTheme.primary, size: 28),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Tap to Upload Logo from Phone',
                                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.primary),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Supports Camera & Gallery • Auto-scanned for virus & format safety',
                                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Upload transparent PNG or JPG image (Max 5MB). Files are validated with magic-byte anti-malware inspection.',
                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Live Preview Section Title
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'LIVE PREVIEW MOCKUP',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1),
                  ),
                ),

                // Live Preview Container (Simulates App Splash/Launch View)
                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                    border: Border.all(color: AppTheme.border, width: 2),
                    boxShadow: AppTheme.cardShadow,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Live Logo Rendering
                        if (previewLogo.isNotEmpty && (previewLogo.startsWith('http') || previewLogo.startsWith('https')))
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.network(
                              previewLogo,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => _buildDefaultPreviewLogo(),
                            ),
                          )
                        else
                          _buildDefaultPreviewLogo(),

                        const SizedBox(height: 16),

                        // Live Gym Name Text Rendering
                        Text(
                          previewName,
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primary,
                            letterSpacing: 2,
                          ),
                        ),

                        const SizedBox(height: 6),
                        Text(
                          'Stronger Every Day',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Save Button
                SizedBox(
                  height: AppTheme.buttonHeight,
                  child: CustomButton(
                    onPressed: _isSaving ? null : _saveBranding,
                    isLoading: _isSaving,
                    text: hasAccess ? 'Apply & Save Branding' : 'Save (Upgrade Required)',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultPreviewLogo() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Icon(
        Icons.fitness_center_rounded,
        color: Colors.white,
        size: 40,
      ),
    );
  }
}
