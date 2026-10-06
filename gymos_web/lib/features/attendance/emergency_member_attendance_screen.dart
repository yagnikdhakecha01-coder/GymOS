import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/repository/gym_repository.dart';
import '../../features/authentication/auth_viewmodel.dart';
import 'attendance_viewmodel.dart';

/// Emergency Member Attendance Screen with multi-select support.
/// Shows only active members whose attendance is NOT yet marked today.
class EmergencyMemberAttendanceScreen extends StatefulWidget {
  const EmergencyMemberAttendanceScreen({super.key});

  @override
  State<EmergencyMemberAttendanceScreen> createState() => _EmergencyMemberAttendanceScreenState();
}

class _EmergencyMemberAttendanceScreenState extends State<EmergencyMemberAttendanceScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  final Set<String> _selectedIds = {};
  String _searchQuery = '';
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
    final members = vm.getUnmarkedMembersToday();

    final filtered = members.where((m) {
      final name = (m['name'] as String? ?? '').toLowerCase();
      final phone = (m['phone'] as String? ?? '').toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery);
    }).toList();

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
          'Member Attendance',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
        actions: [
          if (_selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_selectedIds.length} selected',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search + Select All Row
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search members by name or phone...',
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
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${filtered.length} member${filtered.length != 1 ? 's' : ''} available',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          if (_selectedIds.length == filtered.length) {
                            _selectedIds.clear();
                          } else {
                            _selectedIds.clear();
                            for (final m in filtered) {
                              _selectedIds.add(m['id'] as String);
                            }
                          }
                        });
                      },
                      icon: Icon(
                        _selectedIds.length == filtered.length && filtered.isNotEmpty
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded,
                        size: 16,
                        color: AppTheme.primary,
                      ),
                      label: Text(
                        _selectedIds.length == filtered.length && filtered.isNotEmpty
                            ? 'Deselect All'
                            : 'Select All',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Member List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, color: AppTheme.success.withOpacity(0.5), size: 48),
                        const SizedBox(height: 12),
                        Text(
                          'All members are marked for today',
                          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No unmarked active members found',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final member = filtered[index];
                      final id = member['id'] as String;
                      final name = member['name'] as String? ?? '';
                      final phone = member['phone'] as String? ?? '';
                      final isSelected = _selectedIds.contains(id);

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: isSelected ? AppTheme.primary.withOpacity(0.04) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedIds.remove(id);
                                } else {
                                  _selectedIds.add(id);
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
                                  // Avatar
                                  CircleAvatar(
                                    backgroundColor: isSelected
                                        ? AppTheme.primary.withOpacity(0.12)
                                        : const Color(0xFFF3F4F6),
                                    radius: 20,
                                    child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Name + Phone
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        if (phone.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              phone,
                                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Checkbox
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: isSelected
                                        ? const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 24, key: ValueKey('checked'))
                                        : const Icon(Icons.circle_outlined, color: AppTheme.textMuted, size: 24, key: ValueKey('unchecked')),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      // Bottom Action Bar
      bottomSheet: _selectedIds.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Reason Input
                  TextField(
                    controller: _reasonController,
                    decoration: InputDecoration(
                      hintText: 'Reason (e.g., Server down, Emergency)',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                      prefixIcon: const Icon(Icons.notes_rounded, color: AppTheme.textMuted, size: 20),
                      filled: true,
                      fillColor: AppTheme.surfaceGray,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Mark Attendance Button
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : () => _handleMarkAttendance(context, filtered),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded, color: Colors.white, size: 20),
                    label: Text(
                      _isSaving
                          ? 'Saving...'
                          : 'Mark ${_selectedIds.length} Member${_selectedIds.length > 1 ? 's' : ''} Present',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      'Status: Pending Cloud Sync',
                      style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFD97706), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _handleMarkAttendance(BuildContext context, List<Map<String, dynamic>> allMembers) async {
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter a reason for manual attendance', style: GoogleFonts.inter()),
          backgroundColor: AppTheme.danger,
        ),
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

      // Filter selected members
      final selectedMembers = allMembers.where((m) => _selectedIds.contains(m['id'])).toList();

      await vm.markManualMemberAttendance(
        gymId: gymId,
        members: selectedMembers,
        reason: reason,
        addedBy: ownerName,
        addedByRole: role.isEmpty ? 'Owner' : role,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${selectedMembers.length} member${selectedMembers.length > 1 ? 's' : ''} marked present • Pending Cloud Sync',
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
          SnackBar(
            content: Text('Error: $e', style: GoogleFonts.inter()),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
