import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import '../../../core/widgets/custom_button.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../../core/repository/gym_repository.dart';
import '../../../core/services/supabase_service.dart';
import '../staff_viewmodel.dart';
import 'new_request_screen.dart';

class StaffRequestsScreen extends StatefulWidget {
  const StaffRequestsScreen({super.key});

  @override
  State<StaffRequestsScreen> createState() => _StaffRequestsScreenState();
}

class _StaffRequestsScreenState extends State<StaffRequestsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _advances = [];
  List<Map<String, dynamic>> _leaves = [];
  List<Map<String, dynamic>> _corrections = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final repo = Provider.of<GymRepository>(context, listen: false);
      final staffVm = Provider.of<StaffViewModel>(context, listen: false);
      final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;

      if (profileUserId != null) {
        final matchingStaff = repo.getStaff().where((s) => s.userId == profileUserId).toList();
        final staff = matchingStaff.isNotEmpty ? matchingStaff.first : null;

        if (staff != null) {
          final data = await staffVm.getStaffDashboardData(staff.id);
          final corrResponse = await SupabaseService.client
              .from('attendance_correction_requests')
              .select()
              .eq('staff_id', staff.id)
              .order('request_date', ascending: false);

          if (mounted) {
            setState(() {
              _leaves = data['leaveRequests'] ?? [];
              _advances = data['advances'] ?? [];
              _corrections = List<Map<String, dynamic>>.from(corrResponse);
            });
          }
        }
      }
    } catch (e) {
      print('Error loading requests: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: const SizedBox.shrink(),
        title: Text(
          'Requests',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary),
            onPressed: _loadRequests,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Advance Salary section
                  _buildSectionHeader('Advance Salary Requests'),
                  const SizedBox(height: 10),
                  if (_advances.isEmpty)
                    _buildEmptyCard('No advance salary requests found.')
                  else
                    ..._advances.take(3).map((a) {
                      final amt = (a['advance_amount'] as num?)?.toDouble() ?? 0.0;
                      final dateStr = a['given_date'] != null
                          ? DateFormat('dd MMM yyyy').format(DateTime.parse(a['given_date']))
                          : 'Unknown Date';
                      return CustomCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.orange.withOpacity(0.1),
                              child: const Icon(Icons.currency_rupee_rounded, color: Colors.orange),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '₹${amt.toStringAsFixed(0)}',
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'For ${a['salary_month'] ?? 'Current Month'} ($dateStr)',
                                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            _buildStatusBadge(a['status'] ?? 'Pending'),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 24),

                  // 2. Holiday Request section
                  _buildSectionHeader('Leave & Holiday Requests'),
                  const SizedBox(height: 10),
                  if (_leaves.isEmpty)
                    _buildEmptyCard('No leave requests found.')
                  else
                    ..._leaves.take(3).map((l) {
                      final start = DateTime.tryParse(l['start_date'] ?? '');
                      final end = DateTime.tryParse(l['end_date'] ?? '');
                      final dateStr = (start != null && end != null)
                          ? '${DateFormat('dd MMM').format(start)} - ${DateFormat('dd MMM yyyy').format(end)}'
                          : 'Unknown Date';
                      final totalDays = (start != null && end != null)
                          ? end.difference(start).inDays + 1
                          : 1;

                      return CustomCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.green.withOpacity(0.1),
                              child: const Icon(Icons.calendar_today_rounded, color: Colors.green),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$totalDays Days (${l['leave_type'] ?? 'Leave'})',
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    dateStr,
                                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            _buildStatusBadge(l['status'] ?? 'Pending'),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 24),

                  // 3. Attendance Correction Requests section
                  _buildSectionHeader('Attendance Correction Requests'),
                  const SizedBox(height: 10),
                  if (_corrections.isEmpty)
                    _buildEmptyCard('No correction requests found.')
                  else
                    ..._corrections.take(3).map((c) {
                      final reqDate = c['request_date'] != null
                          ? DateFormat('dd MMM yyyy').format(DateTime.parse(c['request_date']))
                          : 'Unknown Date';
                      return CustomCard(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: Colors.blue.withOpacity(0.1),
                              child: const Icon(Icons.edit_calendar_rounded, color: Colors.blue, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c['reason'] ?? 'Timing correction',
                                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Requested Date: $reqDate',
                                    style: GoogleFonts.inter(fontSize: 10.5, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            _buildStatusBadge(c['status'] ?? 'Pending'),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 32),

                  CustomButton(
                    text: '+ New Request',
                    color: AppTheme.primary,
                    onPressed: () async {
                      final res = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NewRequestScreen()),
                      );
                      if (res == true) {
                        _loadRequests();
                      }
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return CustomCard(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          message,
          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color text;
    if (status == 'Approved') {
      bg = const Color(0xFFE8F5E9);
      text = Colors.green;
    } else if (status == 'Pending') {
      bg = const Color(0xFFFFF3E0);
      text = Colors.orange;
    } else {
      bg = const Color(0xFFFFEBEE);
      text = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }
}
