import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/constants/app_constants.dart';

import '../../core/services/supabase_service.dart';
import 'admin_gym_dashboard_screen.dart';

class GymsScreen extends StatefulWidget {
  const GymsScreen({super.key});

  @override
  State<GymsScreen> createState() => _GymsScreenState();
}

class _GymsScreenState extends State<GymsScreen> {
  bool _isLoading = true;
  String _selectedFilter = 'all';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _gyms = [];

  @override
  void initState() {
    super.initState();
    _fetchGyms();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchGyms() async {
    try {
      if (!mounted) return;
      setState(() => _isLoading = true);

      if (!AdminSupabaseService.isInitialized) {
        await AdminSupabaseService.initialize();
      }

      if (!AdminSupabaseService.isInitialized) {
        setState(() {
          _gyms = [];
          _isLoading = false;
        });
        return;
      }
      final client = AdminSupabaseService.client;
      
      final response = await client
          .from('gyms')
          .select('*, members(count), staff(count), user_gym_associations(role, user_id, profiles(full_name, phone_number))');
      
      List<Map<String, dynamic>> allSubs = [];
      try {
        final subsRes = await client.from('subscriptions').select('*');
        if (subsRes is List) {
          allSubs = subsRes.map((e) => Map<String, dynamic>.from(e)).toList();
        }
      } catch (e) {
        debugPrint('Warning: Could not fetch subscriptions table ($e). Falling back to gyms table dates.');
      }
      
      final List<Map<String, dynamic>> loadedGyms = [];
      for (var item in response as List) {
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
        
        final membersCount = (gymMap['members'] as List?)?.firstOrNull?['count'] ?? 0;
        final staffCount = (gymMap['staff'] as List?)?.firstOrNull?['count'] ?? 0;
        
        final subMap = allSubs.firstWhere(
          (s) => s['gym_id'] == gymMap['id'],
          orElse: () => <String, dynamic>{},
        );

        String trialLeftStr = '-';
        String expiryStr = '-';
        final effectiveExpiryStr = subMap['end_date'] ?? subMap['trial_end'] ?? gymMap['expiry_date'] ?? gymMap['trial_end_date'];
        if (effectiveExpiryStr != null) {
          final endDate = DateTime.tryParse(effectiveExpiryStr.toString());
          if (endDate != null) {
            final diff = endDate.difference(DateTime.now()).inDays;
            trialLeftStr = diff > 0 ? '$diff days' : 'Expired';
            expiryStr = endDate.toLocal().toString().split(' ')[0];
          }
        }
        
        String lastLoginStr = 'Never';
        if (gymMap['last_login_at'] != null) {
          final date = DateTime.tryParse(gymMap['last_login_at']);
          if (date != null) {
            final diff = DateTime.now().difference(date);
            if (diff.inMinutes < 60) {
              lastLoginStr = '${diff.inMinutes}m ago';
            } else if (diff.inHours < 24) {
              lastLoginStr = '${diff.inHours}h ago';
            } else {
              lastLoginStr = '${diff.inDays}d ago';
            }
          }
        }

        loadedGyms.add({
          'id': gymMap['id'],
          'name': gymMap['name'] ?? 'Unnamed Gym',
          'owner': ownerName,
          'email': gymMap['email'] ?? '-',
          'mobile': ownerMobile != '-' ? ownerMobile : (gymMap['phone_number'] ?? '-'),
          'plan': PlatformPlan.displayName(gymMap['plan'] ?? 'free_trial'),
          'rawPlan': gymMap['plan'] ?? 'free_trial',
          'status': gymMap['status'] ?? 'trial',
          'trialLeft': trialLeftStr,
          'expiry': expiryStr,
          'members': membersCount,
          'staff': staffCount,
          'lastLogin': lastLoginStr,
          'appVersion': gymMap['app_version'] ?? 'v2.4.1',
          'notes': gymMap['notes'] ?? '',
          'is_locked': gymMap['is_locked'] ?? false,
          'rawGym': gymMap,
        });
      }

      if (!mounted) return;
      setState(() {
        _gyms = loadedGyms;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching gyms from Supabase: $e');
      if (mounted) {
        setState(() {
          _gyms = [];
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredGyms {
    var gyms = List<Map<String, dynamic>>.from(_gyms);
    if (_selectedFilter != 'all') {
      gyms = gyms.where((g) => g['status'] == _selectedFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      gyms = gyms.where((g) =>
        (g['name'] as String).toLowerCase().contains(q) ||
        (g['owner'] as String).toLowerCase().contains(q) ||
        (g['email'] as String).toLowerCase().contains(q) ||
        (g['mobile'] as String).contains(q)
      ).toList();
    }
    return gyms;
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);

    if (_isLoading) {
      return Padding(
        padding: EdgeInsets.all(padding),
        child: const SkeletonTable(rows: 8),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 300),
            childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
            children: [
              // Header
              _buildHeader(context),
              const SizedBox(height: 20),
              // Status filter chips
              _buildFilterChips(context),
              const SizedBox(height: 20),
              // Data table
              _buildDataTable(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gym Management',
                style: GoogleFonts.inter(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AdminTheme.textColor(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_filteredGyms.length} gyms found',
                style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context)),
              ),
            ],
          ),
        ),
        // Search bar
        SizedBox(
          width: AdminResponsive.isMobile(context) ? 180 : 280,
          height: 40,
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search gyms...',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: AdminTheme.mutedTextColor(context)),
              prefixIcon: Icon(Icons.search_rounded, size: 18, color: AdminTheme.mutedTextColor(context)),
              filled: true,
              fillColor: AdminTheme.surfaceColor(context),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
                borderSide: BorderSide.none,
              ),
            ),
            style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context)),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    final filters = [
      {'key': 'all', 'label': 'All', 'count': _gyms.length},
      {'key': GymStatus.trial, 'label': 'Trial', 'count': _gyms.where((g) => g['status'] == GymStatus.trial).length},
      {'key': GymStatus.active, 'label': 'Active', 'count': _gyms.where((g) => g['status'] == GymStatus.active).length},
      {'key': GymStatus.gracePeriod, 'label': 'Grace Period', 'count': _gyms.where((g) => g['status'] == GymStatus.gracePeriod).length},
      {'key': GymStatus.suspended, 'label': 'Suspended', 'count': _gyms.where((g) => g['status'] == GymStatus.suspended).length},
      {'key': GymStatus.disabled, 'label': 'Disabled', 'count': _gyms.where((g) => g['status'] == GymStatus.disabled).length},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isActive = _selectedFilter == f['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(AdminTheme.radiusXl),
              onTap: () => setState(() => _selectedFilter = f['key'] as String),
              child: AnimatedContainer(
                duration: AdminTheme.animFast,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? AdminTheme.primary.withValues(alpha: AdminTheme.isDark(context) ? 0.2 : 0.1)
                      : AdminTheme.surfaceColor(context),
                  borderRadius: BorderRadius.circular(AdminTheme.radiusXl),
                  border: Border.all(
                    color: isActive ? AdminTheme.primary.withValues(alpha: 0.4) : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      f['label'] as String,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                        color: isActive ? AdminTheme.primary : AdminTheme.secondaryTextColor(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isActive
                            ? AdminTheme.primary.withValues(alpha: 0.15)
                            : AdminTheme.borderColor(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${f['count']}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isActive ? AdminTheme.primary : AdminTheme.mutedTextColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDataTable(BuildContext context) {
    final gyms = _filteredGyms;
    if (gyms.isEmpty) {
      return const EmptyState(
        icon: Icons.fitness_center_outlined,
        title: 'No gyms found',
        subtitle: 'Try adjusting your filters or search query.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStatePropertyAll(AdminTheme.surfaceColor(context)),
            headingTextStyle: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AdminTheme.secondaryTextColor(context),
            ),
            dataTextStyle: GoogleFonts.inter(
              fontSize: 13,
              color: AdminTheme.textColor(context),
            ),
            columnSpacing: 20,
            horizontalMargin: 20,
            dataRowMinHeight: 56,
            dataRowMaxHeight: 56,
            columns: const [
              DataColumn(label: Text('GYM NAME')),
              DataColumn(label: Text('OWNER')),
              DataColumn(label: Text('MOBILE')),
              DataColumn(label: Text('PLAN')),
              DataColumn(label: Text('STATUS')),
              DataColumn(label: Text('TRIAL LEFT')),
              DataColumn(label: Text('EXPIRY')),
              DataColumn(label: Text('MEMBERS')),
              DataColumn(label: Text('STAFF')),
              DataColumn(label: Text('LAST LOGIN')),
              DataColumn(label: Text('ACTIONS')),
            ],
            rows: gyms.map((gym) => DataRow(
              onSelectChanged: (selected) {
                 if (selected == true) {
                   Navigator.push(
                     context,
                     MaterialPageRoute(
                       builder: (context) => AdminGymDashboardScreen(gym: gym),
                     ),
                   );
                 }
               },
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AdminTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            (gym['name'] as String)[0],
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              color: AdminTheme.primary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            gym['name'] as String,
                            style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          Text(
                            gym['email'] as String,
                            style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                DataCell(Text(gym['owner'] as String)),
                DataCell(Text(gym['mobile'] as String)),
                DataCell(_buildPlanBadge(gym['plan'] as String)),
                DataCell(AdminStatusBadge.fromGymStatus(gym['status'] as String)),
                DataCell(Text(gym['trialLeft'] as String)),
                DataCell(Text(gym['expiry'] as String)),
                DataCell(Text('${gym['members']}')),
                DataCell(Text('${gym['staff']}')),
                DataCell(Text(gym['lastLogin'] as String)),
                DataCell(_buildActionsButton(context, gym)),
              ],
            )).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanBadge(String plan) {
    Color color;
    switch (plan) {
      case 'Business': color = AdminTheme.success; break;
      case 'Pro': color = AdminTheme.info; break;
      case 'Starter': color = AdminTheme.primary; break;
      default: color = AdminTheme.warning; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AdminTheme.radiusXs),
      ),
      child: Text(
        plan,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildActionsButton(BuildContext context, Map<String, dynamic> gym) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz_rounded, size: 20, color: AdminTheme.secondaryTextColor(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusCard)),
      offset: const Offset(0, 40),
      itemBuilder: (ctx) {
        final status = (gym['status'] as String? ?? 'active').toLowerCase();
        final isSuspended = status == 'suspended';
        final isLocked = gym['is_locked'] == true;
        return [
          _popupItem(Icons.visibility_outlined, 'View Gym', 'view'),
          _popupItem(Icons.swap_horiz_rounded, 'Change Plan', 'change_plan'),
          isLocked
              ? _popupItem(Icons.lock_open_rounded, 'Unlock Gym', 'unlock_gym', color: AdminTheme.success)
              : _popupItem(Icons.lock_outline_rounded, 'Lock Gym', 'lock_gym', color: AdminTheme.orange),
          _popupItem(Icons.timer_outlined, 'Extend Trial', 'extend_trial'),
          _popupItem(Icons.date_range_outlined, 'Edit Expiry', 'edit_expiry'),
          const PopupMenuDivider(),
          _popupItem(Icons.check_circle_outlined, 'Activate', 'activate'),
          isSuspended
              ? _popupItem(Icons.play_circle_outline_rounded, 'Unsuspend', 'unsuspend', color: AdminTheme.success)
              : _popupItem(Icons.pause_circle_outlined, 'Suspend', 'suspend', color: AdminTheme.orange),
          _popupItem(Icons.block_rounded, 'Disable', 'disable', color: AdminTheme.danger),
          const PopupMenuDivider(),
          _popupItem(Icons.notifications_outlined, 'Send Notification', 'notify'),
          _popupItem(Icons.payment_outlined, 'Manual Payment', 'payment'),
          _popupItem(Icons.history_rounded, 'Payment History', 'payment_history'),
          _popupItem(Icons.note_add_outlined, 'Add Note', 'add_note'),
          const PopupMenuDivider(),
          _popupItem(Icons.delete_outline_rounded, 'Delete Gym', 'delete', color: AdminTheme.danger),
        ];
      },
      onSelected: (value) => _handleAction(context, value, gym),
    );
  }

  PopupMenuItem<String> _popupItem(IconData icon, String label, String value, {Color? color}) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? AdminTheme.secondaryTextColor(context)),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: color)),
        ],
      ),
    );
  }

  void _handleAction(BuildContext context, String action, Map<String, dynamic> gym) async {
    final gymName = gym['name'] as String;
    final gymId = gym['id'];
    final client = AdminSupabaseService.isInitialized ? AdminSupabaseService.client : null;

    switch (action) {
      case 'view':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdminGymDashboardScreen(gym: gym),
          ),
        );
        break;
      case 'lock_gym':
        final confirmedLock = await showAdminConfirmDialog(context,
          title: 'Lock $gymName?',
          message: 'This will lock all dashboard functionalities for the owner, receptionist, and staff. They will see the locked screen.',
          confirmText: 'Lock Gym',
          isDangerous: true,
          icon: Icons.lock_outline_rounded,
        );
        if (confirmedLock == true) {
          try {
            if (client != null && gymId != null) {
              await client.from('gyms').update({'is_locked': true}).eq('id', gymId);
            } else {
              final index = _gyms.indexWhere((g) => g['id'] == gymId);
              if (index != -1) {
                setState(() {
                  _gyms[index]['is_locked'] = true;
                });
              }
            }
            await _fetchGyms();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$gymName has been locked'), backgroundColor: AdminTheme.orange),
            );
          } catch (e) {
            final errStr = e.toString();
            if (errStr.contains('column "is_locked" does not exist') || errStr.contains('is_locked')) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Database Update Required'),
                  content: const Text('Please run the provided SQL code in your Supabase SQL Editor first:\n\nALTER TABLE public.gyms ADD COLUMN is_locked BOOLEAN DEFAULT false;'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('OK'),
                    )
                  ],
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to lock gym: $e'), backgroundColor: Colors.red),
              );
            }
          }
        }
        break;
      case 'unlock_gym':
        final confirmedUnlock = await showAdminConfirmDialog(context,
          title: 'Unlock $gymName?',
          message: 'This will restore dashboard access immediately.',
          confirmText: 'Unlock Gym',
          isDangerous: false,
          icon: Icons.lock_open_rounded,
        );
        if (confirmedUnlock == true) {
          try {
            if (client != null && gymId != null) {
              await client.from('gyms').update({'is_locked': false}).eq('id', gymId);
            } else {
              final index = _gyms.indexWhere((g) => g['id'] == gymId);
              if (index != -1) {
                setState(() {
                  _gyms[index]['is_locked'] = false;
                });
              }
            }
            await _fetchGyms();
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$gymName has been unlocked'), backgroundColor: AdminTheme.success),
            );
          } catch (e) {
            final errStr = e.toString();
            if (errStr.contains('column "is_locked" does not exist') || errStr.contains('is_locked')) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Database Update Required'),
                  content: const Text('Please run the provided SQL code in your Supabase SQL Editor first:\n\nALTER TABLE public.gyms ADD COLUMN is_locked BOOLEAN DEFAULT false;'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('OK'),
                    )
                  ],
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to unlock gym: $e'), backgroundColor: Colors.red),
              );
            }
          }
        }
        break;
      case 'change_plan':
        if (!context.mounted) return;
        final selectedPlan = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text('Select Plan for $gymName', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'free_trial'),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Free Trial', style: GoogleFonts.inter())),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'starter'),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Starter', style: GoogleFonts.inter())),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'pro'),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Pro', style: GoogleFonts.inter())),
              ),
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, 'business'),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text('Business', style: GoogleFonts.inter())),
              ),
            ],
          ),
        );
        if (selectedPlan != null) {
          if (client != null && gymId != null) {
            await client.from('gyms').update({'plan': selectedPlan}).eq('id', gymId);
            try {
              await client.from('subscriptions').update({
                'plan_id': selectedPlan,
                'status': selectedPlan == 'free_trial' ? 'trial' : 'active'
              }).eq('gym_id', gymId);
            } catch (e) {
              debugPrint('Error updating subscriptions table on plan change: $e');
            }
            _fetchGyms();
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Plan changed to ${PlatformPlan.displayName(selectedPlan)}'), backgroundColor: AdminTheme.success),
          );
        }
        break;
      case 'suspend':
        final confirmedSuspend = await showAdminConfirmDialog(context,
          title: 'Suspend $gymName?',
          message: 'The gym owner will have limited access. Members & staff can still view their profiles but attendance will stop.',
          confirmText: 'Suspend',
          isDangerous: true,
          icon: Icons.pause_circle_outline_rounded,
        );
        if (confirmedSuspend == true) {
          if (client != null && gymId != null) {
            await client.from('gyms').update({'status': 'suspended'}).eq('id', gymId);
            try {
              await client.from('subscriptions').update({'status': 'failed_payment'}).eq('gym_id', gymId);
            } catch (e) {
              debugPrint('Error updating subscriptions table on suspend: $e');
            }
            _fetchGyms();
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$gymName has been suspended'), backgroundColor: AdminTheme.orange),
          );
        }
        break;
      case 'unsuspend':
        final confirmedUnsuspend = await showAdminConfirmDialog(context,
          title: 'Unsuspend $gymName?',
          message: 'This will restore full access immediately to the gym owner and staff.',
          confirmText: 'Unsuspend',
          isDangerous: false,
          icon: Icons.play_circle_outline_rounded,
        );
        if (confirmedUnsuspend == true) {
          if (client != null && gymId != null) {
            await client.from('gyms').update({'status': 'active'}).eq('id', gymId);
            try {
              final currentSub = await client.from('subscriptions').select('plan_id').eq('gym_id', gymId).maybeSingle();
              final planId = currentSub?['plan_id'] as String? ?? 'free_trial';
              await client.from('subscriptions').update({
                'status': planId == 'free_trial' ? 'trial' : 'active'
              }).eq('gym_id', gymId);
            } catch (e) {
              debugPrint('Error updating subscriptions table on unsuspend: $e');
            }
            _fetchGyms();
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$gymName has been unsuspended'), backgroundColor: AdminTheme.success),
          );
        }
        break;
      case 'disable':
        final confirmedDisable = await showAdminConfirmDialog(context,
          title: 'Disable $gymName?',
          message: 'Only Super Admin can re-enable. The owner will see only a disabled message. Select a reason for disabling.',
          confirmText: 'Disable',
          isDangerous: true,
          icon: Icons.block_rounded,
        );
        if (confirmedDisable == true) {
          if (client != null && gymId != null) {
            await client.from('gyms').update({'status': 'disabled', 'disabled_reason': 'Terms Violation'}).eq('id', gymId);
            try {
              await client.from('subscriptions').update({'status': 'cancelled'}).eq('gym_id', gymId);
            } catch (e) {
              debugPrint('Error updating subscriptions table on disable: $e');
            }
            _fetchGyms();
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$gymName has been disabled'), backgroundColor: AdminTheme.danger),
          );
        }
        break;
      case 'delete':
        final confirmedDelete = await showAdminConfirmDialog(context,
          title: 'Delete $gymName?',
          message: 'This will permanently remove all gym data including members, staff, attendance, and transactions. All gym users (owner, staff, members) will be force-logged out. Payments history will be kept. This action cannot be undone.',
          confirmText: 'Delete Forever',
          isDangerous: true,
          icon: Icons.delete_forever_rounded,
        );
        if (confirmedDelete == true) {
          if (client != null && gymId != null) {
            try {
              final result = await client.rpc('delete_gym_cascade', params: {
                'p_gym_id': gymId,
              });
              _fetchGyms();
              if (!context.mounted) return;
              final data = result as Map<String, dynamic>?;
              final membersDeleted = data?['members_deleted'] ?? 0;
              final staffDeleted = data?['staff_deleted'] ?? 0;
              final usersLoggedOut = data?['users_logged_out'] ?? 0;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$gymName deleted • $membersDeleted members, $staffDeleted staff removed • $usersLoggedOut users logged out'),
                  backgroundColor: AdminTheme.danger,
                  duration: const Duration(seconds: 5),
                ),
              );
            } catch (e) {
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Delete failed: $e'),
                  backgroundColor: AdminTheme.danger,
                ),
              );
            }
          }
        }
        break;
      case 'activate':
        if (client != null && gymId != null) {
          await client.from('gyms').update({
            'status': 'active',
            'expiry_date': DateTime.now().add(const Duration(days: 30)).toIso8601String()
          }).eq('id', gymId);
          try {
            await client.from('subscriptions').update({
              'status': 'active',
              'end_date': DateTime.now().add(const Duration(days: 30)).toIso8601String()
            }).eq('gym_id', gymId);
          } catch (e) {
            debugPrint('Error updating subscriptions table on activate: $e');
          }
          _fetchGyms();
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$gymName has been activated'), backgroundColor: AdminTheme.success),
        );
      case 'extend_trial':
        final rawGym = gym['rawGym'] as Map<String, dynamic>? ?? gym;
        final currentTrialEndStr = rawGym['expiry_date'] ?? rawGym['trial_end_date'] ?? (gym['expiry'] != '-' ? gym['expiry'] : null);
        DateTime baseDate = DateTime.now();
        if (currentTrialEndStr != null) {
          final parsed = DateTime.tryParse(currentTrialEndStr.toString());
          if (parsed != null && parsed.isAfter(DateTime.now())) {
            baseDate = parsed;
          }
        }

        if (!context.mounted) return;
        final result = await showDialog<Map<String, dynamic>>(
          context: context,
          builder: (ctx) {
            final TextEditingController valController = TextEditingController(text: '30');
            String unit = 'days';
            return StatefulBuilder(
              builder: (context, setDialogState) {
                return AlertDialog(
                  title: Text('Extend Trial for $gymName', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Current Expiry: ${currentTrialEndStr != null ? (DateTime.tryParse(currentTrialEndStr.toString())?.toIso8601String().split('T')[0] ?? currentTrialEndStr.toString().split(' ')[0]) : "Not Set"}',
                        style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context)),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: valController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Duration',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<String>(
                            value: unit,
                            items: ['days', 'months']
                                .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setDialogState(() => unit = val);
                              }
                            },
                          )
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final val = int.tryParse(valController.text);
                        if (val != null && val > 0) {
                          Navigator.pop(ctx, {'value': val, 'unit': unit});
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary),
                      child: const Text('Extend'),
                    )
                  ],
                );
              }
            );
          }
        );

        if (result != null) {
          final int value = result['value'];
          final String unit = result['unit'];
          DateTime newExpiry = baseDate;
          if (unit == 'days') {
            newExpiry = baseDate.add(Duration(days: value));
          } else {
            newExpiry = DateTime(baseDate.year, baseDate.month + value, baseDate.day);
          }

          if (client != null && gymId != null) {
            await client.from('gyms').update({
              'trial_end_date': newExpiry.toIso8601String(),
              'expiry_date': newExpiry.toIso8601String(),
              'plan': 'free_trial',
              'status': 'trial'
            }).eq('id', gymId);
            
            try {
              await client.from('subscriptions').update({
                'trial_end': newExpiry.toIso8601String(),
                'end_date': newExpiry.toIso8601String(),
                'status': 'trial',
                'plan_id': 'free_trial'
              }).eq('gym_id', gymId);
            } catch (e) {
              debugPrint('Error updating subscriptions on trial extend: $e');
            }
            await _fetchGyms();
          } else {
            final index = _gyms.indexWhere((g) => g['id'] == gymId);
            if (index != -1) {
              setState(() {
                _gyms[index]['trialLeft'] = '${newExpiry.difference(DateTime.now()).inDays} days';
                _gyms[index]['expiry'] = newExpiry.toLocal().toString().split(' ')[0];
                _gyms[index]['plan'] = 'Free Trial';
                _gyms[index]['status'] = 'trial';
              });
            }
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Trial extended until ${newExpiry.toIso8601String().split('T')[0]}'), backgroundColor: AdminTheme.success),
          );
        }
        break;
      case 'edit_expiry':
        final rawGymMap = gym['rawGym'] as Map<String, dynamic>? ?? gym;
        final subMap = (rawGymMap['subscriptions'] as List?)?.firstOrNull;
        final currentExpiryStr = subMap?['end_date'] ?? subMap?['trial_end'] ?? rawGymMap['expiry_date'] ?? rawGymMap['trial_end_date'] ?? gym['expiry'];
        
        DateTime initialDate = DateTime.now().add(const Duration(days: 30));
        if (currentExpiryStr != null && currentExpiryStr.toString() != '-') {
          final parsed = DateTime.tryParse(currentExpiryStr.toString());
          if (parsed != null) {
            initialDate = parsed;
          }
        }

        if (!context.mounted) return;
        final DateTime? pickedDate = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
          helpText: 'Select Expiry Date for $gymName',
        );

        if (pickedDate != null) {
          final newDateIso = pickedDate.toIso8601String();
          final bool isActive = pickedDate.isAfter(DateTime.now());

          if (client != null && gymId != null) {
            await client.from('gyms').update({
              'expiry_date': newDateIso,
              'trial_end_date': newDateIso,
              'status': isActive ? (gym['status'] == 'trial' ? 'trial' : 'active') : 'grace_period'
            }).eq('id', gymId);
            
            try {
              String ownerId = '';
              final assoc = rawGymMap['user_gym_associations'] as List?;
              if (assoc != null) {
                for (var a in assoc) {
                  if (a['role'] == 'owner' && a['user_id'] != null) {
                    ownerId = a['user_id'].toString();
                    break;
                  }
                }
              }

              if (ownerId.isNotEmpty) {
                await client.from('subscriptions').upsert(
                  {
                    'gym_id': gymId,
                    'owner_id': ownerId,
                    'end_date': newDateIso,
                    'trial_end': newDateIso,
                    'status': isActive ? (gym['status'] == 'trial' ? 'trial' : 'active') : 'expired',
                    'updated_at': DateTime.now().toIso8601String(),
                  },
                  onConflict: 'gym_id',
                );
              } else {
                await client.from('subscriptions').update({
                  'end_date': newDateIso,
                  'trial_end': newDateIso,
                  'status': isActive ? (gym['status'] == 'trial' ? 'trial' : 'active') : 'expired',
                  'updated_at': DateTime.now().toIso8601String(),
                }).eq('gym_id', gymId);
              }
            } catch (e) {
              debugPrint('Error updating subscriptions on edit expiry: $e');
            }
          }
          await _fetchGyms();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Subscription expiry set to ${pickedDate.toString().split(' ')[0]}'), backgroundColor: AdminTheme.success),
          );
        }
        break;
      case 'payment_history':
        _showPaymentHistoryDialog(context, gym);
        break;
      case 'payment':
        _showManualPaymentDialog(context, gym);
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action: $action on $gymName')),
        );
    }
  }

  Future<List<Map<String, dynamic>>> _fetchGymPaymentHistory(dynamic gymId) async {
    if (!AdminSupabaseService.isInitialized || gymId == null) return [];
    final client = AdminSupabaseService.client;
    List<Map<String, dynamic>> items = [];
    try {
      final paymentsRes = await client
          .from('payments')
          .select('*')
          .eq('gym_id', gymId)
          .order('created_at', ascending: false);
      if (paymentsRes is List) {
        items.addAll(paymentsRes.map((e) => Map<String, dynamic>.from(e)));
      }
    } catch (e) {
      debugPrint('Error fetching payments for gym $gymId: $e');
    }

    if (items.isEmpty) {
      try {
        final invRes = await client
            .from('invoices')
            .select('*')
            .eq('gym_id', gymId)
            .order('created_at', ascending: false);
        if (invRes is List) {
          for (var inv in invRes) {
            items.add({
              'id': inv['id'],
              'amount': inv['amount'],
              'status': inv['status'] == 'paid' ? 'Success' : inv['status'],
              'payment_method': 'Online Invoice (${inv['invoice_number'] ?? "Invoice"})',
              'created_at': inv['created_at'] ?? inv['billing_date'],
            });
          }
        }
      } catch (_) {}
    }
    return items;
  }

  Future<void> _showPaymentHistoryDialog(BuildContext context, Map<String, dynamic> gym) async {
    final gymName = gym['name'] as String;
    final gymId = gym['id'];

    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchGymPaymentHistory(gymId),
          builder: (context, snapshot) {
            final isLoading = snapshot.connectionState == ConnectionState.waiting;
            final payments = snapshot.data ?? [];

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.history_rounded, color: AdminTheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Payment History - $gymName',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                height: 380,
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : (payments.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 12),
                                Text(
                                  'No payment history found for $gymName',
                                  style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: payments.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final item = payments[i];
                              final amount = item['amount'] ?? 0;
                              final status = (item['status'] ?? 'Success').toString().toUpperCase();
                              final method = item['payment_method'] ?? 'Razorpay Gateway';
                              final razorpayId = item['razorpay_payment_id'] ?? item['id'] ?? '-';
                              final dateStr = item['created_at'] != null
                                  ? DateTime.tryParse(item['created_at'].toString())?.toLocal().toString().split('.')[0] ?? item['created_at']
                                  : '-';

                              final bool isSuccess = status == 'SUCCESS' || status == 'PAID';

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                leading: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: isSuccess ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isSuccess ? Icons.check_circle_rounded : Icons.cancel_rounded,
                                    color: isSuccess ? Colors.green : Colors.red,
                                    size: 20,
                                  ),
                                ),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('₹$amount', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isSuccess ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        status,
                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: isSuccess ? Colors.green[800] : Colors.red[800]),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Method: $method\nTxn ID: $razorpayId  •  $dateStr',
                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.grey[600]),
                                  ),
                                ),
                              );
                            },
                          )),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showManualPaymentDialog(BuildContext context, Map<String, dynamic> gym) {
    final gymName = gym['name'] as String;
    final gymId = gym['id'];
    final TextEditingController amountController = TextEditingController(text: '699');
    String selectedMethod = 'Bank Transfer';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.payment_rounded, color: AdminTheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Record Manual Payment - $gymName', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Amount (₹)', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(border: OutlineInputBorder(), prefixText: '₹ '),
              ),
              const SizedBox(height: 16),
              Text('Payment Method', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedMethod,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer (NEFT/IMPS)')),
                  DropdownMenuItem(value: 'Cash', child: Text('Cash Payment')),
                  DropdownMenuItem(value: 'UPI / Direct', child: Text('Direct UPI')),
                  DropdownMenuItem(value: 'Other Manual', child: Text('Other Payment Method')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedMethod = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.primary),
              onPressed: () async {
                final double? amt = double.tryParse(amountController.text);
                if (amt != null && amt > 0 && gymId != null && AdminSupabaseService.isInitialized) {
                  Navigator.pop(ctx);
                  try {
                    final client = AdminSupabaseService.client;
                    final txnId = 'MANUAL-${DateTime.now().millisecondsSinceEpoch}';

                    await client.from('payments').insert({
                      'gym_id': gymId,
                      'amount': amt,
                      'status': 'Success',
                      'payment_method': selectedMethod,
                      'razorpay_payment_id': txnId,
                    });

                    final newEndDate = DateTime.now().add(const Duration(days: 30)).toIso8601String();
                    await client.from('gyms').update({
                      'expiry_date': newEndDate,
                      'status': 'active',
                    }).eq('id', gymId);

                    await client.from('subscriptions').update({
                      'end_date': newEndDate,
                      'status': 'active',
                    }).eq('gym_id', gymId);

                    await _fetchGyms();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Manual payment ₹$amt recorded successfully!'), backgroundColor: Colors.green),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to record payment: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: Text('Record Payment', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showGymDetailSheet(BuildContext context, Map<String, dynamic> gym) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusLg)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(
                        color: AdminTheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          (gym['name'] as String)[0],
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AdminTheme.primary, fontSize: 22),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(gym['name'] as String, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: AdminTheme.textColor(context))),
                          const SizedBox(height: 4),
                          AdminStatusBadge.fromGymStatus(gym['status'] as String),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _detailRow('Owner', gym['owner'] as String),
                        _detailRow('Email', gym['email'] as String),
                        _detailRow('Mobile', gym['mobile'] as String),
                        _detailRow('Plan', gym['plan'] as String),
                        _detailRow('Trial Days Left', gym['trialLeft'] as String),
                        _detailRow('Expiry Date', gym['expiry'] as String),
                        _detailRow('Members', '${gym['members']}'),
                        _detailRow('Staff', '${gym['staff']}'),
                        _detailRow('Last Login', gym['lastLogin'] as String),
                        _detailRow('App Version', gym['appVersion'] as String),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.secondaryTextColor(context), fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context))),
          ),
        ],
      ),
    );
  }
}

// ── Mock Data ──
const List<Map<String, dynamic>> _mockGyms = [
  {'name': 'Iron Paradise', 'owner': 'Rahul Sharma', 'email': 'rahul@ironparadise.com', 'mobile': '9876543210', 'plan': 'Pro', 'status': 'active', 'trialLeft': '-', 'expiry': '2027-03-15', 'members': 245, 'staff': 12, 'lastLogin': '2h ago', 'appVersion': 'v2.4.1'},
  {'name': 'FitZone Premium', 'owner': 'Priya Patel', 'email': 'priya@fitzone.in', 'mobile': '9876543211', 'plan': 'Business', 'status': 'active', 'trialLeft': '-', 'expiry': '2027-06-20', 'members': 520, 'staff': 25, 'lastLogin': '30m ago', 'appVersion': 'v2.4.1'},
  {'name': 'Power House Gym', 'owner': 'Amit Kumar', 'email': 'amit@powerhouse.com', 'mobile': '9876543212', 'plan': 'Free Trial', 'status': 'trial', 'trialLeft': '18 days', 'expiry': '-', 'members': 45, 'staff': 3, 'lastLogin': '1d ago', 'appVersion': 'v2.4.0'},
  {'name': 'Muscle Factory', 'owner': 'Vikram Singh', 'email': 'vikram@musclefactory.com', 'mobile': '9876543213', 'plan': 'Starter', 'status': 'grace_period', 'trialLeft': '-', 'expiry': '2026-07-28', 'members': 120, 'staff': 6, 'lastLogin': '3d ago', 'appVersion': 'v2.3.9'},
  {'name': 'CrossFit Arena', 'owner': 'Neha Gupta', 'email': 'neha@crossfitarena.com', 'mobile': '9876543214', 'plan': 'Pro', 'status': 'suspended', 'trialLeft': '-', 'expiry': '2026-07-01', 'members': 180, 'staff': 8, 'lastLogin': '7d ago', 'appVersion': 'v2.4.0'},
  {'name': 'Yoga Bliss Center', 'owner': 'Sanjay Verma', 'email': 'sanjay@yogabliss.com', 'mobile': '9876543215', 'plan': 'Starter', 'status': 'disabled', 'trialLeft': '-', 'expiry': '-', 'members': 65, 'staff': 4, 'lastLogin': '30d ago', 'appVersion': 'v2.3.8'},
  {'name': 'Elite Fitness', 'owner': 'Ravi Joshi', 'email': 'ravi@elitefitness.in', 'mobile': '9876543216', 'plan': 'Business', 'status': 'active', 'trialLeft': '-', 'expiry': '2027-12-01', 'members': 890, 'staff': 35, 'lastLogin': '1h ago', 'appVersion': 'v2.4.1'},
  {'name': 'Thunder Gym', 'owner': 'Kiran Desai', 'email': 'kiran@thundergym.com', 'mobile': '9876543217', 'plan': 'Free Trial', 'status': 'trial', 'trialLeft': '45 days', 'expiry': '-', 'members': 22, 'staff': 2, 'lastLogin': '5h ago', 'appVersion': 'v2.4.1'},
  {'name': 'Spartan Health Club', 'owner': 'Deepak Mehta', 'email': 'deepak@spartanclub.com', 'mobile': '9876543218', 'plan': 'Pro', 'status': 'active', 'trialLeft': '-', 'expiry': '2027-09-10', 'members': 340, 'staff': 15, 'lastLogin': '4h ago', 'appVersion': 'v2.4.1'},
  {'name': 'Flex Zone', 'owner': 'Anita Roy', 'email': 'anita@flexzone.in', 'mobile': '9876543219', 'plan': 'Starter', 'status': 'grace_period', 'trialLeft': '-', 'expiry': '2026-07-25', 'members': 78, 'staff': 5, 'lastLogin': '2d ago', 'appVersion': 'v2.4.0'},
];
