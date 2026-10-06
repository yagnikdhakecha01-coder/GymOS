import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/attendance.dart';
import '../../features/authentication/auth_viewmodel.dart';
import 'attendance_viewmodel.dart';

/// Owner-level direct attendance correction screen.
/// Allows Owner to search, find, and directly correct any attendance record.
class OwnerAttendanceCorrectionScreen extends StatefulWidget {
  const OwnerAttendanceCorrectionScreen({super.key});

  @override
  State<OwnerAttendanceCorrectionScreen> createState() => _OwnerAttendanceCorrectionScreenState();
}

class _OwnerAttendanceCorrectionScreenState extends State<OwnerAttendanceCorrectionScreen> {
  DateTime _selectedDate = DateTime.now();
  String _userTypeFilter = 'All'; // 'All', 'Member', 'Staff'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Correction form
  AttendanceRecord? _selectedRecord;
  String? _newStatus;
  TimeOfDay? _newCheckIn;
  TimeOfDay? _newCheckOut;
  final TextEditingController _reasonController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () {
            if (_selectedRecord != null) {
              setState(() => _selectedRecord = null);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _selectedRecord != null ? 'Correct Record' : 'Attendance Correction',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
      ),
      body: _selectedRecord != null
          ? _buildCorrectionForm()
          : _buildRecordBrowser(),
    );
  }

  Widget _buildRecordBrowser() {
    final repo = Provider.of<GymRepository>(context);
    final dateStr = DateFormat('dd-MM-yyyy').format(_selectedDate);

    // Filter attendance records for selected date
    final records = repo.getAttendance().where((r) {
      if (r.date != dateStr) return false;
      if (_userTypeFilter != 'All' && r.userType != _userTypeFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final name = r.userName.toLowerCase();
        return name.contains(_searchQuery);
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Date Picker + Filters
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            children: [
              // Date Selector
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 90)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setState(() => _selectedDate = picked);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceGray,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: AppTheme.primary, size: 18),
                      const SizedBox(width: 10),
                      Text(
                        DateFormat('dd MMM yyyy (EEEE)').format(_selectedDate),
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Type Filter + Search
              Row(
                children: [
                  // Type Filter Chips
                  ..._buildFilterChips(),
                  const Spacer(),
                  // Record count
                  Text(
                    '${records.length} record${records.length != 1 ? 's' : ''}',
                    style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Search
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search by name...',
                  hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
                  filled: true,
                  fillColor: AppTheme.surfaceGray,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                ),
              ),
            ],
          ),
        ),

        // Records List
        Expanded(
          child: records.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_busy_rounded, color: AppTheme.textMuted.withOpacity(0.4), size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'No attendance records found',
                        style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        'for ${DateFormat('dd MMM yyyy').format(_selectedDate)}',
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return _buildRecordCard(record);
                  },
                ),
        ),
      ],
    );
  }

  List<Widget> _buildFilterChips() {
    final filters = ['All', 'Member', 'Staff'];
    return filters.map((f) {
      final isSelected = _userTypeFilter == f;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(f),
          selected: isSelected,
          onSelected: (val) {
            if (val) setState(() => _userTypeFilter = f);
          },
          selectedColor: AppTheme.primary,
          labelStyle: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: isSelected ? Colors.white : AppTheme.textPrimary,
          ),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      );
    }).toList();
  }

  Map<String, String?> _getUserDetails(AttendanceRecord record, GymRepository repo) {
    String resolvedName = record.userName;
    String? resolvedAvatar;

    if (record.userType == 'Staff') {
      final staff = repo.getOfflineStaff().firstWhere(
        (s) => s['id'] == record.staffId || s['id'] == record.userId || s['user_id'] == record.userId,
        orElse: () => <String, dynamic>{},
      );
      if (staff.isNotEmpty) {
        if (resolvedName == 'User' || resolvedName.isEmpty) {
          resolvedName = staff['name'] as String? ?? 'User';
        }
        resolvedAvatar = staff['avatar'] as String?;
      }
    } else {
      final member = repo.getOfflineMembers().firstWhere(
        (m) => m['id'] == record.userId || m['user_id'] == record.userId,
        orElse: () => <String, dynamic>{},
      );
      if (member.isNotEmpty) {
        if (resolvedName == 'User' || resolvedName.isEmpty) {
          resolvedName = member['name'] as String? ?? 'User';
        }
        resolvedAvatar = member['avatar'] as String?;
      }
    }

    return {'name': resolvedName, 'avatar': resolvedAvatar};
  }

  Widget _buildRecordCard(AttendanceRecord record) {
    final repo = Provider.of<GymRepository>(context, listen: false);
    final userDetails = _getUserDetails(record, repo);
    final resolvedName = userDetails['name'] ?? 'User';
    final resolvedAvatar = userDetails['avatar'];
    final statusColor = _getStatusColor(record.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedRecord = record;
              _newStatus = record.status;
              _newCheckIn = _parseTimeOfDay(record.checkInTime);
              _newCheckOut = _parseTimeOfDay(record.checkOutTime);
              _reasonController.clear();
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF0F0F2)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: record.userType == 'Staff'
                      ? const Color(0xFFDBEAFE)
                      : const Color(0xFFEDE9FE),
                  radius: 20,
                  backgroundImage: resolvedAvatar != null && resolvedAvatar.isNotEmpty
                      ? NetworkImage(resolvedAvatar)
                      : null,
                  child: resolvedAvatar != null && resolvedAvatar.isNotEmpty
                      ? null
                      : Text(
                          resolvedName.isNotEmpty ? resolvedName[0].toUpperCase() : '?',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            color: record.userType == 'Staff' ? AppTheme.info : AppTheme.primary,
                            fontSize: 15,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              resolvedName,
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              record.status,
                              style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: statusColor),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            record.userType,
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                          ),
                          if (record.checkInTime != null && record.checkInTime!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text('•', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                            const SizedBox(width: 6),
                            Text(
                              'In: ${record.checkInTime}',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                          if (record.checkOutTime != null && record.checkOutTime!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              'Out: ${record.checkOutTime}',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                          ],
                          if (record.method != null && record.method!.isNotEmpty) ...[
                            const Spacer(),
                            Text(
                              record.method!,
                              style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.edit_rounded, color: AppTheme.textMuted, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCorrectionForm() {
    final record = _selectedRecord!;
    final repo = Provider.of<GymRepository>(context, listen: false);
    final userDetails = _getUserDetails(record, repo);
    final resolvedName = userDetails['name'] ?? 'User';
    final resolvedAvatar = userDetails['avatar'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current Record Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF0F0F2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: record.userType == 'Staff'
                          ? const Color(0xFFDBEAFE)
                          : const Color(0xFFEDE9FE),
                      radius: 20,
                      backgroundImage: resolvedAvatar != null && resolvedAvatar.isNotEmpty
                          ? NetworkImage(resolvedAvatar)
                          : null,
                      child: resolvedAvatar != null && resolvedAvatar.isNotEmpty
                          ? null
                          : Text(
                              resolvedName.isNotEmpty ? resolvedName[0].toUpperCase() : '?',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                color: record.userType == 'Staff' ? AppTheme.info : AppTheme.primary,
                                fontSize: 15,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(resolvedName, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                          Text('${record.userType} • ${record.date}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24, color: Color(0xFFF3F4F6)),
                // Current Values
                _buildInfoRow('Current Status', record.status, _getStatusColor(record.status)),
                if (record.checkInTime != null && record.checkInTime!.isNotEmpty)
                  _buildInfoRow('Current Check-In', record.checkInTime!, AppTheme.textSecondary),
                if (record.checkOutTime != null && record.checkOutTime!.isNotEmpty)
                  _buildInfoRow('Current Check-Out', record.checkOutTime!, AppTheme.textSecondary),
                if (record.method != null && record.method!.isNotEmpty)
                  _buildInfoRow('Method', record.method!, AppTheme.textSecondary),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Correction Form
          Text(
            'New Values',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Only changed fields will be updated',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 16),

          // Status
          Text(
            'Status',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['Present', 'Absent', 'Late', 'Half Day', 'On Leave'].map((s) {
              final isSelected = _newStatus == s;
              final color = _getStatusColor(s);
              return ChoiceChip(
                label: Text(s),
                selected: isSelected,
                onSelected: (val) {
                  if (val) setState(() => _newStatus = s);
                },
                selectedColor: color.withOpacity(0.2),
                labelStyle: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? color : AppTheme.textPrimary,
                ),
                side: BorderSide(color: isSelected ? color.withOpacity(0.5) : const Color(0xFFE5E7EB)),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Time Pickers
          Text(
            'Check-In & Check-Out Time',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildCorrectionTimePicker('New Check In', _newCheckIn, (t) => setState(() => _newCheckIn = t))),
              const SizedBox(width: 12),
              Expanded(child: _buildCorrectionTimePicker('New Check Out', _newCheckOut, (t) => setState(() => _newCheckOut = t))),
            ],
          ),
          const SizedBox(height: 20),

          // Reason
          Text(
            'Reason for Correction *',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Explain why this correction is needed...',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 28),

          // Save Button
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _handleCorrection,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD97706),
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, color: Colors.white, size: 20),
            label: Text(
              _isSaving ? 'Saving...' : 'Apply Correction',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),

          // Warning
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This correction will be logged in the audit trail. All corrections are permanent and traceable.',
                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF92400E), height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Audit Trail for this record
          _buildAuditTrail(),
        ],
      ),
    );
  }

  Widget _buildAuditTrail() {
    final vm = Provider.of<AttendanceViewModel>(context);
    final record = _selectedRecord!;
    final logs = vm.getAuditLogs(date: record.date).where((log) {
      return log.targetUserId == record.userId;
    }).toList();

    if (logs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Audit Trail',
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        ...logs.map((log) {
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFF0F0F2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      log.actionType == 'attendance_correction' ? Icons.edit_note_rounded : Icons.person_add_alt_rounded,
                      color: AppTheme.textMuted,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      log.actionType == 'attendance_correction' ? 'Correction' : 'Manual Entry',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('hh:mm a').format(log.createdAt.toLocal()),
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'By ${log.performedBy} (${log.performedByRole})',
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                ),
                if (log.oldStatus != null && log.newStatus != null && log.oldStatus != log.newStatus)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Status: ${log.oldStatus} → ${log.newStatus}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.info),
                    ),
                  ),
                if (log.reason.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Reason: ${log.reason}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted)),
          Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  Widget _buildCorrectionTimePicker(String label, TimeOfDay? time, ValueChanged<TimeOfDay> onPicked) {
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: time ?? TimeOfDay.now(),
        );
        if (picked != null) onPicked(picked);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(
              time != null ? time.format(context) : 'Not Set',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: time != null ? AppTheme.textPrimary : AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Present':
        return AppTheme.success;
      case 'Absent':
        return AppTheme.danger;
      case 'Late':
        return AppTheme.warning;
      case 'Half Day':
        return AppTheme.info;
      case 'On Leave':
        return AppTheme.textMuted;
      default:
        return AppTheme.textSecondary;
    }
  }

  TimeOfDay? _parseTimeOfDay(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      final dt = DateFormat('hh:mm a').parse(timeStr);
      return TimeOfDay(hour: dt.hour, minute: dt.minute);
    } catch (_) {
      return null;
    }
  }

  void _handleCorrection() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a reason for this correction', style: GoogleFonts.inter()), backgroundColor: AppTheme.danger),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final vm = Provider.of<AttendanceViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? '';
      final ownerName = authVm.gymInfo?['owner'] ?? 'Owner';
      final record = _selectedRecord!;

      // Determine what changed
      String? newCheckInStr;
      String? newCheckOutStr;
      if (_newCheckIn != null) {
        newCheckInStr = _newCheckIn!.format(context);
      }
      if (_newCheckOut != null) {
        newCheckOutStr = _newCheckOut!.format(context);
      }

      final result = await vm.ownerCorrectAttendance(
        gymId: gymId,
        logId: record.id,
        targetUserId: record.userId,
        targetUserName: record.userName,
        targetUserType: record.userType,
        date: record.date,
        newStatus: _newStatus != record.status ? _newStatus : null,
        newCheckIn: newCheckInStr != record.checkInTime ? newCheckInStr : null,
        newCheckOut: newCheckOutStr != record.checkOutTime ? newCheckOutStr : null,
        reason: reason,
        correctedBy: ownerName,
      );

      if (mounted) {
        final success = result['success'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(success ? Icons.check_circle_rounded : Icons.error_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    success ? 'Attendance corrected for ${record.userName}' : (result['message'] ?? 'Correction failed'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: success ? AppTheme.success : AppTheme.danger,
            duration: const Duration(seconds: 3),
          ),
        );
        if (success) setState(() => _selectedRecord = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e', style: GoogleFonts.inter()), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
