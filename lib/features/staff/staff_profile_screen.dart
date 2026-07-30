import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/models/staff.dart';
import 'staff_viewmodel.dart';
import '../members/members_viewmodel.dart';
import 'pay_salary_screen.dart';
import '../authentication/auth_viewmodel.dart';
import '../../core/widgets/success_dialog.dart';
import '../../core/services/supabase_service.dart';

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

  // Account Status / Invitation tracking
  Map<String, dynamic>? _invitation;
  bool _loadingInvitation = false;

  // Dynamic tab data
  // Dynamic tab data
  List<Map<String, dynamic>> _attendanceRecords = [];
  List<Map<String, dynamic>> _advanceSalaryRecords = [];
  List<Map<String, dynamic>> _leaveRequests = [];
  List<Map<String, dynamic>> _leaveHistory = [];
  List<Map<String, dynamic>> _salaryHistory = [];
  double _pendingSalaryFromDb = 0.0;
  String _gymShiftMode = 'Single Shift';

  StaffViewModel? _staffVm;

  @override
  void initState() {
    super.initState();
    _loadInvitation();
    _fetchDbTabsData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final staffVm = Provider.of<StaffViewModel>(context);
    if (_staffVm != staffVm) {
      _staffVm?.removeListener(_onViewModelUpdated);
      _staffVm = staffVm;
      _staffVm?.addListener(_onViewModelUpdated);
    }
  }

  @override
  void dispose() {
    _staffVm?.removeListener(_onViewModelUpdated);
    super.dispose();
  }

  void _onViewModelUpdated() {
    if (mounted) {
      _fetchDbTabsData();
    }
  }

  Future<void> _fetchDbTabsData() async {
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    // Fetch data from Supabase
    final data = await staffVm.getStaffDashboardData(widget.staff.id);
    
    // Call RPC function to get dynamic calculated pending salary directly from Postgres database
    double pendingSalary = 0.0;
    try {
      final res = await SupabaseService.client.rpc('get_staff_pending_salary', params: {
        'p_staff_id': widget.staff.id,
      });
      if (res != null) {
        pendingSalary = (res as num).toDouble();
      }
    } catch (e) {
      print('Error fetching pending salary from DB: $e');
      pendingSalary = widget.staff.salary;
    }

    // Fetch gym shift settings mode
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
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

    if (mounted) {
      setState(() {
        _attendanceRecords = data['attendance'] ?? [];
        _advanceSalaryRecords = data['advance'] ?? [];
        _leaveRequests = data['leaveRequests'] ?? [];
        _leaveHistory = data['leaveHistory'] ?? [];
        _salaryHistory = data['salaryHistory'] ?? [];
        _pendingSalaryFromDb = pendingSalary;
      });
    }
  }

  Future<void> _loadInvitation() async {
    setState(() => _loadingInvitation = true);
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    final invite = await staffVm.getLatestInvitation(widget.staff.id);
    if (mounted) {
      setState(() {
        _invitation = invite;
        _loadingInvitation = false;
      });
    }
  }

  void _shareInvitationCode(String code, String phone) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Share Invitation', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.green),
                title: Text('Share via WhatsApp', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(context);
                  final message = '''🏋️ Staff Invitation

Hello,

You have been invited to join our gym as staff.

Invitation Code:
$code

Registered Mobile:
$phone

Download GymOS and enter this invitation code during registration.

Thank you.''';
                  
                  final cleanedPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
                  final whatsappUrl = Uri.parse("https://wa.me/$cleanedPhone?text=${Uri.encodeComponent(message)}");
                  
                  if (await canLaunchUrl(whatsappUrl)) {
                    await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open WhatsApp. Please make sure it is installed.'), backgroundColor: AppTheme.danger),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined, color: AppTheme.primary),
                title: Text('Copy Code Only', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invitation Code copied!'), backgroundColor: AppTheme.success),
                  );
                },
              ),
            ],
          ),
        );
      },
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
            return Padding(
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
                      decoration: const InputDecoration(labelText: 'Gym Shift'),
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
                            SuccessDialog.show(
                              context,
                              title: 'Staff Updated',
                              message: '${updatedStaff.name}\'s basic information has been updated successfully.',
                              onDone: () {
                                _fetchDbTabsData();
                                setState(() {});
                              },
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            Navigator.pop(context); // Pop loading spinner
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to update staff: $e'), backgroundColor: AppTheme.danger),
                            );
                          }
                        }
                      },
                      child: Text('Save Changes', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ],
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _currentTabIndex == 1 ? 'Attendance' : 'Staff Profile',
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        centerTitle: true,
        actions: widget.isOwnerView
            ? [
                IconButton(
                  icon: Icon(
                    _currentTabIndex == 1 ? Icons.calendar_month_outlined : Icons.more_vert,
                    color: AppTheme.textPrimary,
                  ),
                  onPressed: () {},
                ),
              ]
            : null,
      ),
      body: _buildCurrentTab(staff),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildCurrentTab(Staff staff) {
    if (widget.isOwnerView) {
      switch (_currentTabIndex) {
        case 0:
          return _buildInfoTab(staff);
        case 1:
          return _buildAttendanceTab(staff);
        case 2:
          return _buildAdvanceSalaryTab(staff);
        case 3:
          return _buildLeaveRequestsTab(staff);
        case 4:
          return _buildSalaryHistoryTab(staff);
        default:
          return _buildInfoTab(staff);
      }
    } else {
      // Staff view: only Info and Attendance
      switch (_currentTabIndex) {
        case 0:
          return _buildInfoTab(staff);
        case 1:
          return _buildAttendanceTab(staff);
        default:
          return _buildInfoTab(staff);
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  // BOTTOM NAVIGATION BAR
  // ═══════════════════════════════════════════════════════
  Widget _buildBottomNav() {
    final List<Map<String, dynamic>> items = widget.isOwnerView
        ? [
            {'icon': Icons.person_outline, 'activeIcon': Icons.person, 'label': 'Info'},
            {'icon': Icons.calendar_today_outlined, 'activeIcon': Icons.calendar_today, 'label': 'Attendance'},
            {'icon': Icons.account_balance_wallet_outlined, 'activeIcon': Icons.account_balance_wallet, 'label': 'Advance'},
            {'icon': Icons.description_outlined, 'activeIcon': Icons.description, 'label': 'Leave Requests'},
            {'icon': Icons.receipt_long_outlined, 'activeIcon': Icons.receipt_long, 'label': 'Salary History'},
          ]
        : [
            {'icon': Icons.person_outline, 'activeIcon': Icons.person, 'label': 'Info'},
            {'icon': Icons.calendar_today_outlined, 'activeIcon': Icons.calendar_today, 'label': 'Attendance'},
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
                  width: 64,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive ? items[index]['activeIcon'] as IconData : items[index]['icon'] as IconData,
                        size: 22,
                        color: isActive ? AppTheme.primary : AppTheme.textMuted,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        items[index]['label'] as String,
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Profile Header Card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Photo
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF1F2937), width: 2),
                  ),
                  child: ClipOval(
                    child: staff.avatar.startsWith('http')
                        ? Image.network(staff.avatar, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultAvatar(staff))
                        : _defaultAvatar(staff),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(staff.name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryLight,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(staff.role, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceGray,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'STA-${staff.id.substring(0, 6).toUpperCase()}',
                              style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, color: AppTheme.textSecondary),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _iconInfoRow(Icons.phone_outlined, staff.phone),
                      const SizedBox(height: 4),
                      _iconInfoRow(Icons.email_outlined, staff.email),
                      const SizedBox(height: 4),
                      _iconInfoRow(Icons.calendar_today_outlined, 'Joined on ${staff.joinDate}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ── Stats Card ──
          Container(
            padding: const EdgeInsets.all(16),
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
                        Text(staff.name, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        Text(staff.role, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: staff.status == 'Active' ? AppTheme.successLight : AppTheme.dangerLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        staff.status,
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: staff.status == 'Active' ? AppTheme.success : AppTheme.danger),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: AppTheme.border),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _statColumn('Start Date', staff.joinDate, AppTheme.textPrimary),
                    if (widget.isOwnerView) ...[
                      _statColumn('Salary Type', staff.salaryType.isNotEmpty ? staff.salaryType : 'Fixed', AppTheme.textPrimary),
                      _statColumn('Pending Salary', '₹${NumberFormat('#,##,###').format(_pendingSalaryFromDb)}', AppTheme.primary),
                    ] else ...[
                      _statColumn('Shift', staff.shift.isNotEmpty ? staff.shift : '—', AppTheme.textPrimary),
                      _statColumn('Department', staff.department.isNotEmpty ? staff.department : '—', AppTheme.textPrimary),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
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

          if (widget.isOwnerView) ...[
            const SizedBox(height: 20),
            // ── QUICK ACTIONS ──
            Text('QUICK ACTIONS', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _quickAction(
                    Icons.currency_rupee,
                    'Pay\nSalary',
                    const Color(0xFF16A34A),
                    () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => PaySalaryScreen(staff: staff, selectedMonth: DateFormat('MMMM yyyy').format(DateTime.now()))));
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _quickAction(
                    Icons.account_balance_wallet,
                    'Advance\nSalary',
                    const Color(0xFF6C3AED),
                    () {
                      setState(() => _currentTabIndex = 2);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _quickAction(
                    Icons.calendar_today,
                    'Attendance\nDetails',
                    const Color(0xFF3B82F6),
                    () {
                      setState(() => _currentTabIndex = 1);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _quickAction(
                    Icons.groups,
                    'Leave\nRequests',
                    const Color(0xFFEF4444),
                    () {
                      setState(() => _currentTabIndex = 3);
                    },
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),

          // ── BASIC INFO ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('BASIC INFO', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
              if (widget.isOwnerView)
                GestureDetector(
                  onTap: () => _showEditBasicInfoDialog(context, staff),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      const Icon(Icons.edit_outlined, size: 14, color: AppTheme.primary),
                      const SizedBox(width: 4),
                      Text('Edit', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
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
          if (widget.isOwnerView) ...[
            const SizedBox(height: 20),
            // ── ACCOUNT STATUS ──
            Text('ACCOUNT STATUS', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
            const SizedBox(height: 12),
            _buildAccountStatusCard(staff),
            if (staff.role.toLowerCase().contains('reception')) ...[
              const SizedBox(height: 20),
              Text('RECEPTIONIST PERMISSIONS', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              _buildReceptionistPermissionsCard(staff),
            ],
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 2: ATTENDANCE (Premium Calendar View)
  // ═══════════════════════════════════════════════════════
  Widget _buildAttendanceTab(Staff staff) {
    final records = _attendanceRecords;
    final present = records.where((r) => r['status'] == 'Present').length;
    final absent = records.where((r) => r['status'] == 'Absent').length;
    final holiday = records.where((r) => r['status'] == 'Holiday').length;
    final total = present + absent;
    final percentage = total > 0 ? ((present / total) * 100).round() : 0;

    // Build status map: day -> status
    final Map<int, String> statusMap = {};
    for (final r in records) {
      final d = r['date'] as DateTime;
      statusMap[d.day] = r['status'] as String;
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          // ── Month Selector ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _attendanceMonth = DateTime(_attendanceMonth.year, _attendanceMonth.month - 1)),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.chevron_left, size: 22, color: AppTheme.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('MMMM yyyy').format(_attendanceMonth),
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.textSecondary),
                  ],
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _attendanceMonth = DateTime(_attendanceMonth.year, _attendanceMonth.month + 1)),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.chevron_right, size: 22, color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
          ),

          // ── Summary Stats Cards ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _attendanceStatCard('$present', 'Present', AppTheme.success, Icons.check_box_outlined),
                const SizedBox(width: 8),
                _attendanceStatCard('$absent', 'Absent', AppTheme.danger, Icons.disabled_by_default_outlined),
                const SizedBox(width: 8),
                _attendanceStatCard('$holiday', 'Holiday', AppTheme.textMuted, Icons.event_busy_outlined),
                const SizedBox(width: 8),
                _attendanceStatCard('$percentage%', 'Attendance', AppTheme.primary, Icons.assessment_outlined),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // ── Calendar Grid ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: _buildCalendarGrid(statusMap),
            ),
          ),
          const SizedBox(height: 12),

          // ── Legend ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _legendItem(AppTheme.success, Icons.check, 'Present'),
                _legendItem(AppTheme.danger, Icons.close, 'Absent'),
                _legendItem(AppTheme.textMuted, Icons.remove, 'Holiday'),
                _legendItem(Colors.orange, Icons.remove, 'Half Day'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Attendance Details List ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Attendance Details', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                Text(
                  '$present Present, $absent Absent, $holiday Holiday',
                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...records.map((record) {
            final date = record['date'] as DateTime;
            final status = record['status'] as String;
            final checkIn = record['checkIn'] as String;
            final checkOut = record['checkOut'] as String;
            final statusColor = _getStatusColor(status);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.border, width: 0.5)),
                ),
                child: Row(
                  children: [
                    // Date block
                    SizedBox(
                      width: 36,
                      child: Column(
                        children: [
                          Text('${date.day.toString().padLeft(2, '0')}', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                          Text(DateFormat('EEE').format(date), style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Status + details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                status == 'Present' ? Icons.check_circle : status == 'Absent' ? Icons.cancel : Icons.remove_circle_outline,
                                size: 14,
                                color: statusColor,
                              ),
                              const SizedBox(width: 6),
                              Text(status, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: statusColor)),
                            ],
                          ),
                           if (checkIn.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Check In: $checkIn  •  Check Out: ${checkOut.isEmpty ? "Pending" : checkOut}',
                                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Worked: ${record['working_minutes'] ?? 0}m  •  Late: ${record['late_minutes'] ?? 0}m  •  Early Exit: ${record['early_exit_minutes'] ?? 0}m  •  Overtime: ${record['overtime_minutes'] ?? 0}m',
                                    style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                                  ),
                                ],
                              ),
                            )
                          else if (status == 'Holiday')
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('Weekly Holiday', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                            )
                          else if (status == 'Absent')
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('No Check In', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: AppTheme.textMuted),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 20),
        ],
      ),
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
                child: Text(d, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),

        // Calendar cells
        ...List.generate((totalCells / 7).ceil(), (weekIndex) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
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
        height: 48,
        margin: const EdgeInsets.all(1),
        child: Center(
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
            ),
            child: Center(
              child: Text(
                day,
                style: GoogleFonts.inter(
                  fontSize: 13,
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Present':
        return AppTheme.success;
      case 'Absent':
        return AppTheme.danger;
      case 'Half Day':
        return Colors.orange;
      case 'Late':
        return Colors.orange;
      case 'Early Exit':
        return Colors.deepOrange;
      case 'Overtime':
        return Colors.blue;
      case 'Leave':
      case 'On Leave':
        return Colors.purple;
      case 'Half Leave':
        return Colors.orange;
      case 'Incomplete Attendance':
        return Colors.redAccent;
      default:
        return AppTheme.textMuted;
    }
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
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 3: ADVANCE SALARY
  // ═══════════════════════════════════════════════════════
  Widget _buildAdvanceSalaryTab(Staff staff) {
    final filters = ['All', 'Given', 'Adjusted', 'Pending'];
    final totalAdvance = _advanceSalaryRecords.fold<double>(0, (sum, r) => sum + ((r['advance_amount'] ?? r['amount'] as num? ?? 0.0).toDouble()));

    final filtered = _advanceFilterIndex == 0
        ? _advanceSalaryRecords
        : _advanceSalaryRecords.where((r) => r['status'] == filters[_advanceFilterIndex]).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total Advance Card
          Container(
            padding: const EdgeInsets.all(16),
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
                    Text('Total Advance', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      '₹${NumberFormat('#,##,###').format(totalAdvance)}',
                      style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ],
                ),
                if (widget.isOwnerView)
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.account_balance_wallet, color: Colors.orange, size: 24),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => _showAddAdvanceDialog(staff),
                        child: Text(
                          '+ Pay Advance',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Filter Tabs
          Row(
            children: List.generate(filters.length, (index) {
              final isActive = _advanceFilterIndex == index;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _advanceFilterIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isActive ? AppTheme.primary : AppTheme.border),
                    ),
                    child: Text(
                      filters[index],
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: isActive ? Colors.white : AppTheme.textSecondary),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Records
          ...filtered.map((record) {
            final statusColor = _getAdvanceStatusColor(record['status'] as String);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
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
                      Text(
                        '₹${NumberFormat('#,##,###').format(record['advance_amount'] ?? record['amount'] ?? 0)}',
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          record['status'] as String,
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Given On', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                      const SizedBox(width: 8),
                      Text('Reason', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(record['givenOn'] as String, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                      const SizedBox(width: 16),
                      Text(record['reason'] as String, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.primary)),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 4: LEAVE REQUESTS
  // ═══════════════════════════════════════════════════════
  Widget _buildLeaveRequestsTab(Staff staff) {
    final filters = ['Pending', 'Approved', 'Rejected', 'All'];
    final pending = _leaveRequests.where((r) => r['status'] == 'Pending').toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Tabs
          Row(
            children: List.generate(filters.length, (index) {
              final isActive = _leaveFilterIndex == index;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _leaveFilterIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? AppTheme.primary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: isActive ? AppTheme.primary : AppTheme.border),
                    ),
                    child: Text(
                      filters[index],
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: isActive ? Colors.white : AppTheme.textSecondary),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Pending Leave Cards
          ...pending.map((leave) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
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
                      Text('${leave['from']} - ${leave['to']}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                        child: Text('${leave['days']} Days', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Leave Type', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                  Text(leave['type'] as String, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.primary)),
                  const SizedBox(height: 6),
                  Text('Reason', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                  Text(leave['reason'] as String, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Applied On', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                      const SizedBox(width: 8),
                      Text(leave['appliedOn'] as String, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textPrimary)),
                      const Spacer(),
                      Text('Status', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                        child: Text('Pending', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange)),
                      ),
                    ],
                  ),
                  if (widget.isOwnerView) ...[
                    const SizedBox(height: 14),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              minimumSize: const Size(0, 40),
                            ),
                            child: Text('Reject', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
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
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              minimumSize: const Size(0, 40),
                            ),
                            child: Text('Approve', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }),
          const SizedBox(height: 20),

          // History Section
          Text('History', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
          const SizedBox(height: 12),
          ..._leaveHistory.map((h) {
            final statusColor = (h['status'] as String) == 'Approved' ? AppTheme.success : AppTheme.danger;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(width: 3, height: 32, decoration: BoxDecoration(color: statusColor, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h['date'] as String, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                        Text('${h['days']} Day', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(h['status'] as String, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                        const SizedBox(width: 4),
                        Icon(Icons.check, size: 12, color: statusColor),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // TAB 5: SALARY HISTORY
  // ═══════════════════════════════════════════════════════
  Widget _buildSalaryHistoryTab(Staff staff) {
    final totalPaid = _salaryHistory.fold<double>(0, (sum, r) {
      final double grossSalary = (r['gross_salary'] as num?)?.toDouble() ?? 0.0;
      return sum + grossSalary;
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.primaryLight.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryLight),
            ),
            child: Column(
              children: [
                Text('Total Salary Paid', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 6),
                Text(
                  '₹${NumberFormat('#,##,###').format(totalPaid)}',
                  style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Monthly Records
          ..._salaryHistory.map((record) {
            final staffVm = Provider.of<StaffViewModel>(context, listen: false);
            return SalaryHistoryItemWidget(
              record: record,
              staffVm: staffVm,
            );
          }),
        ],
      ),
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.12)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 8),
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
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.textMuted),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
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
        padding: const EdgeInsets.all(16),
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
      padding: const EdgeInsets.all(16),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Registered',
                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Staff member has successfully joined the gym.',
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 16),
                Text(
                  'Registered Mobile Number',
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  staff.phone,
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.link_off_rounded, size: 16),
                  label: Text('Unlink Account', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
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
            'Paid on ${record['paidOn']}',
            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '₹${NumberFormat('#,##,###').format(record['gross_salary'] ?? 0.0)}',
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
            _buildRow('Base Salary', '₹${NumberFormat('#,##,###').format(record['base_salary'] ?? 0.0)}'),
            if ((record['commission_amount'] ?? 0.0) > 0)
              _buildRow('Commission', '+ ₹${NumberFormat('#,##,###').format(record['commission_amount'])}', valueColor: Colors.green),
            if ((record['other_additions'] ?? 0.0) > 0)
              _buildRow('Additions', '+ ₹${NumberFormat('#,##,###').format(record['other_additions'])}', valueColor: Colors.green),
            if ((record['other_deductions'] ?? 0.0) > 0)
              _buildRow('Deductions', '- ₹${NumberFormat('#,##,###').format(record['other_deductions'])}', valueColor: Colors.red),
            const SizedBox(height: 4),
            _buildRow(
              'Gross Salary',
              '₹${NumberFormat('#,##,###').format(record['gross_salary'] ?? 0.0)}',
              isBold: true,
            ),
            const SizedBox(height: 4),
            if ((record['advance_deduction'] ?? 0.0) > 0)
              _buildRow('Advance Recovery', '- ₹${NumberFormat('#,##,###').format(record['advance_deduction'])}', valueColor: Colors.red),
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 8),
            _buildRow(
              'Net Paid Amount', 
              '₹${NumberFormat('#,##,###').format(record['amount'])}', 
              isBold: true,
              valueColor: AppTheme.primary
            ),
            
            if (_isLoading) ...[
              const SizedBox(height: 16),
              const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary))),
            ] else if (_isError) ...[
              const SizedBox(height: 12),
              Center(child: Text('Failed to load breakdown details.', style: GoogleFonts.inter(fontSize: 11, color: Colors.red))),
            ] else if (_details != null) ...[
              // Render Commissions breakdown table if available
              if (List.from(_details!['commissions'] ?? []).isNotEmpty) ...[
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
              if (List.from(_details!['advances'] ?? []).isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Advance Recoveries',
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
                    ...List.from(_details!['advances']).map((it) {
                      final dateStr = it['given_date']?.toString() ?? '';
                      final reason = it['reason']?.toString() ?? 'N/A';
                      final double advance = (it['advance_amount'] as num? ?? 0.0).toDouble();
                      final double recovered = (it['recovered_amount'] as num? ?? 0.0).toDouble();
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
              if (List.from(_details!['adjustments'] ?? []).isNotEmpty) ...[
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
          ],
        ),
      ),
    );
  }
}
