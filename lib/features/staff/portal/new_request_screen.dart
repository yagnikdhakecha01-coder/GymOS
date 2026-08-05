import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/repository/gym_repository.dart';
import '../../authentication/auth_viewmodel.dart';

class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({super.key});

  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  String _selectedType = 'Advance Salary'; // Advance Salary or Holiday Request
  final _amountController = TextEditingController();
  final _daysController = TextEditingController();
  final _reasonController = TextEditingController();

  DateTime? _startDate;
  DateTime? _endDate;
  String _leaveType = 'Casual';

  @override
  void dispose() {
    _amountController.dispose();
    _daysController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _recalculateDatesFromDays() {
    final days = int.tryParse(_daysController.text.trim());
    if (days != null && days > 0) {
      final start = _startDate ?? DateTime.now();
      setState(() {
        _startDate = start;
        _endDate = start.add(Duration(days: days - 1));
      });
    }
  }

  Future<void> _selectStartDateCalendar() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked;
        final days = int.tryParse(_daysController.text.trim()) ?? 1;
        _endDate = picked.add(Duration(days: days - 1));
      });
    }
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: (_startDate != null && _endDate != null)
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : DateTimeRange(start: DateTime.now(), end: DateTime.now()),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        final count = picked.end.difference(picked.start).inDays + 1;
        _daysController.text = count.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final computedDays = (_startDate != null && _endDate != null)
        ? _endDate!.difference(_startDate!).inDays + 1
        : (int.tryParse(_daysController.text.trim()) ?? 0);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'New Request',
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Selector Row
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedType = 'Advance Salary'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedType == 'Advance Salary' ? AppTheme.primary : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Advance Salary',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _selectedType == 'Advance Salary' ? Colors.white : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedType = 'Holiday Request'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _selectedType == 'Holiday Request' ? AppTheme.primary : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Holiday Request',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _selectedType == 'Holiday Request' ? Colors.white : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 2. Dynamic Input Fields
              if (_selectedType == 'Advance Salary') ...[
                Text(
                  'Amount (₹)',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Enter amount (e.g. 2000)',
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ] else ...[
                // STEP 1: Enter Number of Days
                Text(
                  '1. Number of Days Required',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _daysController,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _recalculateDatesFromDays(),
                  decoration: const InputDecoration(
                    hintText: 'Enter days (e.g. 2 or 3)',
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 16),

                // STEP 2: Select Dates on Calendar
                Text(
                  '2. Select Dates on Calendar',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _selectStartDateCalendar,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.border),
                            borderRadius: BorderRadius.circular(10),
                            color: const Color(0xFFF9FAFB),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month, color: AppTheme.primary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _startDate != null
                                      ? DateFormat('dd MMM yyyy').format(_startDate!)
                                      : 'Start Date',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: _startDate != null ? FontWeight.w600 : FontWeight.normal,
                                    color: _startDate != null ? AppTheme.textPrimary : AppTheme.textMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: _selectDateRange,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.border),
                            borderRadius: BorderRadius.circular(10),
                            color: const Color(0xFFF9FAFB),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range, color: AppTheme.primary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _endDate != null
                                      ? DateFormat('dd MMM yyyy').format(_endDate!)
                                      : 'End Date',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: _endDate != null ? FontWeight.w600 : FontWeight.normal,
                                    color: _endDate != null ? AppTheme.textPrimary : AppTheme.textMuted,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_startDate != null && _endDate != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Selected Leave Period:',
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                        Text(
                          '${DateFormat('dd MMM').format(_startDate!)} - ${DateFormat('dd MMM yyyy').format(_endDate!)} ($computedDays ${computedDays == 1 ? 'Day' : 'Days'})',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // STEP 3: Leave Type
                Text(
                  '3. Leave Type',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _leaveType,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: ['Casual', 'Sick', 'Earned', 'Emergency']
                      .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _leaveType = val);
                  },
                ),
              ],
              const SizedBox(height: 20),

              // 3. Reason field
              Text(
                'Reason',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reasonController,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Enter detailed reason for request...',
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 32),

              // Submit Button
              CustomButton(
                text: 'Submit Request',
                color: AppTheme.primary,
                onPressed: () async {
                  final authVm = Provider.of<AuthViewModel>(context, listen: false);
                  final repo = Provider.of<GymRepository>(context, listen: false);
                  final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;

                  if (profileUserId == null) return;
                  final matchingStaff = repo.getStaff().where((s) => s.userId == profileUserId).toList();
                  final staff = matchingStaff.isNotEmpty ? matchingStaff.first : null;

                  if (staff == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Staff profile not found.'), backgroundColor: AppTheme.danger),
                    );
                    return;
                  }

                  final gymId = staff.gymId;
                  final staffId = staff.id;
                  final reason = _reasonController.text.trim();

                  if (reason.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a reason for the request.'), backgroundColor: AppTheme.danger),
                    );
                    return;
                  }

                  try {
                    if (_selectedType == 'Advance Salary') {
                      final amount = double.tryParse(_amountController.text.trim());
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter a valid advance amount.'), backgroundColor: AppTheme.danger),
                        );
                        return;
                      }

                      await repo.saveSalaryAdvanceOffline(
                        gymId: gymId,
                        staffId: staffId,
                        amount: amount,
                        reason: reason,
                        date: DateTime.now().toIso8601String(),
                        status: 'Pending',
                      );
                    } else {
                      final daysInput = int.tryParse(_daysController.text.trim());
                      if (daysInput == null || daysInput <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Please enter the number of leave days.'), backgroundColor: AppTheme.danger),
                        );
                        return;
                      }

                      if (_startDate == null) {
                        _startDate = DateTime.now();
                      }
                      _endDate = _startDate!.add(Duration(days: daysInput - 1));

                      await repo.createLeaveRequestOffline(
                        gymId: gymId,
                        staffId: staffId,
                        startDate: _startDate!.toIso8601String(),
                        endDate: _endDate!.toIso8601String(),
                        reason: reason,
                        leaveType: _leaveType,
                      );
                    }

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Request submitted successfully!'), backgroundColor: AppTheme.success),
                      );
                      Navigator.pop(context, true);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to submit request: $e'), backgroundColor: AppTheme.danger),
                      );
                    }
                  }
                },
              ),
              const SizedBox(height: 20),

              // Note banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppTheme.primary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your request will be reviewed by the gym owner. You will be notified once it is approved.',
                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
