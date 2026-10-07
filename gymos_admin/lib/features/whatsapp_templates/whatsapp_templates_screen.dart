import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/admin_theme.dart';
import '../../core/theme/responsive.dart';
import 'services/template_service.dart';

class WhatsAppTemplatesScreen extends StatefulWidget {
  const WhatsAppTemplatesScreen({super.key});

  @override
  State<WhatsAppTemplatesScreen> createState() =>
      _WhatsAppTemplatesScreenState();
}

class _WhatsAppTemplatesScreenState extends State<WhatsAppTemplatesScreen>
    with SingleTickerProviderStateMixin {
  final WhatsAppTemplateService _service = WhatsAppTemplateService.instance;

  bool _isLoading = true;
  String? _error;
  List<WhatsAppTemplate> _templates = [];
  String _searchQuery = '';
  String _statusFilter = 'ALL';
  String _categoryFilter = 'ALL';

  late TabController _tabController;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _statusFilter = ['ALL', 'APPROVED', 'PENDING', 'REJECTED', 'PAUSED'][
              _tabController.index];
        });
      }
    });
    _loadTemplates();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final templates = await _service.fetchTemplates();
      if (mounted) {
        setState(() {
          _templates = templates;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<WhatsAppTemplate> get _filteredTemplates {
    return _templates.where((t) {
      final matchesSearch = _searchQuery.isEmpty ||
          t.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          t.bodyText.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesStatus =
          _statusFilter == 'ALL' || t.status == _statusFilter;
      final matchesCategory =
          _categoryFilter == 'ALL' || t.category == _categoryFilter;
      return matchesSearch && matchesStatus && matchesCategory;
    }).toList();
  }

  Map<String, int> get _statusCounts {
    final counts = <String, int>{
      'ALL': _templates.length,
      'APPROVED': 0,
      'PENDING': 0,
      'REJECTED': 0,
      'PAUSED': 0,
    };
    for (final t in _templates) {
      counts[t.status] = (counts[t.status] ?? 0) + 1;
    }
    return counts;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED':
        return AdminTheme.success;
      case 'PENDING':
        return AdminTheme.warning;
      case 'REJECTED':
        return AdminTheme.danger;
      case 'PAUSED':
        return AdminTheme.orange;
      case 'DISABLED':
        return AdminTheme.textMuted;
      default:
        return AdminTheme.info;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'APPROVED':
        return Icons.check_circle_rounded;
      case 'PENDING':
        return Icons.schedule_rounded;
      case 'REJECTED':
        return Icons.cancel_rounded;
      case 'PAUSED':
        return Icons.pause_circle_rounded;
      case 'DISABLED':
        return Icons.block_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'MARKETING':
        return AdminTheme.pink;
      case 'UTILITY':
        return AdminTheme.info;
      case 'AUTHENTICATION':
        return AdminTheme.teal;
      default:
        return AdminTheme.textSecondary;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'MARKETING':
        return Icons.campaign_rounded;
      case 'UTILITY':
        return Icons.build_circle_rounded;
      case 'AUTHENTICATION':
        return Icons.verified_user_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  Future<void> _deleteTemplate(WhatsAppTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Template',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
        content: RichText(
          text: TextSpan(
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AdminTheme.textColor(context),
            ),
            children: [
              const TextSpan(text: 'Are you sure you want to delete '),
              TextSpan(
                text: template.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const TextSpan(text: '?\n\nThis action cannot be undone.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AdminTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.inter(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _service.deleteTemplate(name: template.name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Template "${template.name}" deleted successfully'),
              backgroundColor: AdminTheme.success,
            ),
          );
          _loadTemplates();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete: $e'),
              backgroundColor: AdminTheme.danger,
            ),
          );
        }
      }
    }
  }

  void _showCreateDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CreateTemplateDialog(
        onCreated: () {
          _loadTemplates();
        },
      ),
    );
  }

  void _showTemplateDetail(WhatsAppTemplate template) {
    showDialog(
      context: context,
      builder: (ctx) => _TemplateDetailDialog(template: template),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AdminTheme.isDark(context);
    final padding = AdminResponsive.contentPadding(context);
    final isMobile = AdminResponsive.isMobile(context);

    return Container(
      color: isDark ? AdminTheme.darkBackground : AdminTheme.lightBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildHeader(isDark, padding, isMobile),
          // Status Tabs
          _buildStatusTabs(isDark, padding),
          // Content
          Expanded(
            child: _isLoading
                ? _buildLoadingState()
                : _error != null
                    ? _buildErrorState()
                    : _filteredTemplates.isEmpty
                        ? _buildEmptyState()
                        : _buildTemplateGrid(padding, isMobile),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark, double padding, bool isMobile) {
    final counts = _statusCounts;
    return Container(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                  ),
                  borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
                ),
                child: const Icon(Icons.article_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WhatsApp Templates',
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.w800,
                        color: AdminTheme.textColor(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${counts['ALL'] ?? 0} templates • ${counts['APPROVED'] ?? 0} approved • ${counts['PENDING'] ?? 0} pending',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AdminTheme.secondaryTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (!isMobile) ...[
                OutlinedButton.icon(
                  onPressed: _loadTemplates,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('Refresh', style: GoogleFonts.inter(fontSize: 13)),
                ),
                const SizedBox(width: 10),
              ],
              ElevatedButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  isMobile ? 'New' : 'Create Template',
                  style: GoogleFonts.inter(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Search & Filters row
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: isMobile ? double.infinity : 280,
                height: 40,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: 'Search templates...',
                    hintStyle: GoogleFonts.inter(
                      fontSize: 13,
                      color: AdminTheme.mutedTextColor(context),
                    ),
                    prefixIcon: Icon(Icons.search_rounded,
                        size: 18, color: AdminTheme.mutedTextColor(context)),
                    filled: true,
                    fillColor: isDark
                        ? AdminTheme.darkSurface
                        : AdminTheme.lightSurface,
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AdminTheme.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  style: GoogleFonts.inter(fontSize: 13),
                ),
              ),
              // Category filter
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AdminTheme.darkSurface
                      : AdminTheme.lightSurface,
                  borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _categoryFilter,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AdminTheme.textColor(context),
                    ),
                    dropdownColor: isDark ? AdminTheme.darkCard : Colors.white,
                    items: ['ALL', 'MARKETING', 'UTILITY', 'AUTHENTICATION']
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (c != 'ALL')
                                    Icon(_categoryIcon(c),
                                        size: 16,
                                        color: _categoryColor(c)),
                                  if (c != 'ALL') const SizedBox(width: 6),
                                  Text(c == 'ALL'
                                      ? 'All Categories'
                                      : c[0] + c.substring(1).toLowerCase()),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _categoryFilter = val);
                    },
                  ),
                ),
              ),
              if (isMobile)
                SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: _loadTemplates,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text('Refresh',
                        style: GoogleFonts.inter(fontSize: 13)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTabs(bool isDark, double padding) {
    final counts = _statusCounts;
    final labels = ['ALL', 'APPROVED', 'PENDING', 'REJECTED', 'PAUSED'];

    return Container(
      margin: EdgeInsets.symmetric(horizontal: padding),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AdminTheme.borderColor(context),
            width: 1,
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelPadding: const EdgeInsets.symmetric(horizontal: 16),
        tabs: labels.map((label) {
          final count = counts[label] ?? 0;
          final color = label == 'ALL' ? AdminTheme.primary : _statusColor(label);
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (label != 'ALL') ...[
                  Icon(_statusIcon(label), size: 14, color: color),
                  const SizedBox(width: 6),
                ],
                Text(label == 'ALL'
                    ? 'All'
                    : label[0] + label.substring(1).toLowerCase()),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFF25D366),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading templates from Meta...',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AdminTheme.secondaryTextColor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AdminTheme.dangerLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded,
                  size: 40, color: AdminTheme.danger),
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load templates',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AdminTheme.textColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxWidth: 500),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminTheme.dangerLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
              ),
              child: SelectableText(
                _error ?? 'Unknown error',
                style: GoogleFonts.robotoMono(
                  fontSize: 12,
                  color: AdminTheme.danger,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadTemplates,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('Try Again', style: GoogleFonts.inter()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF25D366).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.article_outlined,
                size: 48, color: Color(0xFF25D366)),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty || _statusFilter != 'ALL' || _categoryFilter != 'ALL'
                ? 'No templates match your filters'
                : 'No templates yet',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AdminTheme.textColor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty || _statusFilter != 'ALL' || _categoryFilter != 'ALL'
                ? 'Try adjusting your search or filters'
                : 'Create your first WhatsApp message template',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AdminTheme.secondaryTextColor(context),
            ),
          ),
          const SizedBox(height: 20),
          if (_searchQuery.isEmpty && _statusFilter == 'ALL' && _categoryFilter == 'ALL')
            ElevatedButton.icon(
              onPressed: _showCreateDialog,
              icon: const Icon(Icons.add_rounded),
              label: Text('Create Template', style: GoogleFonts.inter()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTemplateGrid(double padding, bool isMobile) {
    final templates = _filteredTemplates;
    final crossAxisCount = isMobile ? 1 : AdminResponsive.gridColumns(context);

    return Padding(
      padding: EdgeInsets.all(padding),
      child: GridView.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: isMobile ? 2.0 : 1.3,
        ),
        itemCount: templates.length,
        itemBuilder: (ctx, i) => _buildTemplateCard(templates[i]),
      ),
    );
  }

  Widget _buildTemplateCard(WhatsAppTemplate template) {
    final isDark = AdminTheme.isDark(context);
    final statusClr = _statusColor(template.status);
    final catClr = _categoryColor(template.category);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        onTap: () => _showTemplateDetail(template),
        child: AnimatedContainer(
          duration: AdminTheme.animFast,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AdminTheme.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
            border: Border.all(
              color: isDark ? AdminTheme.darkBorder : AdminTheme.lightBorder,
            ),
            boxShadow: AdminTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: Status badge + Actions
              Row(
                children: [
                  // Status chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusClr.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_statusIcon(template.status),
                            size: 12, color: statusClr),
                        const SizedBox(width: 4),
                        Text(
                          template.status[0] +
                              template.status.substring(1).toLowerCase(),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusClr,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Category chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: catClr.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_categoryIcon(template.category),
                            size: 12, color: catClr),
                        const SizedBox(width: 4),
                        Text(
                          template.category[0] +
                              template.category.substring(1).toLowerCase(),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: catClr,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Delete button
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _deleteTemplate(template),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline_rounded,
                          size: 18,
                          color: AdminTheme.mutedTextColor(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Template name
              Text(
                template.name,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AdminTheme.textColor(context),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Language: ${template.language}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AdminTheme.mutedTextColor(context),
                ),
              ),
              const SizedBox(height: 8),
              // Body preview
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AdminTheme.darkSurface.withValues(alpha: 0.5)
                        : const Color(0xFFF0FFF4),
                    borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
                    border: Border.all(
                      color: const Color(0xFF25D366).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Text(
                    template.bodyText.isNotEmpty
                        ? template.bodyText
                        : '(No body text)',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AdminTheme.secondaryTextColor(context),
                      height: 1.4,
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Footer: last updated
              if (template.lastUpdated != null)
                Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: 12,
                        color: AdminTheme.mutedTextColor(context)),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd MMM yyyy, hh:mm a')
                          .format(template.lastUpdated!.toLocal()),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AdminTheme.mutedTextColor(context),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// CREATE TEMPLATE DIALOG
// ═══════════════════════════════════════════════════════════════════

class _CreateTemplateDialog extends StatefulWidget {
  final VoidCallback onCreated;

  const _CreateTemplateDialog({required this.onCreated});

  @override
  State<_CreateTemplateDialog> createState() => _CreateTemplateDialogState();
}

class _CreateTemplateDialogState extends State<_CreateTemplateDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _headerController = TextEditingController();
  final _bodyController = TextEditingController();
  final _footerController = TextEditingController();

  String _category = 'UTILITY';
  String _language = 'en_US';
  bool _isCreating = false;
  String? _error;

  // Buttons list
  final List<Map<String, TextEditingController>> _buttons = [];

  static const _languages = {
    'en_US': 'English (US)',
    'en_GB': 'English (UK)',
    'hi': 'Hindi',
    'mr': 'Marathi',
    'gu': 'Gujarati',
    'ta': 'Tamil',
    'te': 'Telugu',
    'kn': 'Kannada',
    'bn': 'Bengali',
    'pa': 'Punjabi',
    'ml': 'Malayalam',
    'ur': 'Urdu',
    'ar': 'Arabic',
    'es': 'Spanish',
    'pt_BR': 'Portuguese (BR)',
    'fr': 'French',
    'de': 'German',
    'id': 'Indonesian',
    'it': 'Italian',
    'ja': 'Japanese',
    'ko': 'Korean',
    'ru': 'Russian',
    'zh_CN': 'Chinese (Simplified)',
    'zh_TW': 'Chinese (Traditional)',
  };

  void _addButton() {
    if (_buttons.length >= 3) return;
    setState(() {
      _buttons.add({
        'text': TextEditingController(),
      });
    });
  }

  void _removeButton(int index) {
    setState(() {
      for (final ctrl in _buttons[index].values) {
        ctrl.dispose();
      }
      _buttons.removeAt(index);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _headerController.dispose();
    _bodyController.dispose();
    _footerController.dispose();
    for (final btn in _buttons) {
      for (final ctrl in btn.values) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isCreating = true;
      _error = null;
    });

    try {
      final btns = _buttons.isNotEmpty
          ? _buttons
              .map((b) => {
                    'type': 'QUICK_REPLY',
                    'text': b['text']!.text.trim(),
                  })
              .where((b) => b['text']!.isNotEmpty)
              .toList()
          : null;

      await WhatsAppTemplateService.instance.createTemplate(
        name: _nameController.text,
        language: _language,
        category: _category,
        headerText: _headerController.text.trim().isNotEmpty
            ? _headerController.text
            : null,
        bodyText: _bodyController.text,
        footerText: _footerController.text.trim().isNotEmpty
            ? _footerController.text
            : null,
        buttons: btns,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onCreated();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Template "${_nameController.text}" submitted for approval!',
              style: GoogleFonts.inter(),
            ),
            backgroundColor: AdminTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AdminTheme.isDark(context);
    final isMobile = AdminResponsive.isMobile(context);

    return Dialog(
      insetPadding: EdgeInsets.all(isMobile ? 16 : 40),
      child: Container(
        width: isMobile ? double.infinity : 640,
        constraints: const BoxConstraints(maxHeight: 720),
        decoration: BoxDecoration(
          color: isDark ? AdminTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(AdminTheme.radiusLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dialog header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AdminTheme.borderColor(context),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF25D366), Color(0xFF128C7E)],
                      ),
                      borderRadius:
                          BorderRadius.circular(AdminTheme.radiusSm),
                    ),
                    child: const Icon(Icons.add_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create Message Template',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AdminTheme.textColor(context),
                          ),
                        ),
                        Text(
                          'Template will be sent to Meta for approval',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AdminTheme.secondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            // Form body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Error banner
                      if (_error != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AdminTheme.dangerLight,
                            borderRadius:
                                BorderRadius.circular(AdminTheme.radiusSm),
                            border: Border.all(
                                color: AdminTheme.danger.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  size: 18, color: AdminTheme.danger),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AdminTheme.danger,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Name & Category row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: _buildField(
                              label: 'Template Name',
                              hint: 'e.g. welcome_message',
                              controller: _nameController,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                if (!RegExp(r'^[a-z0-9_]+$').hasMatch(
                                    v.trim().toLowerCase().replaceAll(' ', '_'))) {
                                  return 'Only lowercase letters, numbers, underscores';
                                }
                                return null;
                              },
                              helpText:
                                  'Only lowercase, numbers, underscores allowed',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Category',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AdminTheme.textColor(context),
                                    )),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<String>(
                                  initialValue: _category,
                                  decoration: _inputDecoration(isDark),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AdminTheme.textColor(context),
                                  ),
                                  dropdownColor: isDark
                                      ? AdminTheme.darkCard
                                      : Colors.white,
                                  items: ['UTILITY', 'MARKETING', 'AUTHENTICATION']
                                      .map((c) => DropdownMenuItem(
                                            value: c,
                                            child: Text(c[0] +
                                                c.substring(1).toLowerCase()),
                                          ))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() => _category = v);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Language
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Language',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AdminTheme.textColor(context),
                              )),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _language,
                            decoration: _inputDecoration(isDark),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: AdminTheme.textColor(context),
                            ),
                            dropdownColor:
                                isDark ? AdminTheme.darkCard : Colors.white,
                            isExpanded: true,
                            items: _languages.entries
                                .map((e) => DropdownMenuItem(
                                      value: e.key,
                                      child: Text(
                                          '${e.value} (${e.key})'),
                                    ))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _language = v);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Header (optional)
                      _buildField(
                        label: 'Header Text (Optional)',
                        hint: 'e.g. Welcome to GymOS!',
                        controller: _headerController,
                        helpText: 'Max 60 characters',
                        maxLength: 60,
                      ),
                      const SizedBox(height: 14),

                      // Body (required)
                      _buildField(
                        label: 'Body Text',
                        hint:
                            'Hello {{1}}, your membership at {{2}} is confirmed!\n\nUse {{1}}, {{2}}, etc. for variables.',
                        controller: _bodyController,
                        maxLines: 5,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Body text is required';
                          }
                          if (v.trim().length > 1024) {
                            return 'Max 1024 characters';
                          }
                          return null;
                        },
                        helpText: 'Use {{1}}, {{2}} etc. for dynamic variables. Max 1024 chars.',
                      ),
                      const SizedBox(height: 14),

                      // Footer (optional)
                      _buildField(
                        label: 'Footer Text (Optional)',
                        hint: 'e.g. Reply STOP to unsubscribe',
                        controller: _footerController,
                        helpText: 'Max 60 characters',
                        maxLength: 60,
                      ),
                      const SizedBox(height: 14),

                      // Buttons section
                      Row(
                        children: [
                          Text('Quick Reply Buttons (Optional)',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AdminTheme.textColor(context),
                              )),
                          const Spacer(),
                          if (_buttons.length < 3)
                            TextButton.icon(
                              onPressed: _addButton,
                              icon:
                                  const Icon(Icons.add_rounded, size: 16),
                              label: Text('Add Button',
                                  style: GoogleFonts.inter(fontSize: 12)),
                            ),
                        ],
                      ),
                      if (_buttons.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ..._buttons.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final btn = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: btn['text'],
                                    decoration: _inputDecoration(isDark).copyWith(
                                      hintText: 'Button ${idx + 1} text',
                                      hintStyle: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: AdminTheme.mutedTextColor(context),
                                      ),
                                    ),
                                    style: GoogleFonts.inter(fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () => _removeButton(idx),
                                  icon: const Icon(Icons.remove_circle_outline_rounded,
                                      size: 20, color: AdminTheme.danger),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],

                      const SizedBox(height: 10),
                      // Preview section
                      _buildPreview(isDark),
                    ],
                  ),
                ),
              ),
            ),
            // Action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: AdminTheme.borderColor(context),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed:
                        _isCreating ? null : () => Navigator.pop(context),
                    child: Text('Cancel', style: GoogleFonts.inter()),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isCreating ? null : _submit,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      _isCreating ? 'Submitting...' : 'Submit for Approval',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String hint,
    required TextEditingController controller,
    String? helpText,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    final isDark = AdminTheme.isDark(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AdminTheme.textColor(context),
            )),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          validator: validator,
          decoration: _inputDecoration(isDark).copyWith(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              fontSize: 13,
              color: AdminTheme.mutedTextColor(context),
            ),
          ),
          style: GoogleFonts.inter(fontSize: 13),
        ),
        if (helpText != null) ...[
          const SizedBox(height: 4),
          Text(helpText,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AdminTheme.mutedTextColor(context),
              )),
        ],
      ],
    );
  }

  InputDecoration _inputDecoration(bool isDark) {
    return InputDecoration(
      filled: true,
      fillColor: isDark ? AdminTheme.darkSurface : AdminTheme.lightSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
        borderSide: BorderSide(
          color: isDark ? AdminTheme.darkBorder : AdminTheme.lightBorder,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
        borderSide: const BorderSide(color: Color(0xFF25D366), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
        borderSide: const BorderSide(color: AdminTheme.danger),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Widget _buildPreview(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? AdminTheme.darkSurface.withValues(alpha: 0.4)
            : const Color(0xFFF0FFF4),
        borderRadius: BorderRadius.circular(AdminTheme.radiusCard),
        border: Border.all(
          color: const Color(0xFF25D366).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_rounded,
                  size: 14, color: Color(0xFF25D366)),
              const SizedBox(width: 6),
              Text(
                'Live Preview',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF25D366),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // WhatsApp-style message bubble
          Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1F3C28) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomRight: Radius.circular(12),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: ListenableBuilder(
              listenable: Listenable.merge([
                _headerController,
                _bodyController,
                _footerController,
              ]),
              builder: (ctx, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_headerController.text.trim().isNotEmpty) ...[
                      Text(
                        _headerController.text,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AdminTheme.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      _bodyController.text.trim().isNotEmpty
                          ? _bodyController.text
                          : 'Your message body will appear here...',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: _bodyController.text.trim().isNotEmpty
                            ? AdminTheme.textColor(context)
                            : AdminTheme.mutedTextColor(context),
                        height: 1.4,
                      ),
                    ),
                    if (_footerController.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        _footerController.text,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AdminTheme.mutedTextColor(context),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          // Preview buttons
          if (_buttons.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...List.generate(_buttons.length, (i) {
              return ListenableBuilder(
                listenable: _buttons[i]['text']!,
                builder: (ctx, _) {
                  final txt = _buttons[i]['text']!.text;
                  if (txt.trim().isEmpty) return const SizedBox.shrink();
                  return Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 320),
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1F3C28)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF25D366).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        txt,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF25D366),
                        ),
                      ),
                    ),
                  );
                },
              );
            }),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// TEMPLATE DETAIL DIALOG
// ═══════════════════════════════════════════════════════════════════

class _TemplateDetailDialog extends StatelessWidget {
  final WhatsAppTemplate template;

  const _TemplateDetailDialog({required this.template});

  Color _statusColor(String status) {
    switch (status) {
      case 'APPROVED':
        return AdminTheme.success;
      case 'PENDING':
        return AdminTheme.warning;
      case 'REJECTED':
        return AdminTheme.danger;
      case 'PAUSED':
        return AdminTheme.orange;
      default:
        return AdminTheme.info;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'APPROVED':
        return Icons.check_circle_rounded;
      case 'PENDING':
        return Icons.schedule_rounded;
      case 'REJECTED':
        return Icons.cancel_rounded;
      case 'PAUSED':
        return Icons.pause_circle_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AdminTheme.isDark(context);
    final isMobile = AdminResponsive.isMobile(context);
    final statusClr = _statusColor(template.status);

    return Dialog(
      insetPadding: EdgeInsets.all(isMobile ? 16 : 40),
      child: Container(
        width: isMobile ? double.infinity : 560,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: isDark ? AdminTheme.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(AdminTheme.radiusLg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      color: AdminTheme.borderColor(context)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusClr.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AdminTheme.radiusSm),
                    ),
                    child: Icon(_statusIcon(template.status),
                        color: statusClr, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.name,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AdminTheme.textColor(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${template.category} • ${template.language} • ${template.status}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AdminTheme.secondaryTextColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Copy template ID
                  IconButton(
                    tooltip: 'Copy Template ID',
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: template.id));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Template ID copied!',
                            style: GoogleFonts.inter(),
                          ),
                          backgroundColor: AdminTheme.success,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ID
                    _detailRow(context, 'Template ID', template.id),
                    const SizedBox(height: 12),
                    _detailRow(context, 'Status', template.status),
                    if (template.rejectedReason != null &&
                        template.rejectedReason!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildLabel(context, 'Rejection Reason'),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AdminTheme.dangerLight,
                          borderRadius:
                              BorderRadius.circular(AdminTheme.radiusSm),
                        ),
                        child: Text(
                          template.rejectedReason!,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: AdminTheme.danger,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),

                    // Components
                    if (template.headerText != null &&
                        template.headerText!.isNotEmpty) ...[
                      _buildLabel(context, 'Header'),
                      const SizedBox(height: 6),
                      _buildComponentBox(context, isDark, template.headerText!,
                          isBold: true),
                      const SizedBox(height: 14),
                    ],

                    _buildLabel(context, 'Body'),
                    const SizedBox(height: 6),
                    _buildComponentBox(
                        context, isDark, template.bodyText),
                    const SizedBox(height: 14),

                    if (template.footerText != null &&
                        template.footerText!.isNotEmpty) ...[
                      _buildLabel(context, 'Footer'),
                      const SizedBox(height: 6),
                      _buildComponentBox(
                          context, isDark, template.footerText!,
                          isMuted: true),
                      const SizedBox(height: 14),
                    ],

                    // Buttons
                    if (template.buttons.isNotEmpty)
                      ...template.buttons.expand((comp) {
                        return (comp.buttons ?? []).map((btn) {
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF25D366)
                                  .withValues(alpha: 0.08),
                              borderRadius:
                                  BorderRadius.circular(AdminTheme.radiusSm),
                              border: Border.all(
                                color: const Color(0xFF25D366)
                                    .withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.touch_app_rounded,
                                    size: 16, color: Color(0xFF25D366)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    btn.text,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF25D366),
                                    ),
                                  ),
                                ),
                                Text(
                                  btn.type,
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: AdminTheme.mutedTextColor(context),
                                  ),
                                ),
                              ],
                            ),
                          );
                        });
                      }),

                    if (template.lastUpdated != null) ...[
                      const SizedBox(height: 16),
                      _detailRow(
                        context,
                        'Last Updated',
                        DateFormat('dd MMM yyyy, hh:mm a')
                            .format(template.lastUpdated!.toLocal()),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AdminTheme.secondaryTextColor(context),
              )),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AdminTheme.textColor(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(BuildContext context, String label) {
    return Text(label,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AdminTheme.secondaryTextColor(context),
          letterSpacing: 0.5,
        ));
  }

  Widget _buildComponentBox(
    BuildContext context,
    bool isDark,
    String text, {
    bool isBold = false,
    bool isMuted = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? AdminTheme.darkSurface.withValues(alpha: 0.5)
            : const Color(0xFFF0FFF4),
        borderRadius: BorderRadius.circular(AdminTheme.radiusSm),
        border: Border.all(
          color: const Color(0xFF25D366).withValues(alpha: 0.15),
        ),
      ),
      child: SelectableText(
        text,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          color: isMuted
              ? AdminTheme.mutedTextColor(context)
              : AdminTheme.textColor(context),
          height: 1.5,
        ),
      ),
    );
  }
}
