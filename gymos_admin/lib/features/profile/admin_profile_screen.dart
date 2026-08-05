import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/skeleton_loader.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});
  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  bool _isLoading = true;
  bool _twoFactorEnabled = true;
  final _nameController = TextEditingController(text: 'Super Admin');
  final _emailController = TextEditingController(text: 'admin@gymos.com');

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 500), () { if (mounted) setState(() => _isLoading = false); });
  }

  @override
  void dispose() { _nameController.dispose(); _emailController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);
    if (_isLoading) return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable(rows: 4));
    final isDesktop = AdminResponsive.isDesktop(context);

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 300),
            childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
            children: [
              Text('Admin Profile', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
              const SizedBox(height: 4),
              Text('Manage your account and security settings', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
              const SizedBox(height: 28),
              if (isDesktop)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: Column(children: [_profileCard(context), const SizedBox(height: 20), _securityCard(context)])),
                  const SizedBox(width: 24),
                  Expanded(flex: 2, child: Column(children: [_loginHistoryCard(context), const SizedBox(height: 20), _deviceHistoryCard(context)])),
                ])
              else ...[_profileCard(context), const SizedBox(height: 20), _securityCard(context), const SizedBox(height: 20), _loginHistoryCard(context), const SizedBox(height: 20), _deviceHistoryCard(context)],
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AdminTheme.cardColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusCard), border: Border.all(color: AdminTheme.borderColor(context))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 32, backgroundColor: AdminTheme.primary,
            child: Text('SA', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20))),
          const SizedBox(width: 20),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Super Admin', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AdminTheme.textColor(context))),
            const SizedBox(height: 4),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AdminTheme.primaryLight, borderRadius: BorderRadius.circular(4)),
              child: Text('Super Admin', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AdminTheme.primary))),
          ]),
        ]),
        const SizedBox(height: 24),
        _field('Full Name', _nameController),
        const SizedBox(height: 16),
        _field('Email', _emailController),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated!'), backgroundColor: AdminTheme.success));
        }, style: ElevatedButton.styleFrom(minimumSize: const Size(140, 40)),
          child: Text('Save Changes', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _securityCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AdminTheme.cardColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusCard), border: Border.all(color: AdminTheme.borderColor(context))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.security_rounded, size: 20, color: AdminTheme.primary),
          const SizedBox(width: 10),
          Text('Security', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
        ]),
        const SizedBox(height: 20),
        _securityRow('Change Password', 'Update your account password', Icons.lock_outline_rounded, () {}),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AdminTheme.surfaceColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
          child: Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Two-Factor Authentication', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
              const SizedBox(height: 2),
              Text('Add extra security with TOTP', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
            ])),
            Switch(value: _twoFactorEnabled, onChanged: (v) => setState(() => _twoFactorEnabled = v)),
          ]),
        ),
        const SizedBox(height: 12),
        _securityRow('Session Timeout', 'Auto-logout after 30 minutes of inactivity', Icons.timer_outlined, () {}),
      ]),
    );
  }

  Widget _securityRow(String title, String subtitle, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AdminTheme.surfaceColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusSm)),
        child: Row(children: [
          Icon(icon, size: 20, color: AdminTheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
            const SizedBox(height: 2),
            Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
          ])),
          Icon(Icons.chevron_right_rounded, color: AdminTheme.mutedTextColor(context)),
        ]),
      ),
    );
  }

  Widget _loginHistoryCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AdminTheme.cardColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusCard), border: Border.all(color: AdminTheme.borderColor(context))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Login History', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
        const SizedBox(height: 16),
        ..._loginHistory.map((h) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: AdminTheme.successLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.login_rounded, size: 16, color: AdminTheme.success)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h['time'] as String, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
              Text(h['ip'] as String, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
            ])),
          ]),
        )),
      ]),
    );
  }

  Widget _deviceHistoryCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: AdminTheme.cardColor(context), borderRadius: BorderRadius.circular(AdminTheme.radiusCard), border: Border.all(color: AdminTheme.borderColor(context))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Device History', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
        const SizedBox(height: 16),
        ..._devices.map((d) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Container(width: 32, height: 32, decoration: BoxDecoration(color: AdminTheme.infoLight, borderRadius: BorderRadius.circular(8)),
              child: Icon(d['icon'] as IconData, size: 16, color: AdminTheme.info)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['device'] as String, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
              Text(d['lastSeen'] as String, style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context))),
            ])),
          ]),
        )),
      ]),
    );
  }

  Widget _field(String label, TextEditingController controller) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context))),
      const SizedBox(height: 6),
      TextField(controller: controller, style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context)),
        decoration: InputDecoration(filled: true, fillColor: AdminTheme.surfaceColor(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12))),
    ]);
  }
}

const _loginHistory = [
  {'time': 'Aug 3, 2026 — 09:30 AM', 'ip': '192.168.1.100 — Chrome'},
  {'time': 'Aug 2, 2026 — 02:15 PM', 'ip': '192.168.1.100 — Chrome'},
  {'time': 'Aug 1, 2026 — 10:00 AM', 'ip': '192.168.1.105 — Firefox'},
  {'time': 'Jul 31, 2026 — 06:00 PM', 'ip': '192.168.1.100 — Chrome'},
];

const _devices = [
  {'device': 'Chrome — Windows 11', 'lastSeen': 'Active now', 'icon': Icons.computer_rounded},
  {'device': 'Firefox — MacOS', 'lastSeen': '3 days ago', 'icon': Icons.laptop_mac_rounded},
  {'device': 'Safari — iPad', 'lastSeen': '1 week ago', 'icon': Icons.tablet_mac_rounded},
];
