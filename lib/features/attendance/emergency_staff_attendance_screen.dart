import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/repository/gym_repository.dart';
import '../../features/authentication/auth_viewmodel.dart';
import 'attendance_viewmodel.dart';

/// Emergency Staff Attendance Screen.
/// Supports shift selection, time pickers, date picker, and reason input.
class EmergencyStaffAttendanceScreen extends StatefulWidget {
  const EmergencyStaffAttendanceScreen({super.key});

  @override
  State<EmergencyStaffAttendanceScreen> createState() => _EmergencyStaffAttendanceScreenState();
}

class _EmergencyStaffAttendanceScreenState extends State<EmergencyStaffAttendanceScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  String _searchQuery = '';
  Map<String, dynamic>? _selectedStaff;
  String _selectedShift = 'Single Shift';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _checkInTime = TimeOfDay.now();
  TimeOfDay? _checkOutTime;
  TimeOfDay _checkInTime2 = const TimeOfDay(hour: 17, minute: 0); // 5:00 PM evening default
  TimeOfDay? _checkOutTime2 = const TimeOfDay(hour: 22, minute: 0); // 10:00 PM evening default
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
    final vm = Provider.of<AttendanceViewModel>(context);
    final allStaff = vm.getOfflineStaff();

    final filtered = allStaff.where((s) {
      final name = (s['name'] as String? ?? '').toLowerCase();
      final phone = (s['phone'] as String? ?? '').toLowerCase();
      final role = (s['role'] as String? ?? '').toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery) || role.contains(_searchQuery);
    }).toList();

    // Determine shift options from staff info & gym configuration
    final shiftMode = vm.shiftMode;
    final shifts = vm.shiftsList;
    final staffShift = _selectedStaff?['shift'] as String?;
    final shiftOptions = _buildShiftOptions(staffShift, shiftMode, shifts);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Staff Attendance',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Search
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search staff by name, role, or phone...',
                hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, color: AppTheme.textMuted, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.surfaceGray,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
              ),
            ),
          ),

          Expanded(
            child: _selectedStaff == null
                ? _buildStaffList(filtered)
                : _buildFormSection(shiftOptions),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffList(List<Map<String, dynamic>> filtered) {
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_rounded, color: AppTheme.textMuted.withOpacity(0.4), size: 48),
            const SizedBox(height: 12),
            Text(
              'No active staff found',
              style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final staff = filtered[index];
        final name = staff['name'] as String? ?? '';
        final role = staff['role'] as String? ?? '';
        final phone = staff['phone'] as String? ?? '';
        final isSelected = _selectedStaff?['id'] == staff['id'];
        final avatarUrl = staff['avatar'] as String?;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: isSelected ? AppTheme.primary.withOpacity(0.04) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedStaff = staff;
                  final staffShift = staff['shift'] as String? ?? 'Both';
                  final lower = staffShift.toLowerCase();
                  if (lower.contains('both') || (lower.contains('morning') && lower.contains('evening'))) {
                    _selectedShift = 'Both';
                  } else {
                    _selectedShift = staffShift;
                  }
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppTheme.primary.withOpacity(0.4) : const Color(0xFFF0F0F2),
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: const Color(0xFFDBEAFE),
                      radius: 20,
                      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl != null && avatarUrl.isNotEmpty
                          ? null
                          : Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.info, fontSize: 15),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$role${phone.isNotEmpty ? ' • $phone' : ''}',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 22),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormSection(List<String> shiftOptions) {
    final staffName = _selectedStaff!['name'] as String? ?? '';
    final staffRole = _selectedStaff!['role'] as String? ?? '';
    final formattedDate = DateFormat('dd MMM yyyy').format(_selectedDate);
    final avatarUrl = _selectedStaff!['avatar'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selected Staff Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  radius: 22,
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl != null && avatarUrl.isNotEmpty
                      ? null
                      : Text(
                          staffName.isNotEmpty ? staffName[0].toUpperCase() : '?',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: 16),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staffName, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      Text(staffRole, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _selectedStaff = null),
                  child: Text('Change', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Shift Selector (if multiple shifts)
          if (shiftOptions.length > 1) ...[
            Text(
              'Select Shift',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: shiftOptions.map((shift) {
                final isSelected = _selectedShift == shift;
                return ChoiceChip(
                  label: Text(shift),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) setState(() => _selectedShift = shift);
                  },
                  selectedColor: AppTheme.primary,
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : AppTheme.textPrimary,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          // Date Selector
          Text(
            'Date',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime.now().subtract(const Duration(days: 30)),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _selectedDate = picked);
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, color: AppTheme.textSecondary, size: 18),
                  const SizedBox(width: 12),
                  Text(formattedDate, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                  const Spacer(),
                  const Icon(Icons.edit_calendar_rounded, color: AppTheme.primary, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Time Pickers
          if (_selectedShift == 'Both') ...[
            Text(
              'Morning Shift - Check-In & Check-Out Time',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildTimePicker('Check In', _checkInTime, (t) => setState(() => _checkInTime = t))),
                const SizedBox(width: 12),
                Expanded(child: _buildTimePicker('Check Out (optional)', _checkOutTime, (t) => setState(() => _checkOutTime = t))),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Evening Shift - Check-In & Check-Out Time',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildTimePicker('Check In', _checkInTime2, (t) => setState(() => _checkInTime2 = t))),
                const SizedBox(width: 12),
                Expanded(child: _buildTimePicker('Check Out (optional)', _checkOutTime2, (t) => setState(() => _checkOutTime2 = t))),
              ],
            ),
          ] else ...[
            Text(
              'Check-In & Check-Out Time',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildTimePicker('Check In', _checkInTime, (t) => setState(() => _checkInTime = t))),
                const SizedBox(width: 12),
                Expanded(child: _buildTimePicker('Check Out (optional)', _checkOutTime, (t) => setState(() => _checkOutTime = t))),
              ],
            ),
          ],
          const SizedBox(height: 24),

          // Reason
          Text(
            'Reason *',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _reasonController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'e.g., Server was down, Emergency attendance',
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
            onPressed: _isSaving ? null : _handleSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: _isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, color: Colors.white, size: 20),
            label: Text(
              _isSaving ? 'Saving...' : 'Save Attendance',
              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Status: Pending Cloud Sync',
              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFD97706), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker(String label, TimeOfDay? time, ValueChanged<TimeOfDay> onPicked) {
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
              time != null ? time.format(context) : 'Select Time',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: time != null ? AppTheme.textPrimary : AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _buildShiftOptions(String? staffShift, String shiftMode, List<Map<String, dynamic>> shifts) {
    if (staffShift != null && staffShift.isNotEmpty) {
      final lower = staffShift.toLowerCase();
      if (lower.contains('both') || (lower.contains('morning') && lower.contains('evening'))) {
        return ['Morning', 'Evening', 'Both'];
      }
      return [staffShift];
    }
    
    if (shiftMode == 'Multiple Shifts' && shifts.isNotEmpty) {
      final names = shifts.map((s) => s['name'] as String? ?? 'Shift').toList();
      if (names.length >= 2) {
        return [...names, 'Both'];
      }
      return names;
    }
    return ['Morning', 'Evening', 'Both'];
  }

  void _handleSave() async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a reason', style: GoogleFonts.inter()), backgroundColor: AppTheme.danger),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final vm = Provider.of<AttendanceViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? '';
      final ownerName = authVm.gymInfo?['owner'] ?? 'Owner';
      final role = authVm.selectedRole ?? 'Owner';
      final dateStr = DateFormat('dd-MM-yyyy').format(_selectedDate);

      if (_selectedShift == 'Both') {
        // Queue Morning Shift log
        final checkInDt1 = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day,
          _checkInTime.hour, _checkInTime.minute,
        );
        final checkInIso1 = checkInDt1.toUtc().toIso8601String();

        String? checkOutIso1;
        if (_checkOutTime != null) {
          final checkOutDt1 = DateTime(
            _selectedDate.year, _selectedDate.month, _selectedDate.day,
            _checkOutTime!.hour, _checkOutTime!.minute,
          );
          checkOutIso1 = checkOutDt1.toUtc().toIso8601String();
        }

        await vm.markManualStaffAttendance(
          gymId: gymId,
          staffId: _selectedStaff!['id'] as String,
          userId: _selectedStaff!['user_id'] as String?,
          staffName: _selectedStaff!['name'] as String? ?? '',
          shiftId: null,
          shiftName: 'Morning',
          checkInIso: checkInIso1,
          checkOutIso: checkOutIso1,
          date: dateStr,
          reason: reason,
          addedBy: ownerName,
          addedByRole: role.isEmpty ? 'Owner' : role,
        );

        // Queue Evening Shift log
        final checkInDt2 = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day,
          _checkInTime2.hour, _checkInTime2.minute,
        );
        final checkInIso2 = checkInDt2.toUtc().toIso8601String();

        String? checkOutIso2;
        if (_checkOutTime2 != null) {
          final checkOutDt2 = DateTime(
            _selectedDate.year, _selectedDate.month, _selectedDate.day,
            _checkOutTime2!.hour, _checkOutTime2!.minute,
          );
          checkOutIso2 = checkOutDt2.toUtc().toIso8601String();
        }

        await vm.markManualStaffAttendance(
          gymId: gymId,
          staffId: _selectedStaff!['id'] as String,
          userId: _selectedStaff!['user_id'] as String?,
          staffName: _selectedStaff!['name'] as String? ?? '',
          shiftId: null,
          shiftName: 'Evening',
          checkInIso: checkInIso2,
          checkOutIso: checkOutIso2,
          date: dateStr,
          reason: reason,
          addedBy: ownerName,
          addedByRole: role.isEmpty ? 'Owner' : role,
        );
      } else {
        // Single shift
        final checkInDt = DateTime(
          _selectedDate.year, _selectedDate.month, _selectedDate.day,
          _checkInTime.hour, _checkInTime.minute,
        );
        final checkInIso = checkInDt.toUtc().toIso8601String();

        String? checkOutIso;
        if (_checkOutTime != null) {
          final checkOutDt = DateTime(
            _selectedDate.year, _selectedDate.month, _selectedDate.day,
            _checkOutTime!.hour, _checkOutTime!.minute,
          );
          checkOutIso = checkOutDt.toUtc().toIso8601String();
        }

        await vm.markManualStaffAttendance(
          gymId: gymId,
          staffId: _selectedStaff!['id'] as String,
          userId: _selectedStaff!['user_id'] as String?,
          staffName: _selectedStaff!['name'] as String? ?? '',
          shiftId: null,
          shiftName: _selectedShift,
          checkInIso: checkInIso,
          checkOutIso: checkOutIso,
          date: dateStr,
          reason: reason,
          addedBy: ownerName,
          addedByRole: role.isEmpty ? 'Owner' : role,
        );
      }

      if (mounted) {
        final staffName = _selectedStaff!['name'] as String? ?? 'Staff';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$staffName marked present • Pending Cloud Sync',
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
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
