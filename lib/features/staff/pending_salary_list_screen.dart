import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/models/staff.dart';
import 'staff_viewmodel.dart';
import 'pay_salary_screen.dart';
import '../authentication/auth_viewmodel.dart';

class PendingSalaryListScreen extends StatefulWidget {
  const PendingSalaryListScreen({super.key});

  @override
  State<PendingSalaryListScreen> createState() => _PendingSalaryListScreenState();
}

class _PendingSalaryListScreenState extends State<PendingSalaryListScreen> {
  String _selectedMonth = '';
  final List<String> _months = [];

  @override
  void initState() {
    super.initState();
    // Generate past 3 months and next 3 months for selection
    final now = DateTime.now();
    for (int i = -3; i <= 3; i++) {
      final date = DateTime(now.year, now.month + i, 1);
      _months.add(DateFormat('MMMM yyyy').format(date));
    }
    _selectedMonth = DateFormat('MMMM yyyy').format(now);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId != null) {
        Provider.of<StaffViewModel>(context, listen: false).fetchGymSalaryAdvances(gymId);
      }
      Provider.of<StaffViewModel>(context, listen: false)
          .fetchPaidSalariesForMonth(_selectedMonth);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Text(
          'Pending Salaries',
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: Consumer<StaffViewModel>(
        builder: (context, staffVm, _) {
          final pendingStaff = staffVm.getPendingSalaryStaff(_selectedMonth);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Month Selector Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.5), width: 1),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Salary Month',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedMonth,
                        icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedMonth = newValue;
                            });
                            final authVm = Provider.of<AuthViewModel>(context, listen: false);
                            final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
                            if (gymId != null) {
                              Provider.of<StaffViewModel>(context, listen: false).fetchGymSalaryAdvances(gymId);
                            }
                            Provider.of<StaffViewModel>(context, listen: false)
                                .fetchPaidSalariesForMonth(newValue);
                          }
                        },
                        items: _months.map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(
                              value,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),

              // Pending List
              Expanded(
                child: pendingStaff.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_circle_outline_rounded,
                                size: 48,
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'All Salaries Paid!',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'No pending salaries for $_selectedMonth',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: pendingStaff.length,
                        itemBuilder: (context, index) {
                          final staff = pendingStaff[index];
                          
                          // Retrieve dynamically calculated totals from database drafts if available
                          final drafts = staffVm.getDraftsForMonth(_selectedMonth);
                          Map<String, dynamic>? draft;
                          for (var d in drafts) {
                            if (d['staff_id'].toString() == staff.id.toString()) {
                              draft = d;
                              break;
                            }
                          }
                          final double totalPayable = draft != null
                              ? (draft['net_salary'] as num).toDouble()
                              : () {
                                  final advances = staffVm.getStaffAdvancesForMonth(staff.id, _selectedMonth);
                                  final double totalAdvance = advances.fold<double>(0.0, (sum, adv) {
                                    final status = adv['status'] as String?;
                                    if (status == 'Approved' || status == 'Given' || status == 'Pending') {
                                      return sum + ((adv['remaining_amount'] ?? adv['advance_amount'] ?? adv['amount'] ?? 0.0) as num).toDouble();
                                    }
                                    return sum;
                                  });
                                  return (staff.salary - totalAdvance).clamp(0.0, double.infinity);
                                }();

                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PaySalaryScreen(
                                    staff: staff,
                                    selectedMonth: _selectedMonth,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppTheme.border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.02),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Staff Photo
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppTheme.border, width: 1.5),
                                    ),
                                    child: ClipOval(
                                      child: staff.avatar.startsWith('http')
                                          ? Image.network(
                                              staff.avatar,
                                              fit: BoxFit.cover,
                                            )
                                          : Image.asset(
                                              'assets/images/member/avatar_default.png',
                                              fit: BoxFit.cover,
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          staff.name,
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          staff.role,
                                          style: GoogleFonts.inter(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryLight,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            staff.salaryType.isNotEmpty ? staff.salaryType : 'Fixed Salary',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Payable amount
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Total Payable',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppTheme.textMuted,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '₹${NumberFormat('#,##,###').format(totalPayable)}',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: AppTheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
