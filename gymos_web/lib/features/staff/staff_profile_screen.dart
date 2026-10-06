import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/models/staff.dart';
import 'staff_viewmodel.dart';
import '../members/members_viewmodel.dart';
import 'pay_salary_screen.dart';
import '../authentication/auth_viewmodel.dart';
import '../../core/widgets/success_dialog.dart';
import '../../core/widgets/app_cached_avatar.dart';
import '../../core/services/supabase_service.dart';
import '../../core/widgets/invitation_share_sheet.dart';

class StaffProfileScreen extends StatefulWidget {
  final Staff staff;
  final bool isOwnerView;
  const StaffProfileScreen({super.key, required this.staff, this.isOwnerView = true});

  @override
  State<StaffProfileScreen> createState() => _StaffProfileScreenState();
}

class _StaffProfileScreenState extends State<StaffProfileScreen> {
  int _currentTabIndex = 0;

  // Attendance tab state
  DateTime _attendanceMonth = DateTime.now();

  // Advance Salary tab state
  int _advanceFilterIndex = 0;

  // Leave Requests tab state
  int _leaveFilterIndex = 0;

  // Second page (Salary & Requests) subtab: 0: All Overview, 1: Advance Salary, 2: Leave Requests, 3: Salary History
  int _payrollSubTabIndex = 0;

  // Account Status / Invitation tracking
  Map<String, dynamic>? _invitation;
  bool _loadingInvitation = false;

  // Dynamic tab data
  List<Map<String, dynamic>> _attendanceRecords = [];
  List<Map<String, dynamic>> _advanceSalaryRecords = [];
  List<Map<String, dynamic>> _leaveRequests = [];
  List<Map<String, dynamic>> _leaveHistory = [];
  List<Map<String, dynamic>> _salaryHistory = [];
  double _pendingSalaryFromDb = 0.0;
  String _gymShiftMode = 'Single Shift';

  // Custom Shift Profile Card State
  late String _profileShiftType;
  late String _profileShift1Start;
  late String _profileShift1End;
  late String _profileShift2Start;
  late String _profileShift2End;
  bool _isSavingShiftSettings = false;

  @override
  void initState() {
    super.initState();
    _profileShiftType = widget.staff.shiftType.isNotEmpty ? widget.staff.shiftType : 'single';
    _profileShift1Start = widget.staff.shift1Start.isNotEmpty ? widget.staff.shift1Start : '09:00 AM';
    _profileShift1End = widget.staff.shift1End.isNotEmpty ? widget.staff.shift1End : '05:00 PM';
    _profileShift2Start = widget.staff.shift2Start.isNotEmpty ? widget.staff.shift2Start : '04:00 PM';
    _profileShift2End = widget.staff.shift2End.isNotEmpty ? widget.staff.shift2End : '09:00 PM';

    // Instant synchronous hydration from local cache (Zero lag opening)
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    final rawAtt = staffVm.getStaffAttendance(widget.staff.id);
    _attendanceRecords = rawAtt.map((r) => {
      'date': r.date,
      'status': r.status,
    }).toList();
    final currentMonthStr = DateFormat('MMMM yyyy').format(DateTime.now());
    _pendingSalaryFromDb = staffVm.isSalaryPaid(widget.staff.id, currentMonthStr) 
        ? 0.0 
        : (staffVm.getStaffCachedPayable(widget.staff.id) > 0 ? staffVm.getStaffCachedPayable(widget.staff.id) : widget.staff.salary);

    _loadInvitation();
    _fetchDbTabsData();
  }

  Future<void> _fetchDbTabsData() async {
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    final data = await staffVm.getStaffDashboardData(widget.staff.id);
    
    double pendingSalary = 0.0;
    final currentMonthStr = DateFormat('MMMM yyyy').format(DateTime.now());
    if (gymId != null) {
      pendingSalary = await staffVm.getStaffPendingPayable(
        gymId: gymId,
        staff: widget.staff,
        salaryMonth: currentMonthStr,
      );
    }

    try {
      if (gymId != null) {
        final settingsRes = await SupabaseService.client
            .from('gym_shift_settings')
            .select('mode')
            .eq('gym_id', gymId)
            .maybeSingle();

        if (settingsRes != null) {
          _gymShiftMode = settingsRes['mode'] ?? 'Single Shift';
        }
      }
    } catch (e) {
      print('Error fetching gym shift mode: $e');
    }

    final salaryHist = data['salaryHistory'] as List? ?? [];

    if (mounted) {
      setState(() {
        _attendanceRecords = data['attendance'] ?? [];
        _advanceSalaryRecords = data['advance'] ?? [];
        _leaveRequests = data['leaveRequests'] ?? [];
        _leaveHistory = data['leaveHistory'] ?? [];
        _salaryHistory = List<Map<String, dynamic>>.from(salaryHist);
        _pendingSalaryFromDb = pendingSalary;
      });
    }
  }

  Future<void> _loadInvitation() async {
    if (!mounted) return;
    setState(() => _loadingInvitation = true);
    try {
      final staffVm = Provider.of<StaffViewModel>(context, listen: false);
      final invite = await staffVm.getLatestInvitation(widget.staff.id);
      if (mounted) {
        setState(() {
          _invitation = invite;
          _loadingInvitation = false;
        });
      }
    } catch (e) {
      print('_loadInvitation error: $e');
      if (mounted) {
        setState(() => _loadingInvitation = false);
      }
    }
  }

  void _shareInvitationCode(String code, String phone) {
    InvitationShareSheet.show(
      context: context,
      invitationCode: code,
      phone: phone,
      recipientName: widget.staff.name,
      isStaff: true,
      role: widget.staff.role,
    );
  }

  Future<void> _confirmUnlinkStaff(StaffViewModel vm, Staff staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Unlink Account?', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text(
          'This staff account will be unlinked.\nThey will require a new invitation code to connect again.',
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Unlink', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _loadingInvitation = true);
      final newCode = await vm.unlinkAccount(staff.id);
      await _loadInvitation();
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Account Unlinked', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'The account has been unlinked successfully.\nHere is the new invitation code for reconnection:',
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    newCode,
                    style: GoogleFonts.robotoMono(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primary, letterSpacing: 2),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Done', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _generateNewStaffCode(StaffViewModel vm, Staff staff) async {
    setState(() => _loadingInvitation = true);
    await vm.generateInvitation(
      recordId: staff.id,
      name: staff.name,
      phone: staff.phone,
    );
    await _loadInvitation();
  }

  void _showEditBasicInfoDialog(BuildContext context, Staff staff) {
    final nameCtrl = TextEditingController(text: staff.name);
    final phoneCtrl = TextEditingController(text: staff.phone);
    final emailCtrl = TextEditingController(text: staff.email);
    final dobCtrl = TextEditingController(text: staff.dob);
    final addressCtrl = TextEditingController(text: staff.address);
    final salaryCtrl = TextEditingController(text: staff.salary.toStringAsFixed(0));
    
    String gender = ['Male', 'Female', 'Other'].contains(staff.gender) ? staff.gender : 'Male';
    String salaryType = ['Fixed Salary', 'Commission', 'Both'].contains(staff.salaryType) ? staff.salaryType : 'Fixed Salary';

    final availableShifts = ['Single Shift', 'Morning Shift', 'Evening Shift', 'Both Shifts'];
    if (!availableShifts.contains(staff.shift) && staff.shift.isNotEmpty) {
      availableShifts.add(staff.shift);
    }
    String shift = availableShifts.contains(staff.shift) ? staff.shift : availableShifts.first;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setModalState) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(dialogCtx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Edit Staff Basic Info', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(dialogCtx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(labelText: 'Phone'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(labelText: 'Email'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: dobCtrl,
                            decoration: const InputDecoration(labelText: 'Date of Birth (e.g. 15 Aug 1995)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: gender,
                            decoration: const InputDecoration(labelText: 'Gender'),
                            items: ['Male', 'Female', 'Other']
                                .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setModalState(() => gender = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressCtrl,
                      decoration: const InputDecoration(labelText: 'Address'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: shift,
                      decoration: const InputDecoration(labelText: 'Assigned Gym Shift'),
                      items: availableShifts
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => shift = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: salaryCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Monthly Salary (₹)'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: salaryType,
                            decoration: const InputDecoration(labelText: 'Salary Type'),
                            items: ['Fixed Salary', 'Commission', 'Both']
                                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                .toList(),
                            onChanged: (val) {
                              if (val != null) setModalState(() => salaryType = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        final double salaryVal = double.tryParse(salaryCtrl.text) ?? staff.salary;
                        final isBothShiftMode = shift.toLowerCase().contains('both');
                        final newShiftType = isBothShiftMode ? 'both' : 'single';

                        final updatedStaff = staff.copyWith(
                          name: nameCtrl.text.trim(),
                          phone: phoneCtrl.text.trim(),
                          email: emailCtrl.text.trim(),
                          dob: dobCtrl.text.trim(),
                          gender: gender,
                          address: addressCtrl.text.trim(),
                          salary: salaryVal,
                          salaryType: salaryType,
                          shift: shift,
                          shiftType: newShiftType,
                        );

                        Navigator.pop(dialogCtx);

                        // Show loading indicator
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (c) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                        );

                        try {
                          final staffVm = Provider.of<StaffViewModel>(context, listen: false);
                          await staffVm.saveStaff(updatedStaff);
                          if (context.mounted) {
                            Navigator.pop(context); // Pop loading spinner
                            setState(() {
                              _profileShiftType = newShiftType;
                            });
                            SuccessDialog.show(
                              context,
                              title: 'Staff Profile Updated!',
                              message: 'Staff details updated successfully.',
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      child: Text('Save Changes', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final staffVm = Provider.of<StaffViewModel>(context);
    final staff = staffVm.allStaff.firstWhere((s) => s.id == widget.staff.id, orElse: () => widget.staff);

    return PopScope(
      canPop: _currentTabIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentTabIndex != 0) {
          setState(() => _currentTabIndex = 0);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () {
              if (_currentTabIndex != 0) {
                setState(() => _currentTabIndex = 0);
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text(
            _currentTabIndex == 0
                ? 'Staff Profile'
                : (_payrollSubTabIndex == 0
                    ? 'Salary & Requests'
                    : (_payrollSubTabIndex == 1
                        ? 'Advance Salary'
                        : (_payrollSubTabIndex == 2
                            ? 'Leave Requests'
                            : 'Salary History'))),
            style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          centerTitle: true,
          actions: widget.isOwnerView
              ? [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: AppTheme.textPrimary),
                    onSelected: (val) {
                      if (val == 'delete') {
                        _confirmDeleteStaff(context, staff);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                            SizedBox(width: 10),
                            Text('Delete Staff', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ]
              : null,
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: _buildCurrentTab(staff),
          ),
        ),
        bottomNavigationBar: Container(
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Center(
              heightFactor: 1.0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: _buildBottomNav(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTab(Staff staff) {
    if (widget.isOwnerView) {
      switch (_currentTabIndex) {
        case 0:
          return _buildInfoTab(staff);
        case 1:
          return _buildPayrollAndRequestsTab(staff);
        default:
          return _buildInfoTab(staff);
      }
    } else {
      // Staff view: Profile & Attendance
      return _buildInfoTab(staff);
    }
  }

  // ═══════════════════════════════════════════════════════
  // BOTTOM NAVIGATION BAR
  // ═══════════════════════════════════════════════════════
  Widget _buildBottomNav() {
    final List<Map<String, dynamic>> items = widget.isOwnerView
        ? [
            {'icon': Icons.badge_outlined, 'activeIcon': Icons.badge, 'label': 'Profile & Attendance'},
            {'icon': Icons.account_balance_wallet_outlined, 'activeIcon': Icons.account_balance_wallet, 'label': 'Salary & Requests'},
          ]
        : [
            {'icon': Icons.badge_outlined, 'activeIcon': Icons.badge, 'label': 'Profile & Attendance'},
          ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (index) {
              final isActive = _currentTabIndex == index;
              return GestureDetector(
                onTap: () => setState(() => _currentTabIndex = index),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 140,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive ? items[index]['activeIcon'] as IconData : items[index]['icon'] as IconData,
                        size: 20,
                        color: isActive ? AppTheme.primary : AppTheme.textMuted,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        items[index]['label'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                          color: isActive ? AppTheme.primary : AppTheme.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 1: INFO
  // ═══════════════════════════════════════════════════════
  Widget _buildInfoTab(Staff staff) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final assignedMembers = membersVm.allMembers.where((m) => m.ptTrainer == staff.id).length;

    final leftChildren = <Widget>[
      // ── Profile Header Card ──
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AppCachedAvatar(
              imageUrl: staff.avatar,
              name: staff.name,
              size: 56,
              border: Border.all(color: const Color(0xFF1F2937), width: 1.5),
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
                          staff.name,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(staff.role, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceGray,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'STA-${staff.id.substring(0, 6).toUpperCase()}',
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w500, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _iconInfoRow(Icons.phone_outlined, staff.phone)),
                      Expanded(child: _iconInfoRow(Icons.email_outlined, staff.email)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(child: _iconInfoRow(Icons.calendar_today_outlined, 'Joined ${staff.joinDate}')),
                      Expanded(child: _iconInfoRow(Icons.access_time_filled_outlined, staff.shift.isNotEmpty ? staff.shift : 'Single Shift')),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),

      // ── Stats / Employment Card ──
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(staff.name, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    Text(staff.role, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: staff.status == 'Active' ? AppTheme.successLight : AppTheme.dangerLight,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    staff.status,
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: staff.status == 'Active' ? AppTheme.success : AppTheme.danger),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 10),
            Row(
              children: [
                _statColumn('Start Date', staff.joinDate, AppTheme.textPrimary),
                if (widget.isOwnerView) ...[
                  _statColumn('Salary Type', staff.salaryType.isNotEmpty ? staff.salaryType : 'Fixed', AppTheme.textPrimary),
                  Builder(builder: (ctx) {
                    final staffVm = ctx.watch<StaffViewModel>();
                    final currentMonthStr = DateFormat('MMMM yyyy').format(DateTime.now());
                    final bool isPaidNow = staffVm.isSalaryPaid(staff.id, currentMonthStr);
                    final double effectivePendingSalary = isPaidNow ? 0.0 : _pendingSalaryFromDb;
                    return _statColumn(
                      'Pending Salary', 
                      isPaidNow ? '₹0' : '₹${NumberFormat('#,##,###').format(effectivePendingSalary)}', 
                      isPaidNow ? AppTheme.success : AppTheme.primary,
                    );
                  }),
                ] else ...[
                  _statColumn('Shift', staff.shift.isNotEmpty ? staff.shift : '—', AppTheme.textPrimary),
                  _statColumn('Department', staff.department.isNotEmpty ? staff.department : '—', AppTheme.textPrimary),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _statColumn('Total Members', '$assignedMembers', AppTheme.textPrimary),
                _statColumn('This Month Att.', '0/0 Days', AppTheme.success),
                _statColumn('Leaves (Month)', '0 Days', AppTheme.danger),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),

      if (widget.isOwnerView) ...[
        // ── QUICK ACTIONS ──
        Text('QUICK ACTIONS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _quickAction(
                Icons.currency_rupee,
                'Pay\nSalary',
                const Color(0xFF16A34A),
                () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => PaySalaryScreen(staff: staff, selectedMonth: DateFormat('MMMM yyyy').format(DateTime.now()))));
                  if (mounted) {
                    final authVm = Provider.of<AuthViewModel>(context, listen: false);
                    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
                    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
                    if (gymId != null) {
                      await staffVm.refreshStaffPayablesForMonth(gymId, DateFormat('MMMM yyyy').format(DateTime.now()));
                    }
                    _fetchDbTabsData();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickAction(
                Icons.account_balance_wallet,
                'Advance\nSalary',
                const Color(0xFF6C3AED),
                () {
                  setState(() {
                    _currentTabIndex = 1;
                    _payrollSubTabIndex = 1;
                  });
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickAction(
                Icons.calendar_today,
                'Attendance\nDetails',
                const Color(0xFF3B82F6),
                () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Attendance is displayed right here on the right side!'), duration: Duration(seconds: 2)),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickAction(
                Icons.groups,
                'Leave\nRequests',
                const Color(0xFFEF4444),
                () {
                  setState(() {
                    _currentTabIndex = 1;
                    _payrollSubTabIndex = 2;
                  });
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // ── SHIFT TIMING SETTINGS ──
        Text('SHIFT TIMING SETTINGS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        _buildShiftSettingsCard(staff),
        const SizedBox(height: 8),
      ],

      // ── BASIC INFO ──
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('BASIC INFO', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
          if (widget.isOwnerView)
            GestureDetector(
              onTap: () => _showEditBasicInfoDialog(context, staff),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 13, color: AppTheme.primary),
                  const SizedBox(width: 4),
                  Text('Edit', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            _basicInfoRow(Icons.cake_outlined, 'Date of Birth', staff.dob.isNotEmpty ? staff.dob : '—'),
            _divider(),
            _basicInfoRow(Icons.person_outline, 'Gender', staff.gender.isNotEmpty ? staff.gender : '—'),
            _divider(),
            _basicInfoRow(Icons.phone_outlined, 'Phone', staff.phone),
            _divider(),
            _basicInfoRow(Icons.email_outlined, 'Email', staff.email),
            _divider(),
            _basicInfoRow(Icons.location_on_outlined, 'Address', staff.address.isNotEmpty ? staff.address : '—'),
            _divider(),
            _basicInfoRow(Icons.access_time_filled_outlined, 'Assigned Shift', staff.shift.isNotEmpty ? staff.shift : '—'),
          ],
        ),
      ),
      const SizedBox(height: 8),

      if (widget.isOwnerView) ...[
        // ── ACCOUNT STATUS ──
        Text('ACCOUNT STATUS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        _buildAccountStatusCard(staff),
        const SizedBox(height: 8),

        if (staff.role.toLowerCase().contains('reception')) ...[
          Text('RECEPTIONIST PERMISSIONS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          _buildReceptionistPermissionsCard(staff),
          const SizedBox(height: 8),
        ],
      ],
    ];

    final rightChildren = <Widget>[
      // ── ATTENDANCE ──
      _buildAttendanceWidget(staff),
      const SizedBox(height: 12),

      if (widget.isOwnerView) ...[
        // ── DANGER ZONE (OWNER ONLY) ──
        Text('DANGER ZONE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.danger, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFCA5A5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 18),
                  const SizedBox(width: 8),
                  Text('Delete Staff Member', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.danger)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Permanently delete this staff member. This frees up 1 staff slot.',
                style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF7F1D1D)),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () => _confirmDeleteStaff(context, staff),
                icon: const Icon(Icons.delete_forever_rounded, size: 16),
                label: const Text('Delete Staff Member', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
              ),
            ],
          ),
        ),
      ],
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 768;
          if (isDesktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: leftChildren,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: rightChildren,
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...leftChildren,
              const SizedBox(height: 12),
              ...rightChildren,
            ],
          );
        },
      ),
    );
  }

  Widget _buildShiftSettingsCard(Staff staff) {
    final isBothShift = (staff.shiftType == 'both' || staff.shift.toLowerCase().contains('both'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.access_time_filled_rounded, color: AppTheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Custom Shift Timings',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isBothShift ? 'Both Shift (Double)' : 'Single Shift',
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Shift 1 Timings
          Text('Shift 1 Timings', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickTimeOnProfile(_profileShift1Start, (val) => setState(() => _profileShift1Start = val)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceGray.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_profileShift1Start, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        const Icon(Icons.access_time_rounded, size: 14, color: AppTheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('to', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickTimeOnProfile(_profileShift1End, (val) => setState(() => _profileShift1End = val)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceGray.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_profileShift1End, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        const Icon(Icons.access_time_rounded, size: 14, color: AppTheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (isBothShift) ...[
            const SizedBox(height: 12),
            Text('Shift 2 Timings (Evening)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickTimeOnProfile(_profileShift2Start, (val) => setState(() => _profileShift2Start = val)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceGray.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_profileShift2Start, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                          const Icon(Icons.access_time_rounded, size: 14, color: AppTheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('to', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickTimeOnProfile(_profileShift2End, (val) => setState(() => _profileShift2End = val)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceGray.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_profileShift2End, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                          const Icon(Icons.access_time_rounded, size: 14, color: AppTheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: _isSavingShiftSettings
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_rounded, size: 16),
              label: Text(_isSavingShiftSettings ? 'Saving...' : 'Save Shift Settings', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
              onPressed: _isSavingShiftSettings ? null : () => _saveShiftSettings(staff),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveShiftSettings(Staff staff) async {
    setState(() => _isSavingShiftSettings = true);
    final String formattedSummary = _profileShiftType == 'both'
        ? '$_profileShift1Start - $_profileShift1End & $_profileShift2Start - $_profileShift2End'
        : '$_profileShift1Start - $_profileShift1End';

    final updatedStaff = staff.copyWith(
      shift: formattedSummary,
      shiftType: _profileShiftType,
      shift1Start: _profileShift1Start,
      shift1End: _profileShift1End,
      shift2Start: _profileShift2Start,
      shift2End: _profileShift2End,
    );

    try {
      final staffVm = Provider.of<StaffViewModel>(context, listen: false);
      await staffVm.saveStaff(updatedStaff);

      if (mounted) {
        setState(() => _isSavingShiftSettings = false);
        SuccessDialog.show(
          context,
          title: 'Shift Timings Saved!',
          message: 'Custom shift timings for ${staff.name} have been updated successfully in database.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingShiftSettings = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save shift: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickTimeOnProfile(String currentVal, Function(String) onPicked) async {
    TimeOfDay initial = const TimeOfDay(hour: 9, minute: 0);
    try {
      final parts = currentVal.split(' ');
      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      int minute = int.parse(timeParts[1]);
      if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && hour < 12) hour += 12;
      if (parts.length > 1 && parts[1].toUpperCase() == 'AM' && hour == 12) hour = 0;
      initial = TimeOfDay(hour: hour, minute: minute);
    } catch (_) {}

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );

    if (picked != null) {
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      onPicked(DateFormat('hh:mm a').format(dt));
    }
  }

  // ═══════════════════════════════════════════════════════
  // TAB 2: ATTENDANCE (Premium Calendar View)
  // ═══════════════════════════════════════════════════════
  // ═══════════════════════════════════════════════════════
  // ATTENDANCE WIDGET
  // ═══════════════════════════════════════════════════════
  Widget _buildAttendanceWidget(Staff staff) {
    final records = _attendanceRecords.where((r) {
      final d = r['date'] as DateTime;
      return d.year == _attendanceMonth.year && d.month == _attendanceMonth.month;
    }).map((r) {
      final d = r['date'] as DateTime;
      final rawStatus = (r['status'] as String?) ?? 'Absent';
      final checkIn = (r['checkIn'] as String?) ?? '';
      // Sundays without check-in are Weekly Holidays, NEVER Absent
      if (d.weekday == DateTime.sunday && (rawStatus == 'Absent' || checkIn.isEmpty)) {
        final mod = Map<String, dynamic>.from(r);
        mod['status'] = 'Holiday';
        return mod;
      }
      return r;
    }).toList();

    final present = records.where((r) => r['status'] == 'Present').length;
    final absent = records.where((r) => r['status'] == 'Absent').length;
    final holiday = records.where((r) => r['status'] == 'Holiday').length;
    final total = present + absent;
    final percentage = total > 0 ? ((present / total) * 100).round() : 0;

    // Build status map: day -> status
    final Map<int, String> statusMap = {};
    for (final r in records) {
      final d = r['date'] as DateTime;
      statusMap[d.day] = (r['status'] as String?) ?? 'Absent';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Month Selector Header ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ATTENDANCE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _attendanceMonth = DateTime(_attendanceMonth.year, _attendanceMonth.month - 1)),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: AppTheme.surfaceGray, borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.chevron_left, size: 16, color: AppTheme.textPrimary),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _attendanceMonth,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null && mounted) {
                      setState(() => _attendanceMonth = DateTime(picked.year, picked.month));
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceGray,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat('MMMM yyyy').format(_attendanceMonth),
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.textSecondary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _attendanceMonth = DateTime(_attendanceMonth.year, _attendanceMonth.month + 1)),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: AppTheme.surfaceGray, borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.chevron_right, size: 16, color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),

        // ── Summary Stats Cards ──
        Row(
          children: [
            _attendanceStatCard('$present', 'Present', AppTheme.success, Icons.check_box_outlined),
            const SizedBox(width: 6),
            _attendanceStatCard('$absent', 'Absent', AppTheme.danger, Icons.disabled_by_default_outlined),
            const SizedBox(width: 6),
            _attendanceStatCard('$holiday', 'Holiday', AppTheme.textMuted, Icons.event_busy_outlined),
            const SizedBox(width: 6),
            _attendanceStatCard('$percentage%', 'Att. %', AppTheme.primary, Icons.assessment_outlined),
          ],
        ),
        const SizedBox(height: 8),

        // ── Calendar Grid ──
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: _buildCalendarGrid(statusMap),
        ),
        const SizedBox(height: 6),

        // ── Legend ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _legendItem(AppTheme.success, Icons.check, 'Present'),
            _legendItem(AppTheme.danger, Icons.close, 'Absent'),
            _legendItem(AppTheme.textMuted, Icons.remove, 'Holiday'),
            _legendItem(Colors.orange, Icons.remove, 'Half Day'),
          ],
        ),
      ],
    );
  }

  // ── Calendar Grid Builder ──
  Widget _buildCalendarGrid(Map<int, String> statusMap) {
    final year = _attendanceMonth.year;
    final month = _attendanceMonth.month;
    final daysInMonth = DateUtils.getDaysInMonth(year, month);
    final firstDay = DateTime(year, month, 1);
    final startWeekday = firstDay.weekday % 7; // Sun=0

    // Previous month trailing days
    final prevMonth = DateTime(year, month - 1);
    final prevMonthDays = DateUtils.getDaysInMonth(prevMonth.year, prevMonth.month);

    final dayHeaders = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final totalCells = ((startWeekday + daysInMonth) / 7).ceil() * 7;

    return Column(
      children: [
        // Day headers
        Row(
          children: dayHeaders.map((d) {
            return Expanded(
              child: Center(
                child: Text(d, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),

        // Calendar cells
        ...List.generate((totalCells / 7).ceil(), (weekIndex) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: List.generate(7, (dayIndex) {
                final cellIndex = weekIndex * 7 + dayIndex;
                final dayNum = cellIndex - startWeekday + 1;

                // Previous month
                if (dayNum < 1) {
                  final prevDay = prevMonthDays + dayNum;
                  return _calendarCell(prevDay.toString(), null, isOutside: true);
                }
                // Next month
                if (dayNum > daysInMonth) {
                  final nextDay = dayNum - daysInMonth;
                  return _calendarCell(nextDay.toString(), null, isOutside: true);
                }
                // Current month
                final status = statusMap[dayNum];
                return _calendarCell(dayNum.toString(), status);
              }),
            ),
          );
        }),
      ],
    );
  }

  Widget _calendarCell(String day, String? status, {bool isOutside = false}) {
    Color bgColor = Colors.transparent;
    Color textColor = AppTheme.textPrimary;
    
    if (status != null && !isOutside) {
      if (status == 'Present' || status == 'Late' || status == 'Early Exit' || status == 'Overtime') {
        bgColor = AppTheme.successLight;
        textColor = AppTheme.success;
      } else if (status == 'Half Day' || status == 'Half Leave') {
        bgColor = const Color(0xFFFEF3C7);
        textColor = Colors.orange;
      } else if (status == 'Absent') {
        bgColor = AppTheme.dangerLight;
        textColor = AppTheme.danger;
      } else if (status == 'Leave' || status == 'On Leave') {
        bgColor = const Color(0xFFF3E8FF);
        textColor = Colors.purple;
      } else if (status == 'Holiday') {
        bgColor = AppTheme.surfaceGray;
        textColor = AppTheme.textMuted;
      }
    }

    if (isOutside) {
      textColor = AppTheme.textMuted.withValues(alpha: 0.5);
    }

    return Expanded(
      child: Container(
        height: 34,
        margin: const EdgeInsets.all(1),
        child: Center(
          child: Container(
            width: 26, height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
            ),
            child: Center(
              child: Text(
                day,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: isOutside ? FontWeight.normal : FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legendItem(Color color, IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 9, color: color),
        ),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // SECOND PAGE: SALARY, ADVANCE & LEAVE REQUESTS
  // ═══════════════════════════════════════════════════════
  Widget _buildPayrollAndRequestsTab(Staff staff) {
    return Column(
      children: [
        // Subtab pills header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _subTabPill(0, Icons.dashboard_outlined, 'All Overview'),
                const SizedBox(width: 8),
                _subTabPill(1, Icons.account_balance_wallet_outlined, 'Advance Salary (${_advanceSalaryRecords.length})'),
                const SizedBox(width: 8),
                _subTabPill(2, Icons.groups_outlined, 'Leave Requests (${_leaveRequests.where((r) => r['status'] == 'Pending').length} Pending)'),
                const SizedBox(width: 8),
                _subTabPill(3, Icons.receipt_long_outlined, 'Salary History (${_salaryHistory.length})'),
              ],
            ),
          ),
        ),
        const Divider(height: 1, color: AppTheme.border),
        // Content area
        Expanded(
          child: _payrollSubTabIndex == 0
              ? _buildPayrollOverviewTab(staff)
              : (_payrollSubTabIndex == 1
                  ? _buildAdvanceSalaryTab(staff)
                  : (_payrollSubTabIndex == 2
                      ? _buildLeaveRequestsTab(staff)
                      : _buildSalaryHistoryTab(staff))),
        ),
      ],
    );
  }

  Widget _subTabPill(int index, IconData icon, String label) {
    final isSelected = _payrollSubTabIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _payrollSubTabIndex = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primary : AppTheme.surfaceGray,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayrollOverviewTab(Staff staff) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 900;
          if (isDesktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildAdvanceSalaryContent(staff),
                      const SizedBox(height: 16),
                      _buildLeaveRequestsContent(staff),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSalaryHistoryContent(staff),
                    ],
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAdvanceSalaryContent(staff),
              const SizedBox(height: 16),
              _buildLeaveRequestsContent(staff),
              const SizedBox(height: 16),
              _buildSalaryHistoryContent(staff),
            ],
          );
        },
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // ADVANCE SALARY
  // ═══════════════════════════════════════════════════════
  Widget _buildAdvanceSalaryTab(Staff staff) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: _buildAdvanceSalaryContent(staff),
    );
  }

  Widget _buildAdvanceSalaryContent(Staff staff) {
    final filters = ['All', 'Given', 'Adjusted', 'Pending'];
    final totalAdvance = _advanceSalaryRecords.fold<double>(0, (sum, r) => sum + ((r['advance_amount'] ?? r['amount'] as num? ?? 0.0).toDouble()));

    final filtered = _advanceFilterIndex == 0
        ? _advanceSalaryRecords
        : _advanceSalaryRecords.where((r) => r['status'] == filters[_advanceFilterIndex]).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ADVANCE SALARY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
            if (widget.isOwnerView)
              GestureDetector(
                onTap: () => _showAddAdvanceDialog(staff),
                child: Row(
                  children: [
                    const Icon(Icons.add_circle_outline, size: 13, color: AppTheme.primary),
                    const SizedBox(width: 4),
                    Text('Pay Advance', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        // Total Advance Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Advance Balance', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 3),
                  Text(
                    '₹${NumberFormat('#,##,###').format(totalAdvance)}',
                    style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance_wallet, color: Colors.orange, size: 20),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Filter Tabs
        Row(
          children: List.generate(filters.length, (index) {
            final isActive = _advanceFilterIndex == index;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _advanceFilterIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isActive ? AppTheme.primary : AppTheme.border),
                  ),
                  child: Text(
                    filters[index],
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: isActive ? Colors.white : AppTheme.textSecondary),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),

        if (filtered.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Center(
              child: Text(
                'No advance salary records found.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          ...filtered.map((record) {
            final statusColor = _getAdvanceStatusColor(record['status'] as String? ?? 'Given');
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '₹${NumberFormat('#,##,###').format(record['advance_amount'] ?? record['amount'] ?? 0)}',
                        style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          (record['status'] as String?) ?? 'Given',
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text((record['givenOn'] as String?) ?? '—', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                      const SizedBox(width: 12),
                      Text((record['reason'] as String?) ?? '', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.primary)),
                    ],
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // LEAVE REQUESTS
  // ═══════════════════════════════════════════════════════
  Widget _buildLeaveRequestsTab(Staff staff) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: _buildLeaveRequestsContent(staff),
    );
  }

  Widget _buildLeaveRequestsContent(Staff staff) {
    final filters = ['Pending', 'Approved', 'Rejected', 'All'];
    final pending = _leaveRequests.where((r) => r['status'] == 'Pending').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LEAVE REQUESTS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        // Filter Tabs
        Row(
          children: List.generate(filters.length, (index) {
            final isActive = _leaveFilterIndex == index;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _leaveFilterIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isActive ? AppTheme.primary : AppTheme.border),
                  ),
                  child: Text(
                    filters[index],
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: isActive ? Colors.white : AppTheme.textSecondary),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 10),

        if (pending.isEmpty && _leaveHistory.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Center(
              child: Text(
                'No leave requests found.',
                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          )
        else ...[
          // Pending Leave Cards
          ...pending.map((leave) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${leave['from']} - ${leave['to']}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                        child: Text('${leave['days']} Days', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.orange)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Type: ${(leave['type'] as String?) ?? 'Leave'} • ${(leave['reason'] as String?) ?? ''}', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  if (widget.isOwnerView)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final staffVm = Provider.of<StaffViewModel>(context, listen: false);
                              await staffVm.updateLeaveStatus(leave['id'], 'Rejected');
                              if (mounted) {
                                SuccessDialog.show(
                                  context,
                                  title: 'Leave Rejected',
                                  message: 'Leave request has been rejected.',
                                  onDone: () => _fetchDbTabsData(),
                                );
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.danger,
                              side: const BorderSide(color: AppTheme.danger),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                            ),
                            child: Text('Reject', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final staffVm = Provider.of<StaffViewModel>(context, listen: false);
                              await staffVm.updateLeaveStatus(leave['id'], 'Approved');
                              if (mounted) {
                                SuccessDialog.show(
                                  context,
                                  title: 'Leave Approved!',
                                  message: 'Leave request has been approved successfully.',
                                  onDone: () => _fetchDbTabsData(),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.success,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                            ),
                            child: Text('Approve', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11)),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            );
          }),

          if (_leaveHistory.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Leave History', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
            const SizedBox(height: 6),
            ..._leaveHistory.map((h) {
              final statusColor = (h['status'] as String? ?? '') == 'Approved' ? AppTheme.success : AppTheme.danger;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(width: 3, height: 24, decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${h['date']} (${h['days']} Day)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                      child: Text((h['status'] as String?) ?? '', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w600, color: statusColor)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // SALARY HISTORY
  // ═══════════════════════════════════════════════════════
  Widget _buildSalaryHistoryTab(Staff staff) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: _buildSalaryHistoryContent(staff),
    );
  }

  Widget _buildSalaryHistoryContent(Staff staff) {
    final totalPaid = _salaryHistory.fold<double>(0, (sum, r) {
      final double grossSalary = (r['gross_salary'] as num?)?.toDouble() ?? 0.0;
      final double netSalary = (r['net_salary'] ?? r['amount'] as num?)?.toDouble() ?? 0.0;
      return sum + (grossSalary > 0 ? grossSalary : netSalary);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('SALARY HISTORY', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
        const SizedBox(height: 6),
        // Total Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryLight.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.primaryLight),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Salary Paid', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 3),
                  Text(
                    '₹${NumberFormat('#,##,###').format(totalPaid)}',
                    style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.receipt_long, color: AppTheme.primary, size: 20),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (_salaryHistory.isEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.receipt_long_outlined, size: 36, color: AppTheme.textMuted),
                const SizedBox(height: 8),
                Text(
                  'No Salary History',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Paid salaries and compensation breakdowns will appear here.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ] else ...[
          // Monthly Records
          ..._salaryHistory.map((record) {
            final staffVm = Provider.of<StaffViewModel>(context, listen: false);
            return SalaryHistoryItemWidget(
              record: record,
              staffVm: staffVm,
            );
          }),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════════════════════

  Widget _defaultAvatar(Staff staff) {
    return Container(
      color: AppTheme.primaryLight,
      child: Center(
        child: Text(
          staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?',
          style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
      ),
    );
  }

  Widget _iconInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppTheme.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _statColumn(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: valueColor)),
        ],
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.12)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _basicInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.5),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(height: 1, color: AppTheme.border);

  Widget _attendanceStatCard(String value, String label, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(value, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountStatusCard(Staff staff) {
    if (_loadingInvitation) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final staffVm = Provider.of<StaffViewModel>(context);
    final hasInvitation = _invitation != null;
    final isActivated = hasInvitation && (_invitation!['code_used'] == true);
    final invitationCode = _invitation?['invitation_code'];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: isActivated
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Registered',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Staff member has successfully joined the gym.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 10),
                Text(
                  'Registered Mobile Number',
                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  staff.phone,
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.link_off_rounded, size: 16),
                  label: Text('Unlink Account', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () => _confirmUnlinkStaff(staffVm, staff),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Pending Verification',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (invitationCode != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Invitation Code', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                          const SizedBox(height: 4),
                          Text(
                            invitationCode,
                            style: GoogleFonts.robotoMono(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary, letterSpacing: 1),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: invitationCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Invitation Code copied!'),
                                  backgroundColor: AppTheme.success,
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.copy_rounded, size: 16, color: AppTheme.primary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _shareInvitationCode(invitationCode, staff.phone),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.share_rounded, size: 16, color: AppTheme.primary),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Registered Mobile Number', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  Text(staff.phone, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 16),
                  Text(
                    'Waiting for the staff to complete registration.',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                  ),
                ] else ...[
                  Text(
                    'No active invitation found. Create one now to link this staff profile.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Generate Code'),
                    onPressed: () => _generateNewStaffCode(staffVm, staff),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildReceptionistPermissionsCard(Staff staff) {
    final permissionsList = [
      {'key': 'add_member', 'label': 'Add Member', 'icon': Icons.person_add_outlined},
      {'key': 'delete_member', 'label': 'Delete Member', 'icon': Icons.person_remove_outlined},
      {'key': 'scan_attendance', 'label': 'Scan Attendance', 'icon': Icons.qr_code_scanner_rounded},
      {'key': 'renew_membership', 'label': 'Renew Membership', 'icon': Icons.autorenew_rounded},
      {'key': 'add_income', 'label': 'Add Income', 'icon': Icons.add_chart_rounded},
      {'key': 'add_expense', 'label': 'Add Expense', 'icon': Icons.money_off_rounded},
      {'key': 'take_payment', 'label': 'Take Payment', 'icon': Icons.payments_outlined},
      {'key': 'send_reminder', 'label': 'Send Reminder', 'icon': Icons.notifications_active_outlined},
      {'key': 'broadcast', 'label': 'Broadcast Message', 'icon': Icons.campaign_outlined},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: permissionsList.map((perm) {
          final key = perm['key'] as String;
          final label = perm['label'] as String;
          final icon = perm['icon'] as IconData;
          final isEnabled = staff.permissions[key] == true;

          return SwitchListTile(
            secondary: Icon(icon, color: AppTheme.primary, size: 20),
            title: Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            value: isEnabled,
            activeColor: AppTheme.primary,
            onChanged: (val) async {
              final newPerms = Map<String, dynamic>.from(staff.permissions);
              newPerms[key] = val;
              
              // Save to database
              try {
                await SupabaseService.client
                    .from('staff')
                    .update({'permissions': newPerms})
                    .eq('id', staff.id);
                
                // Fetch staff list again to sync UI in owner's local list
                await Provider.of<StaffViewModel>(context, listen: false).fetchStaff();
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Permissions updated successfully for ${staff.name}')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update permissions: $e')),
                );
              }
            },
          );
        }).toList(),
      ),
    );
  }

  Color _getAdvanceStatusColor(String status) {
    switch (status) {
      case 'Pending':
        return Colors.orange;
      case 'Adjusted':
        return AppTheme.success;
      case 'Given':
        return AppTheme.info;
      default:
        return AppTheme.textMuted;
    }
  }

  void _showAddAdvanceDialog(Staff staff) {
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Pay Advance Salary', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Amount (₹)', hintText: 'e.g. 3000'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(labelText: 'Reason / Notes', hintText: 'e.g. Personal emergency'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text) ?? 0.0;
                if (amt > 0) {
                  Navigator.pop(context); // Pop dialog
                  
                  BuildContext? dialogCtx;
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) {
                      dialogCtx = ctx;
                      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                    },
                  );
                  
                  try {
                    final authVm = Provider.of<AuthViewModel>(context, listen: false);
                    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? 'default_gym';
                    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
                    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
                    
                    await staffVm.createSalaryAdvance(
                      gymId: gymId,
                      staffId: staff.id,
                      amount: amt,
                      reason: reasonCtrl.text.isNotEmpty ? reasonCtrl.text.trim() : 'Salary Advance',
                      date: todayStr,
                    );

                    if (mounted) {
                      if (dialogCtx != null && dialogCtx!.mounted) {
                        Navigator.pop(dialogCtx!); // Pop spinner using its context
                      }
                      SuccessDialog.show(
                        context,
                        title: 'Advance Paid!',
                        message: 'Advance salary of ₹${NumberFormat('#,##,###').format(amt)} paid to ${staff.name} successfully.',
                        onDone: () => _fetchDbTabsData(),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      if (dialogCtx != null && dialogCtx!.mounted) {
                        Navigator.pop(dialogCtx!); // Pop spinner
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
                      );
                    }
                  }
                }
              },
              child: Text('Pay', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteStaff(BuildContext context, Staff staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_forever_rounded, color: AppTheme.danger, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Delete Staff',
                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete ${staff.name} (${staff.role})?',
              style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will remove all staff credentials and free up 1 staff slot in your plan.',
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF991B1B), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('Delete Staff', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final staffVm = Provider.of<StaffViewModel>(context, listen: false);
      try {
        await staffVm.deleteStaff(staff.id);
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Staff member "${staff.name}" deleted successfully. 1 staff slot freed.'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete staff: $e'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }
}


class SalaryHistoryItemWidget extends StatefulWidget {
  final Map<String, dynamic> record;
  final StaffViewModel staffVm;

  const SalaryHistoryItemWidget({
    super.key,
    required this.record,
    required this.staffVm,
  });

  @override
  State<SalaryHistoryItemWidget> createState() => _SalaryHistoryItemWidgetState();
}

class _SalaryHistoryItemWidgetState extends State<SalaryHistoryItemWidget> {
  Map<String, dynamic>? _details;
  bool _isLoading = false;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetails());
  }

  Future<void> _loadDetails() async {
    if (_details != null || _isLoading) return;
    setState(() {
      _isLoading = true;
      _isError = false;
    });
    try {
      final draftId = widget.record['id']?.toString() ?? '';
      final res = await widget.staffVm.fetchPaidSalaryDraftDetails(draftId);
      if (res != null && res['success'] == true) {
        setState(() {
          _details = res;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isError = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading salary draft details: $e');
      setState(() {
        _isError = true;
        _isLoading = false;
      });
    }
  }

  Widget _buildRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label, 
            style: GoogleFonts.inter(
              fontSize: 12, 
              color: isBold ? AppTheme.textPrimary : AppTheme.textSecondary,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal
            )
          ),
          Text(
            value, 
            style: GoogleFonts.inter(
              fontSize: 12.5, 
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600, 
              color: valueColor ?? AppTheme.textPrimary
            )
          ),
        ],
      ),
    );
  }

  Widget _tableHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _tableCell(String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        value,
        style: GoogleFonts.inter(
          fontSize: 11, 
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color ?? AppTheme.textPrimary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    
    // Dynamic commissions list & sum
    final dynamic commissionsList = (_details != null && List.from(_details!['commissions'] ?? []).isNotEmpty)
        ? _details!['commissions']
        : [];
    final double liveCommSum = List.from(commissionsList).fold<double>(
      0.0,
      (sum, c) => sum + ((c['amount'] as num?)?.toDouble() ?? 0.0),
    );
    final double effectiveComm = liveCommSum > 0 
        ? liveCommSum 
        : ((_details?['commission_amount'] ?? record['commission_amount'] as num?)?.toDouble() ?? 0.0);

    // Dynamic advances list & sum
    final dynamic advancesList = (_details != null && List.from(_details!['advances'] ?? []).isNotEmpty)
        ? _details!['advances']
        : (record['advances'] as List? ?? []);
    final double liveAdvSum = List.from(advancesList).fold<double>(
      0.0,
      (sum, a) => sum + ((a['recovered_amount'] ?? a['advance_amount'] ?? a['amount'] as num?)?.toDouble() ?? 0.0),
    );
    final double effectiveAdv = liveAdvSum > 0 
        ? liveAdvSum 
        : ((_details?['advance_deduction'] ?? record['advance_deduction'] as num?)?.toDouble() ?? 0.0);

    final double baseSalary = (_details?['base_salary'] ?? record['base_salary'] as num?)?.toDouble() ?? 5000.0;
    final double additions = (_details?['other_additions'] ?? record['other_additions'] as num?)?.toDouble() ?? 0.0;
    final double deductions = (_details?['other_deductions'] ?? record['other_deductions'] as num?)?.toDouble() ?? 0.0;

    final double calculatedGross = baseSalary + effectiveComm + additions - deductions;
    final double grossSalary = (_details?['gross_salary'] as num?)?.toDouble() ?? 
        ((record['gross_salary'] as num?)?.toDouble() ?? calculatedGross);
    final double finalGross = grossSalary >= calculatedGross ? grossSalary : calculatedGross;

    final double finalNet = (_details?['net_salary'] as num?)?.toDouble() ?? 
        ((record['net_salary'] ?? record['amount'] as num?)?.toDouble() ?? (finalGross - effectiveAdv));

    final String effectivePaidOn = (_details?['paid_on'] != null && _details!['paid_on'].toString().isNotEmpty)
        ? _details!['paid_on'].toString()
        : ((record['paid_on'] ?? record['paidOn'] ?? '').toString());

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(
            record['month'] as String,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          subtitle: Text(
            effectivePaidOn.isNotEmpty ? 'Paid on $effectivePaidOn' : (record['month'] as String),
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '₹${NumberFormat('#,##,###').format(finalGross)}',
                style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down, size: 20, color: AppTheme.textSecondary),
            ],
          ),
          onExpansionChanged: (expanded) {
            if (expanded) {
              _loadDetails();
            }
          },
          children: [
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 12),
            _buildRow('Base Salary', '₹${NumberFormat('#,##,###').format(baseSalary)}'),
            if (effectiveComm > 0)
              _buildRow('Commission', '+ ₹${NumberFormat('#,##,###').format(effectiveComm)}', valueColor: Colors.green),
            if (additions > 0)
              _buildRow('Additions', '+ ₹${NumberFormat('#,##,###').format(additions)}', valueColor: Colors.green),
            if (deductions > 0)
              _buildRow('Deductions', '- ₹${NumberFormat('#,##,###').format(deductions)}', valueColor: Colors.red),
            const SizedBox(height: 4),
            _buildRow(
              'Gross Salary',
              '₹${NumberFormat('#,##,###').format(finalGross)}',
              isBold: true,
            ),
            const SizedBox(height: 4),
            if (effectiveAdv > 0)
              _buildRow('Advance Recovery', '- ₹${NumberFormat('#,##,###').format(effectiveAdv)}', valueColor: Colors.red),
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 8),
            _buildRow(
              'Net Paid Amount', 
              '₹${NumberFormat('#,##,###').format(finalNet)}', 
              isBold: true,
              valueColor: AppTheme.primary
            ),
            
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))),
            ],

            // Render Commissions breakdown table if available
            if (_details != null && List.from(_details!['commissions'] ?? []).isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Commissions Included',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
              const SizedBox(height: 8),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.2),
                  1: FlexColumnWidth(1.2),
                  2: FlexColumnWidth(1.0),
                  3: FlexColumnWidth(1.0),
                  4: FlexColumnWidth(1.0),
                },
                children: [
                  TableRow(
                    children: [
                      _tableHeader('Date'),
                      _tableHeader('Ref'),
                      _tableHeader('Recd.'),
                      _tableHeader('Rate'),
                      _tableHeader('Comm.'),
                    ],
                  ),
                  ...List.from(_details!['commissions']).map((it) {
                    final dateStr = it['created_at']?.toString() ?? '';
                    final ref = it['payment_id']?.toString().split('-').last ?? 'Payment';
                    final double recd = (it['payment_received'] as num? ?? 0.0).toDouble();
                    final double rate = (it['commission_rate'] as num? ?? 0.0).toDouble();
                    final double comm = (it['amount'] as num? ?? 0.0).toDouble();
                    return TableRow(
                      children: [
                        _tableCell(dateStr),
                        _tableCell(ref),
                        _tableCell('₹${recd.toStringAsFixed(0)}'),
                        _tableCell('${rate.toStringAsFixed(0)}%'),
                        _tableCell('₹${comm.toStringAsFixed(0)}', isBold: true, color: Colors.green),
                      ],
                    );
                  }),
                ],
              ),
            ],

            // Render Advance Recoveries breakdown table if available
            if (List.from(advancesList).isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Advance Recoveries & Dates',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
              const SizedBox(height: 8),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(1.2),
                  1: FlexColumnWidth(1.8),
                  2: FlexColumnWidth(1.0),
                  3: FlexColumnWidth(1.0),
                },
                children: [
                  TableRow(
                    children: [
                      _tableHeader('Given Date'),
                      _tableHeader('Reason'),
                      _tableHeader('Advance'),
                      _tableHeader('Recovered'),
                    ],
                  ),
                  ...List.from(advancesList).map((it) {
                    final dateStr = it['given_date'] != null 
                        ? (it['givenOn'] ?? it['given_date'].toString().split('T').first) 
                        : 'N/A';
                    final reason = it['reason']?.toString() ?? 'Personal';
                    final double advance = (it['advance_amount'] ?? it['amount'] as num? ?? 0.0).toDouble();
                    final double recovered = (it['recovered_amount'] ?? it['advance_amount'] ?? it['amount'] as num? ?? 0.0).toDouble();
                    return TableRow(
                      children: [
                        _tableCell(dateStr),
                        _tableCell(reason),
                        _tableCell('₹${advance.toStringAsFixed(0)}'),
                        _tableCell('₹${recovered.toStringAsFixed(0)}', isBold: true, color: Colors.red),
                      ],
                    );
                  }),
                ],
              ),
            ],

            // Render Adjustments breakdown table if available
            if (_details != null && List.from(_details!['adjustments'] ?? []).isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Salary Adjustments',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
              ),
              const SizedBox(height: 8),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2.0),
                  1: FlexColumnWidth(1.0),
                  2: FlexColumnWidth(1.0),
                },
                children: [
                  TableRow(
                    children: [
                      _tableHeader('Reason'),
                      _tableHeader('Type'),
                      _tableHeader('Amount'),
                    ],
                  ),
                  ...List.from(_details!['adjustments']).map((it) {
                    final reason = it['reason']?.toString() ?? 'N/A';
                    final type = it['type']?.toString() ?? 'N/A';
                    final double amount = (it['amount'] as num? ?? 0.0).toDouble();
                    final isAddition = type == 'Addition';
                    return TableRow(
                      children: [
                        _tableCell(reason),
                        _tableCell(type, color: isAddition ? Colors.green : Colors.red),
                        _tableCell(
                          '₹${amount.toStringAsFixed(0)}',
                          isBold: true,
                          color: isAddition ? Colors.green : Colors.red,
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
