import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/services/supabase_service.dart';
import '../../core/widgets/skeleton_loader.dart';

class AuditLogsScreen extends StatefulWidget {
  const AuditLogsScreen({super.key});

  @override
  State<AuditLogsScreen> createState() => _AuditLogsScreenState();
}

class _AuditLogsScreenState extends State<AuditLogsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _realLogs = [];
  final _searchController = TextEditingController();
  String _selectedCategory = 'all';

  final List<Map<String, String>> _categories = [
    {'id': 'all', 'label': 'All Activities'},
    {'id': 'database', 'label': '📦 Database & Backups'},
    {'id': 'gyms', 'label': '🏢 Gyms & Owners'},
    {'id': 'subscriptions', 'label': '💳 Subscriptions'},
    {'id': 'security', 'label': '🔒 Security & Access'},
    {'id': 'settings', 'label': '⚙️ Settings'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchRealAuditLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchRealAuditLogs() async {
    setState(() => _isLoading = true);
    try {
      if (!AdminSupabaseService.isInitialized) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final client = AdminSupabaseService.client;
      final response = await client
          .from('audit_logs')
          .select()
          .order('created_at', ascending: false)
          .limit(100);

      final List<Map<String, dynamic>> loaded = [];
      for (final item in (response as List)) {
        loaded.add(Map<String, dynamic>.from(item));
      }

      // If audit_logs has very few rows, also fetch from activity_logs for full transparency
      if (loaded.isEmpty) {
        try {
          final actRes = await client
              .from('activity_logs')
              .select('id, action, module, staff_name, created_at, target_member')
              .order('created_at', ascending: false)
              .limit(50);
          for (final item in (actRes as List)) {
            loaded.add({
              'id': item['id'],
              'action': item['action'] ?? 'Activity Recorded',
              'category': (item['module'] ?? 'general').toString().toLowerCase(),
              'admin_email': item['staff_name'] ?? 'Staff / Admin',
              'details': item['target_member'] != null ? 'Target: ${item['target_member']}' : null,
              'created_at': item['created_at'],
              'metadata': null,
            });
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _realLogs = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching audit logs: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  IconData _getIconForCategory(String? category, String action) {
    final cat = (category ?? '').toLowerCase();
    final act = action.toLowerCase();

    if (cat == 'database' || act.contains('backup') || act.contains('restore')) {
      return Icons.storage_rounded;
    }
    if (cat == 'gyms' || act.contains('gym')) {
      return Icons.fitness_center_rounded;
    }
    if (cat == 'subscriptions' || act.contains('plan') || act.contains('payment')) {
      return Icons.credit_card_rounded;
    }
    if (cat == 'security' || act.contains('login') || act.contains('auth')) {
      return Icons.shield_rounded;
    }
    if (cat == 'settings') {
      return Icons.tune_rounded;
    }
    return Icons.history_rounded;
  }

  Color _getColorForCategory(String? category, String action) {
    final cat = (category ?? '').toLowerCase();
    final act = action.toLowerCase();

    if (act.contains('error') || act.contains('fail') || act.contains('suspend') || act.contains('delete')) {
      return AdminTheme.danger;
    }
    if (act.contains('success') || act.contains('restore') || act.contains('active') || act.contains('created')) {
      return AdminTheme.success;
    }
    if (cat == 'database' || act.contains('backup')) {
      return AdminTheme.teal;
    }
    if (cat == 'subscriptions' || act.contains('plan')) {
      return AdminTheme.primary;
    }
    if (cat == 'gyms') {
      return AdminTheme.info;
    }
    return AdminTheme.orange;
  }

  String _formatTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return 'Recent';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return DateFormat('MMM d, yyyy — hh:mm a').format(dt);
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);
    if (_isLoading) {
      return Padding(padding: EdgeInsets.all(padding), child: const SkeletonTable(rows: 8));
    }

    final query = _searchController.text.trim().toLowerCase();
    final filteredLogs = _realLogs.where((log) {
      final category = (log['category'] ?? '').toString().toLowerCase();
      if (_selectedCategory != 'all' && category != _selectedCategory) {
        return false;
      }
      if (query.isNotEmpty) {
        final action = (log['action'] ?? '').toString().toLowerCase();
        final details = (log['details'] ?? '').toString().toLowerCase();
        final admin = (log['admin_email'] ?? '').toString().toLowerCase();
        final gym = (log['gym_name'] ?? '').toString().toLowerCase();
        return action.contains(query) ||
            details.contains(query) ||
            admin.contains(query) ||
            gym.contains(query);
      }
      return true;
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: AnimationLimiter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 300),
            childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
            children: [
              // Header Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Real-Time Audit Logs',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AdminTheme.textColor(context),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: AdminTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AdminTheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: AdminTheme.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Live (${_realLogs.length} events)',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AdminTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '100% Real, verifiable database activity and administrator actions',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: AdminTheme.secondaryTextColor(context),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Refresh button
                  IconButton(
                    tooltip: 'Refresh Logs',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _fetchRealAuditLogs,
                    style: IconButton.styleFrom(
                      backgroundColor: AdminTheme.cardColor(context),
                      side: BorderSide(color: AdminTheme.borderColor(context)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Search
                  SizedBox(
                    width: 260,
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search live logs...',
                        hintStyle: GoogleFonts.inter(fontSize: 13, color: AdminTheme.mutedTextColor(context)),
                        prefixIcon: Icon(Icons.search, size: 18, color: AdminTheme.mutedTextColor(context)),
                        filled: true,
                        fillColor: AdminTheme.surfaceColor(context),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
                          borderSide: BorderSide(color: AdminTheme.borderColor(context)),
                        ),
                      ),
                      style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Category Filter Pills
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categories.map((cat) {
                    final isSelected = _selectedCategory == cat['id'];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(
                          cat['label']!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected ? Colors.white : AdminTheme.secondaryTextColor(context),
                          ),
                        ),
                        selectedColor: AdminTheme.primary,
                        backgroundColor: AdminTheme.cardColor(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected ? AdminTheme.primary : AdminTheme.borderColor(context),
                          ),
                        ),
                        showCheckmark: false,
                        onSelected: (val) {
                          setState(() => _selectedCategory = cat['id']!);
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),

              // Log Container List
              Container(
                decoration: BoxDecoration(
                  color: AdminTheme.cardColor(context),
                  borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
                  border: Border.all(color: AdminTheme.borderColor(context)),
                ),
                child: filteredLogs.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.history_toggle_off_rounded, size: 48, color: AdminTheme.mutedTextColor(context)),
                              const SizedBox(height: 12),
                              Text(
                                _realLogs.isEmpty
                                    ? 'No audit logs recorded yet in database'
                                    : 'No logs match your search or filter',
                                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AdminTheme.textColor(context)),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Real logs will be recorded whenever you create backups, modify gyms, update plans, or configure settings.',
                                style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context)),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: filteredLogs.asMap().entries.map((e) {
                          return _logEntry(context, e.value, e.key == filteredLogs.length - 1);
                        }).toList(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logEntry(BuildContext context, Map<String, dynamic> log, bool isLast) {
    final action = log['action'] as String? ?? 'Admin Action';
    final category = log['category'] as String? ?? 'general';
    final color = _getColorForCategory(category, action);
    final icon = _getIconForCategory(category, action);
    final details = log['details'] as String?;
    final adminEmail = log['admin_email'] as String? ?? 'Super Admin';
    final gymName = log['gym_name'] as String?;
    final timeStr = _formatTimestamp(log['created_at'] as String?);
    final metadata = log['metadata'];

    return InkWell(
      onTap: metadata != null
          ? () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AdminTheme.cardColor(context),
                  title: Text(action, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (details != null) ...[
                        Text(details, style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context))),
                        const SizedBox(height: 12),
                      ],
                      Text('Metadata / Payload:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AdminTheme.mutedTextColor(context))),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AdminTheme.surfaceColor(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AdminTheme.borderColor(context)),
                        ),
                        child: Text(
                          metadata.toString(),
                          style: GoogleFonts.firaCode(fontSize: 11, color: AdminTheme.textColor(context)),
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                  ],
                ),
              );
            }
          : null,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: AdminTheme.borderColor(context))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          action,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AdminTheme.textColor(context),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AdminTheme.surfaceColor(context),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AdminTheme.borderColor(context)),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AdminTheme.mutedTextColor(context),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (details != null && details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline_rounded, size: 14, color: AdminTheme.mutedTextColor(context)),
                          const SizedBox(width: 4),
                          Text(
                            adminEmail,
                            style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule_rounded, size: 14, color: AdminTheme.mutedTextColor(context)),
                          const SizedBox(width: 4),
                          Text(
                            timeStr,
                            style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                          ),
                        ],
                      ),
                      if (gymName != null && gymName.isNotEmpty)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fitness_center_rounded, size: 14, color: AdminTheme.mutedTextColor(context)),
                            const SizedBox(width: 4),
                            Text(
                              gymName,
                              style: GoogleFonts.inter(fontSize: 11, color: AdminTheme.mutedTextColor(context)),
                            ),
                          ],
                        ),
                      if (metadata != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.info_outline_rounded, size: 13, color: AdminTheme.primary),
                            const SizedBox(width: 3),
                            Text(
                              'Details Available',
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AdminTheme.primary),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
