import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/services/supabase_service.dart';

class DuplicateDetectionScreen extends StatefulWidget {
  const DuplicateDetectionScreen({super.key});

  @override
  State<DuplicateDetectionScreen> createState() => _DuplicateDetectionScreenState();
}

class _DuplicateDetectionScreenState extends State<DuplicateDetectionScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _alerts = [];

  @override
  void initState() {
    super.initState();
    _scanDuplicates();
  }

  String _getMonthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month >= 1 && month <= 12) return names[month - 1];
    return '';
  }

  String _formatRelativeTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.isNegative) return 'Just now';
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dateTime.day} ${_getMonthName(dateTime.month)}';
  }

  Future<void> _scanDuplicates() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      if (!AdminSupabaseService.isInitialized) {
        setState(() {
          _alerts = [];
          _isLoading = false;
        });
        return;
      }
      final client = AdminSupabaseService.client;

      // Fetch all gyms with their owners
      final response = await client
          .from('gyms')
          .select('id, name, status, created_at, user_gym_associations(role, profiles(full_name, phone_number))');
      
      final gymsList = response as List;
      final List<Map<String, dynamic>> processedGyms = [];

      for (var item in gymsList) {
        final gymMap = Map<String, dynamic>.from(item);
        String ownerName = '-';
        String ownerMobile = '-';
        
        final associations = gymMap['user_gym_associations'] as List?;
        if (associations != null) {
          for (var assoc in associations) {
            if (assoc['role'] == 'owner') {
              final profile = assoc['profiles'];
              if (profile != null) {
                ownerName = profile['full_name'] ?? '-';
                ownerMobile = profile['phone_number'] ?? '-';
              }
              break;
            }
          }
        }

        processedGyms.add({
          'id': gymMap['id'],
          'name': gymMap['name'] ?? 'Gym',
          'owner': ownerName,
          'mobile': ownerMobile,
          'status': gymMap['status'] ?? 'active',
          'created_at': gymMap['created_at'],
        });
      }

      // Check duplicates
      final List<Map<String, dynamic>> detectedAlerts = [];
      final Set<String> pairedKeys = {}; // Avoid showing A-B and B-A duplicate pairs

      for (int i = 0; i < processedGyms.length; i++) {
        final g1 = processedGyms[i];
        if (g1['name'] == 'Gym' || g1['owner'] == '-') continue;

        for (int j = i + 1; j < processedGyms.length; j++) {
          final g2 = processedGyms[j];
          if (g2['name'] == 'Gym' || g2['owner'] == '-') continue;

          bool isDup = false;
          int score = 0;
          List<String> reasons = [];

          // Rule 1: Same mobile number
          if (g1['mobile'] != '-' && g1['mobile'] != 'Unknown' && g1['mobile'] == g2['mobile']) {
            isDup = true;
            score = 95;
            reasons.add('Same Mobile Number (${g1['mobile']})');
          }

          // Rule 2: Same owner name & similar gym name
          final name1 = g1['name'].toString().toLowerCase().replaceAll(' ', '');
          final name2 = g2['name'].toString().toLowerCase().replaceAll(' ', '');
          
          if (g1['owner'].toString().toLowerCase() == g2['owner'].toString().toLowerCase() && g1['owner'] != '-') {
            if (name1.contains(name2) || name2.contains(name1)) {
              isDup = true;
              score = score > 85 ? score : 85;
              reasons.add('Same Owner Name & Similar Gym Name');
            }
          }

          // Rule 3: Similar gym name
          if (name1 == name2) {
            isDup = true;
            score = score > 90 ? score : 90;
            reasons.add('Exact Identical Gym Name');
          } else if (name1.length > 4 && name2.length > 4 && (name1.contains(name2) || name2.contains(name1))) {
            isDup = true;
            score = score > 75 ? score : 75;
            reasons.add('Similar Gym Name');
          }

          if (isDup) {
            final key = '${g1['id']}-${g2['id']}';
            final reverseKey = '${g2['id']}-${g1['id']}';
            if (!pairedKeys.contains(key) && !pairedKeys.contains(reverseKey)) {
              pairedKeys.add(key);

              final cAt = DateTime.tryParse(g1['created_at'] ?? '') ?? DateTime.now();

              detectedAlerts.add({
                'score': score,
                'time': _formatRelativeTime(cAt),
                'new': {
                  'id': g1['id'],
                  'name': g1['name'],
                  'owner': g1['owner'],
                  'mobile': g1['mobile'],
                  'status': g1['status'],
                },
                'existing': {
                  'id': g2['id'],
                  'name': g2['name'],
                  'owner': g2['owner'],
                  'mobile': g2['mobile'],
                  'status': g2['status'],
                },
                'reasons': reasons,
              });
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _alerts = detectedAlerts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error scanning duplicates: $e');
      if (mounted) {
        setState(() {
          _alerts = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateGymStatus(String gymId, String status, String message) async {
    try {
      final client = AdminSupabaseService.client;
      await client.from('gyms').update({'status': status}).eq('id', gymId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AdminTheme.success),
        );
      }
      _scanDuplicates();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  Future<void> _deleteGym(String gymId) async {
    try {
      final client = AdminSupabaseService.client;
      await client.rpc('delete_gym_cascade', params: {'p_gym_id': gymId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gym and all related data deleted successfully'), backgroundColor: AdminTheme.success),
        );
      }
      _scanDuplicates();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${e.toString()}'), backgroundColor: AdminTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);
    if (_isLoading) return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable(rows: 5));

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 300),
            childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
            children: [
              Row(
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Duplicate Detection', style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
                    const SizedBox(height: 4),
                    Text('Real-time database similarity scanner', style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context))),
                  ]),
                  const Spacer(),
                  IconButton(
                    onPressed: _scanDuplicates,
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Rescan Database',
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: AdminTheme.infoLight, borderRadius: BorderRadius.circular(AdminTheme.radiusXs)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.visibility_off_rounded, size: 14, color: AdminTheme.info),
                      const SizedBox(width: 6),
                      Text('Hidden from users', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminTheme.info)),
                    ]),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              if (_alerts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AdminTheme.cardColor(context),
                    borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
                    border: Border.all(color: AdminTheme.borderColor(context)),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.verified_user_rounded, size: 48, color: AdminTheme.success),
                        const SizedBox(height: 16),
                        Text(
                          'No Duplicate Gyms Detected',
                          style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AdminTheme.textColor(context)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Your database is fully clean.',
                          style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context)),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._alerts.map((alert) => _alertCard(context, alert)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _alertCard(BuildContext context, Map<String, dynamic> alert) {
    final score = alert['score'] as int;
    Color scoreColor = score >= 90 ? AdminTheme.danger : (score >= 70 ? AdminTheme.orange : AdminTheme.warning);
    final newGym = alert['new'] as Map<String, dynamic>;
    final existingGym = alert['existing'] as Map<String, dynamic>;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AdminTheme.dangerLight, borderRadius: BorderRadius.circular(AdminTheme.radiusXs)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.content_copy_rounded, size: 14, color: AdminTheme.danger),
                  const SizedBox(width: 5),
                  Text('Possible Duplicate', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AdminTheme.danger)),
                ]),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: scoreColor.withOpacity(0.1), borderRadius: BorderRadius.circular(AdminTheme.radiusXs)),
                child: Text('$score% match', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: scoreColor)),
              ),
              const Spacer(),
              Text(alert['time'] as String, style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context))),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _gymColumn(context, 'New Registration', newGym)),
              Container(width: 1, height: 80, color: AdminTheme.borderColor(context), margin: const EdgeInsets.symmetric(horizontal: 20)),
              Expanded(child: _gymColumn(context, 'Existing Gym', existingGym)),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8, runSpacing: 6,
            children: (alert['reasons'] as List<String>).map((r) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AdminTheme.warningLight, borderRadius: BorderRadius.circular(4)),
              child: Text(r, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFD97706))),
            )).toList(),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _actionButton(context, 'Approve Active', AdminTheme.success, Icons.check_rounded, () async {
                final confirm = await showAdminConfirmDialog(context, title: 'Approve Gym?', message: 'Set gym status to active.');
                if (confirm == true) {
                  await _updateGymStatus(newGym['id'], 'active', 'Gym approved as Active.');
                }
              }),
              const SizedBox(width: 8),
              _actionButton(context, 'Suspend', AdminTheme.orange, Icons.pause_circle_outline, () async {
                final confirm = await showAdminConfirmDialog(context, title: 'Suspend Gym?', message: 'Suspend this new registration.', isDangerous: true);
                if (confirm == true) {
                  await _updateGymStatus(newGym['id'], 'suspended', 'Gym suspended.');
                }
              }),
              const SizedBox(width: 8),
              _actionButton(context, 'Delete', AdminTheme.danger, Icons.delete_outline, () async {
                final confirm = await showAdminConfirmDialog(context, title: 'Delete Gym?', message: 'Permanently delete this new registration.', isDangerous: true);
                if (confirm == true) {
                  await _deleteGym(newGym['id']);
                }
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _gymColumn(BuildContext context, String label, Map<String, dynamic> data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AdminTheme.mutedTextColor(context))),
        const SizedBox(height: 8),
        Text(data['name']!.toString(), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
        const SizedBox(height: 4),
        Text('Owner: ${data['owner']}', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
        Text('Mobile: ${data['mobile']}', style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context))),
      ],
    );
  }

  Widget _actionButton(BuildContext context, String label, Color color, IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}
