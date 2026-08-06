import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/notification_service_mobile.dart';
import '../authentication/auth_viewmodel.dart';

class HolidaysScreen extends StatefulWidget {
  const HolidaysScreen({super.key});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  List<Map<String, dynamic>> _holidays = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHolidays();
  }

  Future<void> _loadHolidays() async {
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId != null && SupabaseService.isInitialized) {
        final res = await SupabaseService.client
            .from('holidays')
            .select()
            .eq('gym_id', gymId)
            .order('created_at', ascending: false);

        if (mounted) {
          setState(() {
            _holidays = List<Map<String, dynamic>>.from(res);
            _isLoading = false;
          });
        }
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print('Error loading holidays: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showResultDialog({
    required bool success,
    required String title,
    required String message,
    String? errorReason,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: success ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.danger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  success ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  color: success ? AppTheme.success : AppTheme.danger,
                  size: 54,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: GoogleFonts.inter(fontSize: 13.5, color: AppTheme.textSecondary, height: 1.4),
                textAlign: TextAlign.center,
              ),
              if (!success && errorReason != null && errorReason.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Error Details / Reason:', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.danger)),
                      const SizedBox(height: 4),
                      SelectableText(
                        errorReason,
                        style: GoogleFonts.robotoMono(fontSize: 11, color: AppTheme.danger),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: success ? AppTheme.primary : AppTheme.danger,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    success ? 'Done' : 'Close & Retry',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeclareHolidaySheet() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text('🎉 Declare Gym Holiday', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                  const SizedBox(height: 16),

                  // Date Picker
                  Text('Select Holiday Date *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: isSubmitting ? null : () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setSheetState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(DateFormat('EEEE, dd MMMM yyyy').format(selectedDate), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                          const Icon(Icons.calendar_today_rounded, size: 18, color: AppTheme.primary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Title
                  Text('Holiday Name / Reason *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: titleController,
                    enabled: !isSubmitting,
                    decoration: const InputDecoration(hintText: 'e.g. Diwali Celebration / Holi'),
                  ),
                  const SizedBox(height: 14),

                  // Description
                  Text('Additional Notes (Optional)', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: descController,
                    enabled: !isSubmitting,
                    maxLines: 2,
                    decoration: const InputDecoration(hintText: 'e.g. Gym will remain completely closed for all shifts'),
                  ),
                  const SizedBox(height: 20),

                  CustomButton(
                    text: isSubmitting ? 'Declaring Holiday...' : 'Declare Holiday & Notify All',
                    isLoading: isSubmitting,
                    icon: Icons.campaign_rounded,
                    onPressed: isSubmitting ? () {} : () async {
                      final title = titleController.text.trim();
                      if (title.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Please enter holiday title'), backgroundColor: AppTheme.danger),
                        );
                        return;
                      }

                      setSheetState(() => isSubmitting = true);

                      try {
                        final authVm = Provider.of<AuthViewModel>(context, listen: false);
                        final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];

                        if (gymId != null && SupabaseService.isInitialized) {
                          final formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
                          final desc = descController.text.trim();

                          await SupabaseService.client.from('holidays').insert({
                            'gym_id': gymId,
                            'holiday_date': formattedDate,
                            'date': formattedDate,
                            'title': title,
                            'name': title,
                            'description': desc,
                          });

                          // 1. Instantly show local device push notification on phone status bar
                          try {
                            await NotificationService.showNotification(
                              id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                              title: '🎉 Holiday Declared: $title',
                              body: 'Gym will remain closed on ${DateFormat('EEEE, dd MMMM yyyy').format(selectedDate)}. Reason: ${desc.isNotEmpty ? desc : title}',
                            );
                          } catch (e) {
                            print('Error showing push notification: $e');
                          }

                          // 2. Instantly update unread notification badge count on Home Screen
                          try {
                            authVm.setUnreadNotificationsCount(authVm.unreadNotificationsCount + 1);
                          } catch (_) {}
                        }

                        if (Navigator.canPop(ctx)) {
                          Navigator.pop(ctx);
                        }
                        _loadHolidays();

                        _showResultDialog(
                          success: true,
                          title: '🎉 Holiday Declared!',
                          message: 'Gym Holiday "$title" has been declared successfully. All staff members & gym members have been notified.',
                        );
                      } catch (e) {
                        setSheetState(() => isSubmitting = false);
                        if (Navigator.canPop(ctx)) {
                          Navigator.pop(ctx);
                        }
                        _showResultDialog(
                          success: false,
                          title: '❌ Holiday Declaration Failed',
                          message: 'Could not declare gym holiday due to database constraint or schema issue.',
                          errorReason: e.toString(),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
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
        title: const Text('Gym Holidays'),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showDeclareHolidaySheet,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Declare Holiday', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _holidays.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.event_available_outlined, size: 56, color: AppTheme.textMuted),
                        const SizedBox(height: 12),
                        Text('No holidays declared yet.', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
                        const SizedBox(height: 6),
                        Text('Click "+ Declare Holiday" to notify all staff & members.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(AppTheme.pagePadding),
                    itemCount: _holidays.length,
                    itemBuilder: (context, index) {
                      final item = _holidays[index];
                      final title = item['title']?.toString() ?? item['name']?.toString() ?? 'Gym Holiday';
                      final desc = item['description']?.toString() ?? '';
                      final dateStr = item['holiday_date']?.toString() ?? item['date']?.toString() ?? '';
                      DateTime? parsedDate = DateTime.tryParse(dateStr);
                      final formattedDate = parsedDate != null ? DateFormat('EEEE, dd MMMM yyyy').format(parsedDate) : dateStr;

                      return CustomCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.event_busy_rounded, color: AppTheme.primary, size: 24),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                  const SizedBox(height: 4),
                                  Text(formattedDate, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(desc, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
