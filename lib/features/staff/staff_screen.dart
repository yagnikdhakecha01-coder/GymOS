import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/status_badge.dart';
import '../../core/widgets/stat_card.dart';
import 'staff_viewmodel.dart';
import '../../core/models/staff.dart';
import '../../core/navigation/app_router.dart';
import 'staff_profile_screen.dart';
import 'add_staff_screen.dart';
import '../../core/widgets/success_dialog.dart';
import '../../core/services/supabase_service.dart';
import '../authentication/auth_viewmodel.dart';
import '../dashboard/widgets/owner_staff_card.dart';
import 'package:intl/intl.dart';
import '../../core/theme/responsive.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  late ScrollController _scrollController;
  double _scrollOffset = 0.0;
  List<Map<String, dynamic>> _staffCardsRpc = [];
  bool _cardsLoading = true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStaffPayrollData());
  }

  Future<void> _loadStaffPayrollData() async {
    if (!mounted) return;
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
    final month = DateFormat('MMMM yyyy').format(DateTime.now());

    if (gymId != null) {
      await staffVm.refreshStaffPayablesForMonth(gymId, month);
    }

    if (SupabaseService.isInitialized && gymId != null) {
      try {
        final response = await SupabaseService.client.rpc('get_owner_staff_cards_v1', params: {
          'p_gym_id': gymId,
          'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        });
        if (mounted && response is List) {
          setState(() {
            _staffCardsRpc = List<Map<String, dynamic>>.from(response);
            _cardsLoading = false;
          });
          return;
        }
      } catch (e) {
        print('get_owner_staff_cards_v1 error: $e');
      }
    }

    if (mounted) setState(() => _cardsLoading = false);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      setState(() {
        _scrollOffset = _scrollController.offset;
      });
    }
  }

  void _showAddStaffSheet(BuildContext context) {
    Navigator.push(
      context,
      AppRouter.slideRoute(const AddStaffScreen(), slideUp: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staffVm = Provider.of<StaffViewModel>(context);
    final allStaff = staffVm.filteredStaff;
    final totalStaff = staffVm.allStaff.length;
    final presentToday = staffVm.allStaff.where((s) => s.status == 'Active').length;
    final onLeave = staffVm.allStaff.where((s) => s.status == 'On Leave').length;

    // Calculate dynamic cards opacity based on scroll offset (fades out at 150px)
    final double cardsOpacity = (1.0 - (_scrollOffset / 150.0)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // 1. Collapsing Title & Stats Grid (Scrolls away & fades out)
            SliverToBoxAdapter(
              child: Opacity(
                opacity: cardsOpacity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Section
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppTheme.pagePadding, 16, AppTheme.pagePadding, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Staff',
                                  style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                ),
                                Text(
                                  'Manage your gym staff and teams',
                                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          CustomButton(
                            text: 'Add Staff',
                            icon: Icons.add,
                            isSmall: true,
                            onPressed: () => _showAddStaffSheet(context),
                          ),
                        ],
                      ),
                    ),

                    // Stat Cards Grid
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
                      child: ResponsiveGrid(
                        crossAxisCountMobile: 2,
                        crossAxisCountTablet: 4,
                        spacing: 10,
                        runSpacing: 10,
                        childAspectRatio: context.selectValue(mobile: 1.55, smallMobile: 1.25, tablet: 1.7),
                        children: [
                          StatCard(
                            icon: Icons.badge_outlined,
                            iconColor: AppTheme.primary,
                            value: '$totalStaff',
                            label: 'Total Staff',
                          ),
                          StatCard(
                            icon: Icons.check_circle_outline,
                            iconColor: AppTheme.success,
                            value: '$presentToday',
                            label: 'Present Today',
                          ),
                          FutureBuilder<dynamic>(
                            future: Future.value(staffVm.totalPendingPayableForMonth),
                            builder: (context, snapshot) {
                              final dueVal = staffVm.totalPendingPayableForMonth;
                              return StatCard(
                                icon: Icons.payments_outlined,
                                iconColor: AppTheme.danger,
                                value: '₹${NumberFormat('#,##,###').format(dueVal)}',
                                label: 'Salary Due',
                              );
                            },
                          ),
                          StatCard(
                            icon: Icons.beach_access_outlined,
                            iconColor: AppTheme.warning,
                            value: '$onLeave',
                            label: 'On Leave',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // 2. Pinned Search Bar & Section Title (Locks at the top)
            SliverPersistentHeader(
              pinned: true,
              delegate: _StaffHeaderDelegate(
                height: 94.0,
                child: Container(
                  color: AppTheme.background,
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search Bar
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 44,
                                child: TextField(
                                  onChanged: staffVm.setSearchQuery,
                                  decoration: InputDecoration(
                                    hintText: 'Search staff...',
                                    hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                                    prefixIcon: const Icon(Icons.search, size: 20),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              height: 44,
                              width: 44,
                              decoration: BoxDecoration(
                                border: Border.all(color: AppTheme.border),
                                borderRadius: BorderRadius.circular(10),
                                color: Colors.white,
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.filter_list_rounded, color: AppTheme.textSecondary, size: 20),
                                onPressed: () {},
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Section Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding + 4),
                        child: Text(
                          'All Staff (${allStaff.length})',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Spacing between title and first card
            const SliverToBoxAdapter(
              child: SizedBox(height: 8),
            ),

            // 4. Staff List
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final staff = allStaff[index];
                    Map<String, dynamic>? rpcMatch;
                    for (final row in _staffCardsRpc) {
                      if (row['staff_id']?.toString() == staff.id.toString()) {
                        rpcMatch = Map<String, dynamic>.from(row);
                        break;
                      }
                    }

                    final payable = staffVm.getStaffCachedPayable(staff.id);
                    final isPaid = payable <= 0 && (rpcMatch?['is_salary_paid'] == true);

                    final staffData = rpcMatch ?? {
                      'staff_id': staff.id,
                      'name': staff.name,
                      'role': staff.role,
                      'avatar': staff.avatar,
                      'status': staff.status,
                      'present_days': 0,
                      'leave_days': 0,
                      'early_exit_count': 0,
                      'last_check_in': 'N/A',
                      'is_checked_in': staff.status == 'Active',
                      'current_date_str': DateFormat('dd MMM yyyy').format(DateTime.now()),
                    };

                    staffData['salary_pending'] = payable;
                    staffData['is_salary_paid'] = isPaid;
                    if (isPaid && rpcMatch != null) {
                      staffData['paid_amount'] = rpcMatch['paid_amount'] ?? payable;
                    }

                    return OwnerStaffCard(
                      staffData: staffData,
                      onTap: () async {
                        await Navigator.push(context, AppRouter.slideRoute(StaffProfileScreen(staff: staff)));
                        if (context.mounted) _loadStaffPayrollData();
                      },
                    );
                  },
                  childCount: allStaff.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _StaffHeaderDelegate({required this.child, this.height = 92.0});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StaffHeaderDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}

class AddStaffSheet extends StatefulWidget {
  const AddStaffSheet({super.key});

  @override
  State<AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends State<AddStaffSheet> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _salaryController = TextEditingController();
  String _selectedRole = 'Trainer';
  String _gymShiftMode = 'Single Shift';

  @override
  void initState() {
    super.initState();
    _loadGymShiftMode();
  }

  Future<void> _loadGymShiftMode() async {
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId != null) {
        final settingsRes = await SupabaseService.client
            .from('gym_shift_settings')
            .select('mode')
            .eq('gym_id', gymId)
            .maybeSingle();
            
        if (settingsRes != null && mounted) {
          setState(() {
            _gymShiftMode = settingsRes['mode'] ?? 'Single Shift';
          });
        }
      }
    } catch (e) {
      print('Error loading gym shift mode: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _salaryController.dispose();
    super.dispose();
  }

  String _generateUUIDv4() {
    final random = Random.secure();
    const chars = '0123456789abcdef';
    String hexStr(int length) {
      return List.generate(length, (index) => chars[random.nextInt(16)]).join();
    }
    final y = ['8', '9', 'a', 'b'][random.nextInt(4)];
    return '${hexStr(8)}-${hexStr(4)}-4${hexStr(3)}-$y${hexStr(3)}-${hexStr(12)}';
  }

  @override
  Widget build(BuildContext context) {
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Add Staff Member', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Photo picker mock
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppTheme.primaryLight,
                    child: const Icon(Icons.photo_camera_outlined, color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(height: 4),
                  const Text('Upload Photo', style: TextStyle(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Text('Full Name', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _nameController, decoration: const InputDecoration(hintText: 'e.g. Rahul Sharma')),
            const SizedBox(height: 12),

            Text('Email Address', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _emailController, decoration: const InputDecoration(hintText: 'e.g. rahul@fitzone.com')),
            const SizedBox(height: 12),

            Text('Phone Number', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextFormField(controller: _phoneController, decoration: const InputDecoration(hintText: 'e.g. 98765 43210')),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Role', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _selectedRole,
                        items: const [
                          DropdownMenuItem(value: 'Trainer', child: Text('Trainer')),
                          DropdownMenuItem(value: 'Receptionist', child: Text('Receptionist')),
                          DropdownMenuItem(value: 'Dietitian', child: Text('Dietitian')),
                          DropdownMenuItem(value: 'Accountant', child: Text('Accountant')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedRole = val);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Salary (₹)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextFormField(controller: _salaryController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'e.g. 25000')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            CustomButton(
              text: 'Save Staff',
              onPressed: () async {
                if (_nameController.text.isEmpty || _salaryController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter name and salary'), backgroundColor: AppTheme.danger),
                  );
                  return;
                }
                
                final id = _generateUUIDv4();
                final newStaff = Staff(
                  id: id,
                  name: _nameController.text.trim(),
                  email: _emailController.text.trim(),
                  phone: _phoneController.text.trim(),
                  role: _selectedRole,
                  department: _selectedRole == 'Trainer' ? 'Training' : 'Administration',
                  status: 'Active',
                  avatar: 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=200',
                  joinDate: '16 Jul 2026',
                  shift: _gymShiftMode == 'Single Shift' ? 'Single Shift' : 'Morning Shift',
                  experience: 'N/A',
                  rating: 4.5,
                  sessionsCount: 0,
                  membersTrained: 0,
                  salary: double.tryParse(_salaryController.text) ?? 20000.0,
                  salaryDue: 0.0,
                );
                                // Show loading spinner
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                );

                try {
                  await staffVm.addStaffMember(newStaff);

                  // Generate invitation code in the background
                  try {
                    await staffVm.generateInvitation(
                      recordId: id,
                      name: newStaff.name,
                      phone: newStaff.phone,
                    );
                  } catch (e) {
                    print('Background staff invitation generation error: $e');
                  }

                  if (mounted) {
                    Navigator.pop(context); // Pop loading spinner
                    SuccessDialog.show(
                      context,
                      title: 'Staff Added!',
                      message: '${newStaff.name} has been added successfully.',
                      onDone: () {
                        Navigator.pop(context); // Pop staff wizard sheet
                      },
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context); // Pop loading spinner
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Database Error: ${e.toString().replaceAll('Exception:', '').trim()}'),
                        backgroundColor: AppTheme.danger,
                        duration: const Duration(seconds: 8),
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
