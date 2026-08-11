import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/services/supabase_service.dart';
import '../authentication/auth_viewmodel.dart';
import '../subscription/owner_subscription_screen.dart';

class CustomBrandingScreen extends StatefulWidget {
  const CustomBrandingScreen({Key? key}) : super(key: key);

  @override
  State<CustomBrandingScreen> createState() => _CustomBrandingScreenState();
}

class _CustomBrandingScreenState extends State<CustomBrandingScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _logoController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final initialName = authVm.customBrandingName == 'GYMOS' ? (authVm.gymInfo?['name'] ?? '') : authVm.customBrandingName;
    final initialLogo = authVm.customBrandingLogoUrl ?? '';
    _nameController = TextEditingController(text: initialName);
    _logoController = TextEditingController(text: initialLogo);

    // Add listeners to trigger live preview refresh
    _nameController.addListener(() => setState(() {}));
    _logoController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _logoController.dispose();
    super.dispose();
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
      final gymId = authVm.gymInfo?['id'];
      if (gymId == null) throw Exception('No active gym found');

      // Update Supabase Database
      await SupabaseService.client
          .from('gyms')
          .update({
            'name': _nameController.text.trim(),
            'logo_url': _logoController.text.trim(),
          })
          .eq('id', gymId);

      // Sync and cache locally
      await authVm.updateCustomBranding(
        enabled: true,
        name: _nameController.text.trim(),
        logoUrl: _logoController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Custom branding updated successfully!'), backgroundColor: AppTheme.success),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update branding: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        title: Row(
          children: [
            const Icon(Icons.lock_rounded, color: AppTheme.warning, size: 28),
            const SizedBox(width: 10),
            Text('Upgrade Required', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Custom whitelabel branding is a Premium feature. Upgrade to Pro or Business Plan to activate custom branding for all your members and staff.',
          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
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
            child: Text('Upgrade Now', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authVm = Provider.of<AuthViewModel>(context);
    final hasAccess = authVm.isCustomBrandingEnabled;

    final previewName = _nameController.text.trim().isEmpty ? 'Your Gym Name' : _nameController.text.trim();
    final previewLogo = _logoController.text.trim();

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
                              'Premium Feature Locked',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.warning.withAlpha(200)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your current plan does not include whitelabel custom branding. You can customize details below to preview how it looks, but you must upgrade your subscription to save and apply the custom name and logo across the member/staff apps.',
                          style: GoogleFonts.inter(fontSize: 12.5, color: Colors.amber[900], height: 1.4),
                        ),
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
                            label: Text('Upgrade to Premium Plan', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
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
                      Text('App Logo Image URL *', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _logoController,
                        validator: (value) => value == null || value.trim().isEmpty ? 'Please enter image url' : null,
                        decoration: const InputDecoration(
                          hintText: 'e.g. https://domain.com/logo.png',
                          prefixIcon: Icon(Icons.link_rounded),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Provide a public URL of your gym logo image (JPG or PNG, transparent background recommended).',
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
