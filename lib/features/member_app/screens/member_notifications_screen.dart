import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import '../../../core/services/announcements_service.dart';

class MemberNotificationsScreen extends StatefulWidget {
  const MemberNotificationsScreen({super.key});

  @override
  State<MemberNotificationsScreen> createState() => _MemberNotificationsScreenState();
}

class _MemberNotificationsScreenState extends State<MemberNotificationsScreen> {
  List<Announcement> _announcements = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnnouncements();
  }

  Future<void> _loadAnnouncements() async {
    setState(() => _isLoading = true);
    final data = await AnnouncementsService.getAnnouncements();
    // Only show "Sent" announcements to members
    final sent = data.where((e) => e.status == 'Sent').toList();
    setState(() {
      _announcements = sent;
      _isLoading = false;
    });
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
        title: const Text('Notifications'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _announcements.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 56, color: AppTheme.textMuted.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text('No Notifications Yet', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 4),
                      Text('We\'ll notify you when there\'s an update.', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(AppTheme.pagePadding),
                  itemCount: _announcements.length,
                  itemBuilder: (context, index) {
                    final ann = _announcements[index];
                    return CustomCard(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryLight,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'ANNOUNCEMENT',
                                  style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: AppTheme.primary),
                                ),
                              ),
                              Text(ann.date, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            ann.title,
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            ann.message,
                            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                          ),
                          if (ann.image.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                ann.image,
                                height: 150,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
