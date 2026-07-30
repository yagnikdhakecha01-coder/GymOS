import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/services/announcements_service.dart';

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  String _imageUrl = '';
  String _selectedAudience = 'All Members';

  List<Announcement> _history = [];
  bool _isLoading = true;

  final List<String> _audiences = ['All Members', 'All Staff', 'PT Members', 'Selected Members'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final data = await AnnouncementsService.getAnnouncements();
    setState(() {
      _history = data;
      _isLoading = false;
    });
  }

  void _showPreview() {
    if (_titleController.text.trim().isEmpty || _messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill title and message to preview'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Container(
          width: 320,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Notification Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.notifications_active, color: AppTheme.primary, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text('GymOS Announcement', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                  const Spacer(),
                  Text('now', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
              const SizedBox(height: 12),
              // Content
              Text(
                _titleController.text.trim(),
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                _messageController.text.trim(),
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
              ),
              if (_imageUrl.isNotEmpty) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(_imageUrl, height: 120, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: CustomButton(
                  text: 'Close Preview',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendBroadcast(String status) async {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();

    if (title.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill title and message'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    final newAnn = Announcement(
      id: 'ann_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      message: message,
      image: _imageUrl,
      audience: _selectedAudience,
      date: DateFormat('dd MMM yyyy').format(DateTime.now()),
      status: status,
    );

    await AnnouncementsService.addAnnouncement(newAnn);

    _titleController.clear();
    _messageController.clear();
    setState(() {
      _imageUrl = '';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(status == 'Sent' ? 'Announcement broadcasted!' : 'Announcement scheduled!'),
        backgroundColor: AppTheme.success,
      ),
    );

    _loadHistory();
    _tabController.animateTo(1);
  }

  void _scheduleBroadcast() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (date != null) {
      _sendBroadcast('Scheduled');
    }
  }

  void _confirmDelete(Announcement ann) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Broadcast'),
        content: const Text('Are you sure you want to delete this broadcast?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              await AnnouncementsService.deleteAnnouncement(ann.id);
              Navigator.pop(context);
              _loadHistory();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Broadcast'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Compose'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Compose
          SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Compose Announcement', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 16),
                      // Title
                      Text('Announcement Title *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(hintText: 'e.g. Christmas Gym Timings 🎄'),
                      ),
                      const SizedBox(height: 14),

                      // Message
                      Text('Announcement Message *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _messageController,
                        maxLines: 4,
                        decoration: const InputDecoration(hintText: 'Enter complete announcement message...'),
                      ),
                      const SizedBox(height: 14),

                      // Image URL
                      Text('Optional Banner Image URL', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextFormField(
                        initialValue: _imageUrl,
                        onChanged: (val) => setState(() => _imageUrl = val.trim()),
                        decoration: const InputDecoration(hintText: 'e.g. https://example.com/banner.png'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Audience
                CustomCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Select Target Audience', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _audiences.map((aud) {
                          final isSelected = _selectedAudience == aud;
                          return ChoiceChip(
                            label: Text(aud),
                            selected: isSelected,
                            selectedColor: AppTheme.primary,
                            labelStyle: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : AppTheme.textSecondary,
                            ),
                            onSelected: (val) {
                              if (val) setState(() => _selectedAudience = aud);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Action Row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primary),
                          foregroundColor: AppTheme.primary,
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: _showPreview,
                        icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
                        label: const Text('Preview'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: _scheduleBroadcast,
                        icon: const Icon(Icons.schedule, size: 18),
                        label: const Text('Schedule'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CustomButton(
                  text: 'Send Now',
                  icon: Icons.send,
                  onPressed: () => _sendBroadcast('Sent'),
                ),
              ],
            ),
          ),

          // Tab 2: History
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          Text('No past announcements', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppTheme.pagePadding),
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        final ann = _history[index];
                        return CustomCard(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    StatusBadge.fromStatus(ann.status),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Target: ${ann.audience}',
                                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                                    ),
                                    const Spacer(),
                                    Text(ann.date, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                                      onPressed: () => _confirmDelete(ann),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ann.title,
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  ann.message,
                                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ],
      ),
    );
  }
}
