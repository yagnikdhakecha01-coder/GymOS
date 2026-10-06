import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/repository/gym_repository.dart';
import '../../core/models/member.dart';
import '../../core/models/staff.dart';

class ManualAttendanceScreen extends StatefulWidget {
  const ManualAttendanceScreen({super.key});

  @override
  State<ManualAttendanceScreen> createState() => _ManualAttendanceScreenState();
}

class _ManualAttendanceScreenState extends State<ManualAttendanceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  // Selected data
  Member? _selectedMember;
  Staff? _selectedStaff;

  // Form states
  bool _isCheckIn = true;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _checkInTime = TimeOfDay.now();
  TimeOfDay? _checkOutTime;
  String _selectedShift = 'Single Shift';

  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    final repo = Provider.of<GymRepository>(context, listen: false);
    final role = repo.storage.getUserRole() ?? '';
    final isReceptionist = role.toLowerCase() == 'receptionist';

    // Tab controller has 1 tab for receptionist, 2 tabs for owner
    _tabController = TabController(length: isReceptionist ? 1 : 2, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = Provider.of<GymRepository>(context);
    final role = repo.storage.getUserRole() ?? '';
    final isReceptionist = role.toLowerCase() == 'receptionist';

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
          'Manual Attendance',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
        bottom: isReceptionist
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.primary,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                tabs: const [
                  Tab(text: 'Members'),
                  Tab(text: 'Staff'),
                ],
              ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Input Section
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: _tabController.index == 0 ? 'Search Active Members...' : 'Search Staff...',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppTheme.textMuted),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, color: AppTheme.textMuted),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.surfaceGray,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
                  ),
                ),
              ),
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: isReceptionist ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
                children: [
                  _buildMembersList(repo),
                  if (!isReceptionist) _buildStaffList(repo),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersList(GymRepository repo) {
    // Filter active members only
    final allMembers = repo.getMembers().where((m) => m.status == 'Active').toList();
    final filteredMembers = allMembers.where((m) {
      final query = _searchQuery.toLowerCase();
      return m.name.toLowerCase().contains(query) || m.phone.contains(query);
    }).toList();

    return Column(
      children: [
        Expanded(
          flex: 4,
          child: filteredMembers.isEmpty
              ? Center(
                  child: Text(
                    'No active members found',
                    style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredMembers.length,
                  itemBuilder: (context, index) {
                    final member = filteredMembers[index];
                    final isSelected = _selectedMember?.id == member.id;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedMember = isSelected ? null : member;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppTheme.primary : AppTheme.border,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppTheme.primary.withOpacity(0.08),
                                radius: 20,
                                child: Text(
                                  member.name.substring(0, 1).toUpperCase(),
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.primary),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member.name,
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      member.phone,
                                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 24)
                              else
                                const Icon(Icons.circle_outlined, color: AppTheme.textMuted, size: 24),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_selectedMember != null) _buildFormSection(isMember: true, repo: repo),
      ],
    );
  }

  Widget _buildStaffList(GymRepository repo) {
    final allStaff = repo.getStaff().where((s) => s.status == 'Active').toList();
    final filteredStaff = allStaff.where((s) {
      final query = _searchQuery.toLowerCase();
      return s.name.toLowerCase().contains(query) || s.phone.contains(query);
    }).toList();

    return Column(
      children: [
        Expanded(
          flex: 4,
          child: filteredStaff.isEmpty
              ? Center(
                  child: Text(
                    'No active staff found',
                    style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredStaff.length,
                  itemBuilder: (context, index) {
                    final staff = filteredStaff[index];
                    final isSelected = _selectedStaff?.id == staff.id;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedStaff = isSelected ? null : staff;
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? AppTheme.primary : AppTheme.border,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppTheme.primary.withOpacity(0.08),
                                radius: 20,
                                child: Text(
                                  staff.name.substring(0, 1).toUpperCase(),
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.primary),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      staff.name,
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${staff.role} • ${staff.phone}',
                                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded, color: AppTheme.primary, size: 24)
                              else
                                const Icon(Icons.circle_outlined, color: AppTheme.textMuted, size: 24),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_selectedStaff != null) _buildFormSection(isMember: false, repo: repo),
      ],
    );
  }

  Widget _buildFormSection({required bool isMember, required GymRepository repo}) {
    final name = isMember ? _selectedMember!.name : _selectedStaff!.name;
    final formattedDate = DateFormat('dd MMM yyyy').format(_selectedDate);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Marking for: $name',
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  formattedDate,
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Check-In / Check-Out Toggle
            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Check In')),
                    selected: _isCheckIn,
                    onSelected: (val) {
                      setState(() {
                        _isCheckIn = true;
                      });
                    },
                    selectedColor: AppTheme.primary,
                    labelStyle: GoogleFonts.inter(
                      color: _isCheckIn ? Colors.white : AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ChoiceChip(
                    label: const Center(child: Text('Check Out')),
                    selected: !_isCheckIn,
                    onSelected: (val) {
                      setState(() {
                        _isCheckIn = false;
                      });
                    },
                    selectedColor: AppTheme.primary,
                    labelStyle: GoogleFonts.inter(
                      color: !_isCheckIn ? Colors.white : AppTheme.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Time Selector
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(context: context, initialTime: _checkInTime);
                      if (picked != null) {
                        setState(() {
                          _checkInTime = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Check In Time', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
                          const SizedBox(height: 4),
                          Text(_checkInTime.format(context), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                if (!_isCheckIn) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _checkOutTime ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            _checkOutTime = picked;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Check Out Time', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
                            const SizedBox(height: 4),
                            Text(
                              _checkOutTime != null ? _checkOutTime!.format(context) : 'Select Time',
                              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Shift Selector
            Text(
              'Shift Selection',
              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedShift,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              items: const [
                DropdownMenuItem(value: 'Single Shift', child: Text('Single Shift')),
                DropdownMenuItem(value: 'Morning Shift', child: Text('Morning Shift')),
                DropdownMenuItem(value: 'Evening Shift', child: Text('Evening Shift')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedShift = val;
                  });
                }
              },
            ),
            const SizedBox(height: 20),

            // Save Button
            ElevatedButton(
              onPressed: () => _handleSave(isMember: isMember, repo: repo),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                'Save Attendance',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSave({required bool isMember, required GymRepository repo}) async {
    final gymId = repo.storage.getGymInfo()?['id'];
    if (gymId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Active Gym not found.'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    final dateStr = DateFormat('dd-MM-yyyy').format(_selectedDate);

    // Build ISO timestamps
    final now = DateTime.now();
    final checkInDateTime = DateTime(now.year, now.month, now.day, _checkInTime.hour, _checkInTime.minute);
    final checkInIso = checkInDateTime.toUtc().toIso8601String();

    String? checkOutIso;
    if (!_isCheckIn && _checkOutTime != null) {
      final checkOutDateTime = DateTime(now.year, now.month, now.day, _checkOutTime!.hour, _checkOutTime!.minute);
      checkOutIso = checkOutDateTime.toUtc().toIso8601String();
    }

    final String userName = isMember ? _selectedMember!.name : _selectedStaff!.name;
    final String? memberId = isMember ? _selectedMember!.id : null;
    final String? staffId = isMember ? null : _selectedStaff!.id;
    final String? userId = isMember ? null : _selectedStaff!.userId;

    if (_isCheckIn) {
      await repo.queueAttendance(
        gymId: gymId,
        memberId: memberId,
        staffId: staffId,
        userId: userId,
        attendanceType: 'Check In',
        shiftId: null, // Resolves dynamically on server or defaults
        date: dateStr,
        checkIn: checkInIso,
        status: 'Present',
        userType: isMember ? 'Member' : 'Staff',
        userName: userName,
      );
    } else {
      if (_checkOutTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select Check Out time.'), backgroundColor: AppTheme.danger),
        );
        return;
      }
      
      // Perform Check-out
      await repo.queueCheckOut(
        gymId: gymId,
        memberId: memberId,
        staffId: staffId,
        date: dateStr,
        checkOutTimeIso: checkOutIso!,
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance marked instantly offline.'), backgroundColor: AppTheme.success),
      );
      Navigator.pop(context);
    }
  }
}
