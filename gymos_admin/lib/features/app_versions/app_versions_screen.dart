import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import 'package:intl/intl.dart';
import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import '../../core/widgets/skeleton_loader.dart';
import '../../core/services/supabase_service.dart';

class AppVersionsScreen extends StatefulWidget {
  const AppVersionsScreen({super.key});
  @override
  State<AppVersionsScreen> createState() => _AppVersionsScreenState();
}

class _AppVersionsScreenState extends State<AppVersionsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _versions = [];
  List<Map<String, dynamic>> _logs = [];

  // Filters & Search
  String _selectedPlatformFilter = 'All'; // 'All', 'android', 'ios'
  String _selectedStatusFilter = 'All'; // 'All', 'published', 'draft'
  final _searchController = TextEditingController();

  // Controllers for creating/editing versions
  final _versionController = TextEditingController();
  final _buildNumberController = TextEditingController();
  final _minSupportedController = TextEditingController();
  final _downloadUrlController = TextEditingController();
  final _notesController = TextEditingController();
  
  String _selectedPlatform = 'android';
  String _selectedUpdateType = 'optional'; // 'none', 'optional', 'force'
  String _selectedStatus = 'draft'; // 'draft', 'published'

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _versionController.dispose();
    _buildNumberController.dispose();
    _minSupportedController.dispose();
    _downloadUrlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final client = AdminSupabaseService.client;
      
      // Load versions gracefully
      List<Map<String, dynamic>> versions = [];
      try {
        final versionsResponse = await client
            .from('app_versions')
            .select()
            .order('created_at', ascending: false);
        versions = List<Map<String, dynamic>>.from(versionsResponse);
      } catch (e) {
        debugPrint('Error loading app_versions: $e');
      }

      // Load activity logs gracefully
      List<Map<String, dynamic>> logs = [];
      try {
        final logsResponse = await client
            .from('version_activity_logs')
            .select()
            .order('created_at', ascending: false)
            .limit(20);
        logs = List<Map<String, dynamic>>.from(logsResponse);
      } catch (e) {
        debugPrint('Error loading version_activity_logs: $e');
      }

      if (mounted) {
        setState(() {
          _versions = versions;
          _logs = logs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveRelease({String? editId}) async {
    final vName = _versionController.text.trim();
    final buildStr = _buildNumberController.text.trim();
    final minSupported = _minSupportedController.text.trim();
    final downloadUrl = _downloadUrlController.text.trim();
    final notes = _notesController.text.trim();

    if (vName.isEmpty || buildStr.isEmpty || minSupported.isEmpty || downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: AdminTheme.danger,
        ),
      );
      return;
    }

    final buildNum = int.tryParse(buildStr);
    if (buildNum == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Build number must be a valid integer'),
          backgroundColor: AdminTheme.danger,
        ),
      );
      return;
    }

    try {
      final client = AdminSupabaseService.client;
      final payload = {
        'platform': _selectedPlatform,
        'version_name': vName,
        'build_number': buildNum,
        'min_supported_version': minSupported,
        'latest_version': vName,
        'download_url': downloadUrl,
        'release_notes': notes,
        'is_force_update': _selectedUpdateType == 'force',
        'is_optional_update': _selectedUpdateType == 'optional',
        'status': _selectedStatus,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (editId != null) {
        await client.from('app_versions').update(payload).eq('id', editId);
      } else {
        payload['created_at'] = DateTime.now().toIso8601String();
        payload['created_by'] = client.auth.currentUser?.id ?? dbPlaceholder;
        await client.from('app_versions').insert(payload);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(editId != null ? 'Version updated successfully' : 'New version created successfully'),
            backgroundColor: AdminTheme.success,
          ),
        );
      }

      // Reset form
      _versionController.clear();
      _buildNumberController.clear();
      _minSupportedController.clear();
      _downloadUrlController.clear();
      _notesController.clear();
      setState(() {
        _selectedUpdateType = 'optional';
        _selectedStatus = 'draft';
      });

      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save release: ${e.toString()}'),
            backgroundColor: AdminTheme.danger,
          ),
        );
      }
    }
  }

  // Helper constant since triggers use auth.uid()
  static const String dbPlaceholder = '00000000-0000-0000-0000-000000000000';

  Future<void> _publishDraft(String id, String platform, String versionName, int buildNum) async {
    try {
      final client = AdminSupabaseService.client;
      await client.from('app_versions').update({
        'status': 'published',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully published version $versionName ($buildNum) for ${platform.toUpperCase()}'),
            backgroundColor: AdminTheme.success,
          ),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to publish version: ${e.toString()}'),
            backgroundColor: AdminTheme.danger,
          ),
        );
      }
    }
  }

  void _openEditDialog(Map<String, dynamic> v) {
    _versionController.text = v['version_name'] ?? '';
    _buildNumberController.text = (v['build_number'] ?? '').toString();
    _minSupportedController.text = v['min_supported_version'] ?? '';
    _downloadUrlController.text = v['download_url'] ?? '';
    _notesController.text = v['release_notes'] ?? '';
    
    setState(() {
      _selectedPlatform = v['platform'] ?? 'android';
      _selectedUpdateType = (v['is_force_update'] == true) 
          ? 'force' 
          : ((v['is_optional_update'] == true) ? 'optional' : 'none');
      _selectedStatus = v['status'] ?? 'draft';
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminTheme.cardColor(context),
        title: Text('Edit Version Settings', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AdminTheme.textColor(context))),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFormFields(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: AdminTheme.secondaryTextColor(context))),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _saveRelease(editId: v['id']);
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = AdminResponsive.contentPadding(context);
    if (_isLoading) {
      return Padding(
        padding: EdgeInsets.all(padding),
        child: const SkeletonTable(rows: 6),
      );
    }

    final isDesktop = AdminResponsive.isDesktop(context);

    // Filtered versions
    final filteredVersions = _versions.where((v) {
      // Platform filter
      if (_selectedPlatformFilter != 'All' && v['platform'] != _selectedPlatformFilter) {
        return false;
      }
      // Status filter
      if (_selectedStatusFilter != 'All' && v['status'] != _selectedStatusFilter) {
        return false;
      }
      // Search
      final search = _searchController.text.toLowerCase();
      if (search.isNotEmpty) {
        final vName = (v['version_name'] ?? '').toString().toLowerCase();
        final buildNum = (v['build_number'] ?? '').toString().toLowerCase();
        final notes = (v['release_notes'] ?? '').toString().toLowerCase();
        if (!vName.contains(search) && !buildNum.contains(search) && !notes.contains(search)) {
          return false;
        }
      }
      return true;
    }).toList();

    // Get current live versions
    final liveAndroid = _versions.firstWhere((v) => v['platform'] == 'android' && v['status'] == 'published', orElse: () => {});
    final liveIos = _versions.firstWhere((v) => v['platform'] == 'ios' && v['status'] == 'published', orElse: () => {});

    return RefreshIndicator(
      onRefresh: _loadData,
      color: AdminTheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(padding),
        child: AnimationLimiter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: AnimationConfiguration.toStaggeredList(
              duration: const Duration(milliseconds: 300),
              childAnimationBuilder: (w) => SlideAnimation(verticalOffset: 20, child: FadeInAnimation(child: w)),
              children: [
                _buildHeader(context),
                const SizedBox(height: 24),
                _buildStatsGrid(context, liveAndroid, liveIos),
                const SizedBox(height: 28),
                if (isDesktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: _buildVersionsTableCard(context, filteredVersions)),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            _buildCreateReleaseCard(context),
                            const SizedBox(height: 24),
                            _buildActivityLogsCard(context),
                          ],
                        ),
                      ),
                    ],
                  )
                else ...[
                  _buildCreateReleaseCard(context),
                  const SizedBox(height: 24),
                  _buildVersionsTableCard(context, filteredVersions),
                  const SizedBox(height: 24),
                  _buildActivityLogsCard(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'App Version Control',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AdminTheme.textColor(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Configure live APK/IPA release versions, set update constraints, and manage build numbers.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AdminTheme.secondaryTextColor(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsGrid(BuildContext context, Map<String, dynamic> android, Map<String, dynamic> ios) {
    return GridView.count(
      crossAxisCount: AdminResponsive.isMobile(context) ? 2 : 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          context,
          'Live Android Version',
          android['version_name'] != null ? 'v${android['version_name']} (${android['build_number']})' : 'None',
          Icons.android_rounded,
          Colors.green,
        ),
        _buildStatCard(
          context,
          'Live iOS Version',
          ios['version_name'] != null ? 'v${ios['version_name']} (${ios['build_number']})' : 'None',
          Icons.apple_rounded,
          Colors.grey,
        ),
        _buildStatCard(
          context,
          'Forced Upgrades',
          _versions.where((v) => v['is_force_update'] == true && v['status'] == 'published').length.toString(),
          Icons.warning_amber_rounded,
          Colors.amber,
        ),
        _buildStatCard(
          context,
          'Total Published Releases',
          _versions.where((v) => v['status'] == 'published').length.toString(),
          Icons.history_toggle_off_rounded,
          AdminTheme.primary,
        ),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AdminTheme.secondaryTextColor(context),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AdminTheme.textColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateReleaseCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Publish New Release',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AdminTheme.textColor(context),
            ),
          ),
          const SizedBox(height: 20),
          _buildFormFields(),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() => _selectedStatus = 'draft');
                    _saveRelease();
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    side: BorderSide(color: AdminTheme.borderColor(context)),
                  ),
                  child: Text(
                    'Save Draft',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _selectedStatus = 'published');
                    _saveRelease();
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
                  child: Text(
                    'Publish Live',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Platform Selection
        Text(
          'Target Platform',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context)),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: const Center(child: Text('Android')),
                selected: _selectedPlatform == 'android',
                onSelected: (selected) {
                  if (selected) setState(() => _selectedPlatform = 'android');
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ChoiceChip(
                label: const Center(child: Text('iOS')),
                selected: _selectedPlatform == 'ios',
                onSelected: (selected) {
                  if (selected) setState(() => _selectedPlatform = 'ios');
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _field('Version Name (e.g. 1.0.1)', _versionController, hint: '1.0.1'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field('Build Number', _buildNumberController, hint: '2'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _field('Minimum Supported Version', _minSupportedController, hint: '1.0.0'),
        const SizedBox(height: 16),
        _field('Download URL', _downloadUrlController, hint: 'https://play.google.com/store/...'),
        const SizedBox(height: 16),
        // Update type selection
        Text(
          'Update Constraint Type',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context)),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _selectedUpdateType,
          decoration: InputDecoration(
            filled: true,
            fillColor: AdminTheme.surfaceColor(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          dropdownColor: AdminTheme.cardColor(context),
          items: const [
            DropdownMenuItem(value: 'none', child: Text('No Notification (Silent)')),
            DropdownMenuItem(value: 'optional', child: Text('Optional Update (User Dismissible)')),
            DropdownMenuItem(value: 'force', child: Text('Force Update (Blocks App Usage)')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedUpdateType = val);
            }
          },
        ),
        const SizedBox(height: 16),
        _field('Release Notes (Markdown Bullet Points)', _notesController, maxLines: 4, hint: '• Added Subscriptions\n• General fixes'),
      ],
    );
  }

  Widget _buildVersionsTableCard(BuildContext context, List<Map<String, dynamic>> list) {
    return Container(
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
              Text(
                'Release History',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AdminTheme.textColor(context),
                ),
              ),
              const Spacer(),
              _buildFilterDropdowns(),
            ],
          ),
          const SizedBox(height: 16),
          _buildSearchField(),
          const SizedBox(height: 20),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  'No versions found matching your filters',
                  style: GoogleFonts.inter(color: AdminTheme.mutedTextColor(context)),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: list.length,
              separatorBuilder: (_, _) => Divider(color: AdminTheme.borderColor(context)),
              itemBuilder: (context, index) {
                final v = list[index];
                return _buildVersionHistoryRow(context, v);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdowns() {
    return Row(
      children: [
        DropdownButton<String>(
          value: _selectedPlatformFilter,
          underline: const SizedBox(),
          dropdownColor: AdminTheme.cardColor(context),
          style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context), fontWeight: FontWeight.w500),
          items: const [
            DropdownMenuItem(value: 'All', child: Text('All Platforms')),
            DropdownMenuItem(value: 'android', child: Text('Android Only')),
            DropdownMenuItem(value: 'ios', child: Text('iOS Only')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedPlatformFilter = val);
            }
          },
        ),
        const SizedBox(width: 16),
        DropdownButton<String>(
          value: _selectedStatusFilter,
          underline: const SizedBox(),
          dropdownColor: AdminTheme.cardColor(context),
          style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context), fontWeight: FontWeight.w500),
          items: const [
            DropdownMenuItem(value: 'All', child: Text('All Statuses')),
            DropdownMenuItem(value: 'published', child: Text('Published')),
            DropdownMenuItem(value: 'draft', child: Text('Drafts')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() => _selectedStatusFilter = val);
            }
          },
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      style: GoogleFonts.inter(fontSize: 13, color: AdminTheme.textColor(context)),
      decoration: InputDecoration(
        hintText: 'Search version name, build number, or notes...',
        hintStyle: GoogleFonts.inter(color: AdminTheme.mutedTextColor(context)),
        prefixIcon: const Icon(Icons.search, size: 18),
        filled: true,
        fillColor: AdminTheme.surfaceColor(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }

  Widget _buildVersionHistoryRow(BuildContext context, Map<String, dynamic> v) {
    final bool isForce = v['is_force_update'] == true;
    final bool isOptional = v['is_optional_update'] == true;
    final bool isPublished = v['status'] == 'published';
    final DateTime? date = v['created_at'] != null ? DateTime.tryParse(v['created_at']) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                v['platform'] == 'android' ? Icons.android_rounded : Icons.apple_rounded,
                size: 20,
                color: v['platform'] == 'android' ? Colors.green : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                'v${v['version_name'] ?? '0.0.0'} (${v['build_number'] ?? '0'})',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: AdminTheme.textColor(context)),
              ),
              const SizedBox(width: 8),
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isPublished 
                      ? AdminTheme.success.withValues(alpha: 0.1) 
                      : AdminTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isPublished ? 'Live' : 'Draft',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isPublished ? AdminTheme.success : AdminTheme.primary,
                  ),
                ),
              ),
              const Spacer(),
              // Actions
              if (!isPublished)
                IconButton(
                  tooltip: 'Publish Release',
                  icon: const Icon(Icons.send_rounded, size: 18, color: AdminTheme.success),
                  onPressed: () => _publishDraft(v['id'], v['platform'], v['version_name'], v['build_number']),
                ),
              IconButton(
                tooltip: 'Edit Settings',
                icon: const Icon(Icons.edit_outlined, size: 18),
                onPressed: () => _openEditDialog(v),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'Min Supported: v${v['min_supported_version']}',
                style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.secondaryTextColor(context)),
              ),
              const SizedBox(width: 16),
              Text(
                'Constraint: ${isForce ? 'Force Update' : (isOptional ? 'Optional Update' : 'Silent')}',
                style: GoogleFonts.inter(
                  fontSize: 12, 
                  color: isForce ? Colors.red : (isOptional ? Colors.orange : AdminTheme.secondaryTextColor(context)),
                  fontWeight: (isForce || isOptional) ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
          if (v['release_notes'] != null && v['release_notes'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              v['release_notes'],
              style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.mutedTextColor(context)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (date != null) ...[
            const SizedBox(height: 6),
            Text(
              'Released on: ${DateFormat('MMM dd, yyyy HH:mm').format(date.toLocal())}',
              style: GoogleFonts.inter(fontSize: 10, color: AdminTheme.mutedTextColor(context)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivityLogsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AdminTheme.cardColor(context),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(color: AdminTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version Activity Logs',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AdminTheme.textColor(context),
            ),
          ),
          const SizedBox(height: 20),
          if (_logs.isEmpty)
            Center(
              child: Text(
                'No activity logs recorded yet.',
                style: GoogleFonts.inter(color: AdminTheme.mutedTextColor(context)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _logs.length,
              separatorBuilder: (_, _) => Divider(color: AdminTheme.borderColor(context)),
              itemBuilder: (context, index) {
                final log = _logs[index];
                final date = log['created_at'] != null ? DateTime.tryParse(log['created_at']) : null;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AdminTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              (log['action'] ?? 'LOG').toString().toUpperCase(),
                              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: AdminTheme.primary),
                            ),
                          ),
                          const Spacer(),
                          if (date != null)
                            Text(
                              DateFormat('MMM dd, HH:mm').format(date.toLocal()),
                              style: GoogleFonts.inter(fontSize: 10, color: AdminTheme.mutedTextColor(context)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        log['notes'] ?? '',
                        style: GoogleFonts.inter(fontSize: 12, color: AdminTheme.textColor(context)),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {int maxLines = 1, required String hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AdminTheme.secondaryTextColor(context)),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: GoogleFonts.inter(fontSize: 14, color: AdminTheme.textColor(context)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: AdminTheme.mutedTextColor(context)),
            filled: true,
            fillColor: AdminTheme.surfaceColor(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AdminTheme.radiusSm), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }
}
