import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/models/staff.dart';
import '../staff_viewmodel.dart';
import '../staff_profile_screen.dart';
import '../pay_salary_screen.dart';

/// Read-only salary view for staff — breakdown, advances, history.
class StaffSalaryScreen extends StatefulWidget {
  final Staff staff;

  const StaffSalaryScreen({super.key, required this.staff});

  @override
  State<StaffSalaryScreen> createState() => _StaffSalaryScreenState();
}

class _StaffSalaryScreenState extends State<StaffSalaryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedMonth = '';
  final List<String> _months = [];

  List<Map<String, dynamic>> _advanceRecords = [];
  List<Map<String, dynamic>> _salaryHistory = [];
  bool _loadingTabs = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    for (int i = -5; i <= 1; i++) {
      _months.add(DateFormat('MMMM yyyy').format(DateTime(now.year, now.month + i, 1)));
    }
    _selectedMonth = DateFormat('MMMM yyyy').format(now);
    _loadTabsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTabsData() async {
    setState(() => _loadingTabs = true);
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    final data = await staffVm.getStaffDashboardData(widget.staff.id);
    if (mounted) {
      setState(() {
        _advanceRecords = List<Map<String, dynamic>>.from(data['advance'] ?? []);
        _salaryHistory = List<Map<String, dynamic>>.from(data['salaryHistory'] ?? []);
        _loadingTabs = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Text('My Salary', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedMonth,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                items: _months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedMonth = val);
                },
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppTheme.primary,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          tabs: const [
            Tab(text: 'Breakdown'),
            Tab(text: 'Advances'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          PaySalaryScreen(
            key: ValueKey(_selectedMonth),
            staff: widget.staff,
            selectedMonth: _selectedMonth,
            readOnly: true,
          ),
          _buildAdvancesTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildAdvancesTab() {
    if (_loadingTabs) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_advanceRecords.isEmpty) {
      return Center(child: Text('No advance records', style: GoogleFonts.inter(color: AppTheme.textMuted)));
    }

    final total = _advanceRecords.fold<double>(0, (sum, r) {
      return sum + ((r['advance_amount'] ?? r['amount'] ?? 0) as num).toDouble();
    });

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total Advance', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
              Text('₹${NumberFormat('#,##,###').format(total)}', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ..._advanceRecords.map((r) {
          final status = r['status']?.toString() ?? 'Pending';
          final amt = ((r['advance_amount'] ?? r['amount'] ?? 0) as num).toDouble();
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              title: Text('₹${NumberFormat('#,##,###').format(amt)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              subtitle: Text('${r['givenOn'] ?? r['salary_month'] ?? '—'} • ${r['reason'] ?? ''}'),
              trailing: Text(status, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildHistoryTab() {
    if (_loadingTabs) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_salaryHistory.isEmpty) {
      return Center(child: Text('No salary history yet', style: GoogleFonts.inter(color: AppTheme.textMuted)));
    }

    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: _salaryHistory.map((record) => SalaryHistoryItemWidget(record: record, staffVm: staffVm)).toList(),
    );
  }
}
