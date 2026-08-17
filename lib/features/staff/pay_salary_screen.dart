import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/models/staff.dart';
import '../../core/models/salary_draft.dart';
import '../../core/models/salary_adjustment.dart';
import '../authentication/auth_viewmodel.dart';
import '../../core/widgets/success_dialog.dart';
import '../../core/services/supabase_service.dart';
import 'staff_viewmodel.dart';
import '../../core/repository/gym_repository.dart';

class PaySalaryScreen extends StatefulWidget {
  final Staff staff;
  final String selectedMonth;
  final bool readOnly;

  const PaySalaryScreen({
    super.key,
    required this.staff,
    required this.selectedMonth,
    this.readOnly = false,
  });

  @override
  State<PaySalaryScreen> createState() => _PaySalaryScreenState();
}

class _PaySalaryScreenState extends State<PaySalaryScreen> {
  // Collapsed sections states
  bool _commissionExpanded = false;
  bool _leavesExpanded = false;
  bool _advancesExpanded = false;

  // Form Controllers
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  String _selectedMethod = 'UPI';
  DateTime _paymentDate = DateTime.now();

  // Database-backed states
  SalaryDraft? _draft;
  List<SalaryAdjustment> _dbAdjustments = [];
  List<Map<String, dynamic>> _commissions = [];
  Map<String, dynamic>? _leaveDetails;
  List<Map<String, dynamic>> _leaves = [];
  List<Map<String, dynamic>> _attendanceLogs = [];
  List<Map<String, dynamic>> _advances = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDraftDetails();
  }

  Future<void> _loadDraftDetails() async {
    // 1. Check local repository cache first so we can render instantly!
    final gymRepository = Provider.of<GymRepository>(context, listen: false);
    final cachedDraftMap = gymRepository.salaryDrafts.firstWhere(
      (d) => d['staff_id'] == widget.staff.id && d['salary_month'] == widget.selectedMonth,
      orElse: () => {},
    );

    if (cachedDraftMap.isNotEmpty) {
      _draft = SalaryDraft.fromJson(cachedDraftMap);
      _isLoading = false;
      if (mounted) setState(() {});
    } else {
      setState(() => _isLoading = true);
    }

    // 2. Fetch/update in the background
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? '';
      final staffVm = Provider.of<StaffViewModel>(context, listen: false);

      SalaryDraft? draft = await staffVm.getOrCreateSalaryDraft(gymId, widget.staff.id, widget.selectedMonth);
      
      // If RPC failed, try direct upsert as fallback
      if (draft == null && SupabaseService.isInitialized && gymId.isNotEmpty) {
        try {
          final upsertResponse = await SupabaseService.client
              .from('salary_drafts')
              .upsert({
                'gym_id': gymId,
                'staff_id': widget.staff.id,
                'salary_month': widget.selectedMonth,
                'base_salary': widget.staff.salary,
                'net_salary': widget.staff.salary,
                'status': 'Draft',
              }, onConflict: 'staff_id,salary_month')
              .select()
              .maybeSingle();
          if (upsertResponse != null) {
            draft = SalaryDraft.fromJson(upsertResponse);
          }
        } catch (_) {}
      }
      
      draft ??= SalaryDraft(
        id: 'draft_${widget.staff.id}_${widget.selectedMonth.replaceAll(' ', '_')}',
        gymId: gymId,
        staffId: widget.staff.id,
        salaryMonth: widget.selectedMonth,
        baseSalary: widget.staff.salary,
        commissionAmount: 0.0,
        advanceDeduction: 0.0,
        otherAdditions: 0.0,
        otherDeductions: 0.0,
        netSalary: widget.staff.salary,
        status: 'Draft',
      );

      bool isPaidSalaryMonth = (draft?.status.toLowerCase() == 'paid') || gymRepository.salaryDrafts.any((d) {
        final sid = d['staff_id'] ?? '';
        final month = d['salary_month'] ?? '';
        final status = (d['status'] ?? '').toString().toLowerCase();
        return sid == widget.staff.id && month == widget.selectedMonth && status == 'paid';
      });

      if (!isPaidSalaryMonth && SupabaseService.isInitialized) {
        try {
          final dbCheck = await SupabaseService.client
              .from('salary_drafts')
              .select('id, status')
              .eq('staff_id', widget.staff.id)
              .eq('salary_month', widget.selectedMonth)
              .maybeSingle();
          if (dbCheck != null && (dbCheck['status']?.toString().toLowerCase() == 'paid')) {
            isPaidSalaryMonth = true;
          } else {
            final expCheck = await SupabaseService.client
                .from('expenses')
                .select('id')
                .eq('gym_id', gymId)
                .eq('category', 'Salaries')
                .ilike('title', '%${widget.staff.name}%')
                .maybeSingle();
            if (expCheck != null) {
              isPaidSalaryMonth = true;
            }
          }
        } catch (_) {}
      }

      final SalaryDraft validDraft = isPaidSalaryMonth ? draft.copyWith(status: 'Paid') : draft;

      final results = await Future.wait([
        staffVm.fetchSalaryAdjustments(validDraft.id).catchError((_) => <SalaryAdjustment>[]),
        staffVm.fetchStaffCommissions(widget.staff.id, pendingOnly: false).catchError((_) => <Map<String, dynamic>>[]),
        staffVm.fetchStaffSalaryMonthLeaveDetails(widget.staff.id, widget.selectedMonth).catchError((_) => null),
        staffVm.fetchSalaryAdvances(widget.staff.id).catchError((_) => <Map<String, dynamic>>[]),
      ]);

      if (mounted) {
        setState(() {
          _draft = validDraft;
          _dbAdjustments = results[0] as List<SalaryAdjustment>;
          _commissions = results[1] as List<Map<String, dynamic>>;
          final leaveDetails = results[2] as Map<String, dynamic>?;
          _leaveDetails = leaveDetails;

          // Load leaves from local repository to include newly approved ones instantly!
          final localLeaves = gymRepository.leaveRequests.where((l) {
            final isOwn = l['staff_id'] == widget.staff.id;
            final isApproved = l['status'] == 'Approved';
            if (!isOwn || !isApproved) return false;
            try {
              final start = DateTime.tryParse(l['start_date'] ?? '');
              final end = DateTime.tryParse(l['end_date'] ?? '');
              if (start == null || end == null) return false;
              final startMonth = DateFormat('MMMM yyyy').format(start);
              final endMonth = DateFormat('MMMM yyyy').format(end);
              return startMonth == widget.selectedMonth || endMonth == widget.selectedMonth;
            } catch (_) {
              return false;
            }
          }).toList();

          _leaves = List<Map<String, dynamic>>.from(localLeaves);
          _attendanceLogs = List<Map<String, dynamic>>.from(leaveDetails?['attendance_logs'] ?? []);

          // Load advances: merge remote fetch + local cache
          final remoteAdvances = results[3] as List<Map<String, dynamic>>;
          final localAdvances = gymRepository.salaryAdvances.where((a) {
            final isOwn = a['staff_id'] == widget.staff.id;
            final status = (a['status']?.toString() ?? '').toLowerCase();
            final isActive = status == 'approved' || status == 'given' || status == 'pending';
            final month = a['salary_month']?.toString() ?? '';
            final givenMonth = a['given_date'] != null
                ? DateFormat('MMMM yyyy').format(DateTime.tryParse(a['given_date'].toString()) ?? DateTime.now())
                : '';
            final isMonth = month == widget.selectedMonth || givenMonth == widget.selectedMonth;
            return isOwn && isActive && isMonth;
          }).toList();

          final mergedAdvances = <String, Map<String, dynamic>>{};
          for (final a in [...remoteAdvances, ...localAdvances]) {
            final id = a['id']?.toString() ?? '${a['given_date']}_${a['advance_amount']}';
            mergedAdvances[id] = Map<String, dynamic>.from(a);
          }
          _advances = mergedAdvances.values.toList();
          _isLoading = false;
        });

        // Force-touch the draft in DB to trigger recalculation of commission/advance/adjustment totals
        final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
        if (uuidRegex.hasMatch(validDraft.id) && validDraft.status != 'Paid' && SupabaseService.isInitialized) {
          try {
            await SupabaseService.client
                .from('salary_drafts')
                .update({'base_salary': validDraft.baseSalary})
                .eq('id', validDraft.id);
          } catch (_) {}
        }
      }
    } catch (e) {
      print('Error loading draft details in background: $e');
      if (mounted) {
        setState(() {
          _draft ??= SalaryDraft(
            id: 'draft_${widget.staff.id}_${widget.selectedMonth.replaceAll(' ', '_')}',
            gymId: '',
            staffId: widget.staff.id,
            salaryMonth: widget.selectedMonth,
            baseSalary: widget.staff.salary,
            commissionAmount: 0.0,
            advanceDeduction: 0.0,
            otherAdditions: 0.0,
            otherDeductions: 0.0,
            netSalary: widget.staff.salary,
            status: 'Draft',
          );
          _isLoading = false;
        });
      }
    }
  }

  bool get _isPaid => _draft?.status == 'Paid' || _draft?.status == 'paid';

  @override
  void dispose() {
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // Calculate live totals using database-backed draft calculations from Supabase
  double get _fixedSalary => _draft?.baseSalary ?? widget.staff.salary;
  double get _commission {
    // Compute live total from the fetched commissions list
    final monthComms = _commissions.where((c) {
      final m = (c['salary_month'] ?? '').toString().trim().toLowerCase();
      final date = c['created_at'] != null ? DateTime.tryParse(c['created_at'].toString()) : null;
      final calcMonth = date != null ? DateFormat('MMMM yyyy').format(date) : '';
      return m == widget.selectedMonth.trim().toLowerCase() || calcMonth.toLowerCase() == widget.selectedMonth.trim().toLowerCase() || m.isEmpty;
    }).toList();

    final liveTotal = monthComms.fold<double>(
      0.0,
      (sum, c) => sum + ((c['amount'] as num?)?.toDouble() ?? 0.0),
    );
    if (liveTotal > 0) return liveTotal;
    return _draft?.commissionAmount ?? 0.0;
  }
  
  double get _advanceDeduction {
    // If draft is already Paid, use the locked advance deduction from the draft
    if (_isPaid) {
      return _draft!.advanceDeduction;
    }
    double listSum = 0.0;
    for (final a in _advances) {
      final s = (a['status']?.toString() ?? '').toLowerCase();
      if (s == 'approved' || s == 'pending' || s == 'given') {
        final amt = a['remaining_amount'] ?? a['advance_amount'] ?? a['amount'];
        if (amt is num) {
          listSum += amt.toDouble();
        }
      }
    }
    if (listSum > 0) return listSum;
    return _draft?.advanceDeduction ?? 0.0;
  }

  double get _advancesTotal => _advances.fold<double>(0.0, (sum, a) => sum + ((a['advance_amount'] ?? a['amount'] as num? ?? 0.0).toDouble()));
  double get _advancesRecovered => _advances.fold<double>(0.0, (sum, a) => sum + ((a['recovered_amount'] as num? ?? 0.0).toDouble()));
  double get _advancesPending => _advances.fold<double>(0.0, (sum, a) => sum + ((a['remaining_amount'] ?? a['amount'] as num? ?? 0.0).toDouble()));
  
  double get _totalAddition => _dbAdjustments
      .where((a) => a.type == 'Addition')
      .fold(0.0, (sum, a) => sum + a.amount);

  double get _totalDeduction => _dbAdjustments
      .where((a) => a.type == 'Deduction')
      .fold(0.0, (sum, a) => sum + a.amount);

  double get _netAdjustment => _totalAddition - _totalDeduction;

  double get _totalGrossSalary => _fixedSalary + _commission + _netAdjustment;

  double get _totalPayable => _isPaid
      ? 0.0
      : (_totalGrossSalary - _advanceDeduction > 0 ? _totalGrossSalary - _advanceDeduction : 0.0);

  void _addAdjustmentDialog() {
    final reasonCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    String type = 'Addition';
    final pageContext = context; // Save page-level context

    showDialog(
      context: pageContext,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Text('Add Adjustment', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<String>(
                            value: 'Addition',
                            groupValue: type,
                            onChanged: (val) => setDialogState(() => type = val!),
                            activeColor: AppTheme.primary,
                          ),
                          Text('Addition', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<String>(
                            value: 'Deduction',
                            groupValue: type,
                            onChanged: (val) => setDialogState(() => type = val!),
                            activeColor: AppTheme.primary,
                          ),
                          Text('Deduction', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                        ],
                      ),
                    ],
                  ),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(labelText: 'Reason'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Amount (₹)'),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    double amt = double.tryParse(amountCtrl.text) ?? 0.0;
                    String finalType = type;
                    if (amt < 0) {
                      amt = amt.abs();
                      finalType = 'Deduction';
                    }
                    if (reasonCtrl.text.isEmpty || amt <= 0 || _draft == null) return;

                    Navigator.pop(dialogCtx); // Close dialog first

                    // Show spinner using page context
                    showDialog(
                      context: pageContext,
                      barrierDismissible: false,
                      builder: (_) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                    );

                    try {
                      final authVm = Provider.of<AuthViewModel>(pageContext, listen: false);
                      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? '';
                      final userId = authVm.currentProfile?.id ?? authVm.currentUser?.id ?? '';

                      // Ensure we have a real UUID draft ID before inserting
                      String draftId = _draft!.id;
                      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
                      if (!uuidRegex.hasMatch(draftId)) {
                        // Draft has a synthetic placeholder ID — create real one via RPC
                        final staffVm = Provider.of<StaffViewModel>(pageContext, listen: false);
                        final realDraft = await staffVm.getOrCreateSalaryDraft(gymId, widget.staff.id, widget.selectedMonth);
                        if (realDraft != null) {
                          draftId = realDraft.id;
                          setState(() => _draft = realDraft);
                        } else {
                          // RPC unavailable — fallback: direct upsert into salary_drafts
                          final upsertResponse = await SupabaseService.client
                              .from('salary_drafts')
                              .upsert({
                                'gym_id': gymId,
                                'staff_id': widget.staff.id,
                                'salary_month': widget.selectedMonth,
                                'base_salary': widget.staff.salary,
                                'net_salary': widget.staff.salary,
                                'status': 'Draft',
                              }, onConflict: 'staff_id,salary_month')
                              .select()
                              .single();
                          draftId = upsertResponse['id'] as String;
                          setState(() => _draft = SalaryDraft.fromJson(upsertResponse));
                        }
                      }

                      // Direct insert into salary_adjustments table
                      await SupabaseService.client.from('salary_adjustments').insert({
                        'gym_id': gymId,
                        'salary_draft_id': draftId,
                        'type': finalType,
                        'amount': amt,
                        'reason': reasonCtrl.text.trim(),
                        'created_by': userId,
                      });

                      if (mounted) {
                        Navigator.pop(pageContext); // Pop spinner
                        _loadDraftDetails(); // Reload from DB
                      }
                    } catch (e) {
                      if (mounted) {
                        Navigator.pop(pageContext); // Pop spinner
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(content: Text('Failed to add adjustment: $e'), backgroundColor: AppTheme.danger),
                        );
                      }
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handlePaySalary() async {
    if (_draft == null) return;
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? '';
    
    // Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    try {
      final payableAmount = _totalPayable;
      final uuidRegex = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
      String realDraftId = _draft!.id;

      if (!uuidRegex.hasMatch(realDraftId)) {
        final realDraft = await staffVm.getOrCreateSalaryDraft(gymId, widget.staff.id, widget.selectedMonth);
        if (realDraft != null) {
          realDraftId = realDraft.id;
        } else if (SupabaseService.isInitialized && gymId.isNotEmpty) {
          final upsertRes = await SupabaseService.client.from('salary_drafts').upsert({
            'gym_id': gymId,
            'staff_id': widget.staff.id,
            'salary_month': widget.selectedMonth,
            'base_salary': _fixedSalary,
            'commission_amount': _commission,
            'advance_deduction': _advanceDeduction,
            'other_additions': _totalAddition,
            'other_deductions': _totalDeduction,
            'net_salary': payableAmount,
            'status': 'Draft',
          }, onConflict: 'staff_id,salary_month').select().single();
          realDraftId = upsertRes['id'] as String;
        }
      }

      // Update draft figures in DB before paying
      if (uuidRegex.hasMatch(realDraftId) && SupabaseService.isInitialized) {
        try {
          await SupabaseService.client.from('salary_drafts').update({
            'base_salary': _fixedSalary,
            'commission_amount': _commission,
            'advance_deduction': _advanceDeduction,
            'other_additions': _totalAddition,
            'other_deductions': _totalDeduction,
            'net_salary': payableAmount,
          }).eq('id', realDraftId);
        } catch (_) {}
      }

      await staffVm.paySalaryDraft(
        draftId: realDraftId,
        paymentMode: _selectedMethod,
        notes: _notesController.text.isNotEmpty ? _notesController.text : '${widget.selectedMonth} salary paid.',
      );

      // Save finance transaction locally & remotely
      staffVm.markSalaryAsPaid(widget.staff.id, widget.selectedMonth);

      if (gymId.isNotEmpty) {
        await staffVm.refreshStaffPayablesForMonth(gymId, widget.selectedMonth);
      }

      if (mounted) {
        Navigator.pop(context); // Pop loading spinner
        SuccessDialog.show(
          context,
          title: 'Salary Paid!',
          message: 'Salary of ₹${NumberFormat('#,##,###').format(payableAmount)} paid to ${widget.staff.name} successfully.',
          onDone: () {
            Navigator.pop(context);
          },
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop loading spinner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pay salary: ${e.toString().replaceAll('Exception:', '').trim()}'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String formattedDate = DateFormat('dd MMM yyyy').format(_paymentDate);
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
            // 1. Staff Profile Header Card
            if (!widget.readOnly)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundImage: NetworkImage(widget.staff.avatar),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.staff.name,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        Text(
                          widget.staff.role,
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.staff.salaryType.isNotEmpty ? widget.staff.salaryType : 'Fixed Salary',
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.primary),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Month: ${widget.selectedMonth}',
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.readOnly) const SizedBox(height: 12),

            if (_isPaid) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Salary for ${widget.selectedMonth} has been paid. New advances will be deducted from next month\'s salary.',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF047857)),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 2. Summary Grid (Calculations Overview Card)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _summaryBlock('Fixed Salary', '₹${NumberFormat('#,##,###').format(_fixedSalary)}', AppTheme.primary),
                      if (_commission > 0) ...[
                        const Text('+', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                        _summaryBlock('Commission', '₹${NumberFormat('#,##,###').format(_commission)}', Colors.green),
                      ],
                      if (_netAdjustment != 0) ...[
                        const Text('+', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                        _summaryBlock(
                          'Adjustments', 
                          _netAdjustment >= 0 ? '+ ₹${NumberFormat('#,##,###').format(_netAdjustment)}' : '- ₹${NumberFormat('#,##,###').format(_netAdjustment.abs())}', 
                          _netAdjustment >= 0 ? Colors.green : Colors.red,
                        ),
                      ],
                      const Text('=', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                      _summaryBlock(
                        _advanceDeduction > 0 ? 'Gross Salary' : (_isPaid ? 'Total Paid' : 'Pending Payable'), 
                        _isPaid 
                            ? '₹${NumberFormat('#,##,###').format(_totalGrossSalary)}' 
                            : '₹${NumberFormat('#,##,###').format(_totalGrossSalary)}', 
                        _isPaid ? const Color(0xFF047857) : AppTheme.primary, 
                        isBold: true
                      ),
                    ],
                  ),
                  if (_advanceDeduction > 0) ...[
                    const Divider(height: 24, color: AppTheme.border),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _summaryBlock('Gross Salary', '₹${NumberFormat('#,##,###').format(_totalGrossSalary)}', AppTheme.textPrimary),
                        const Text('-', style: TextStyle(fontSize: 16, color: Colors.red, fontWeight: FontWeight.bold)),
                        _summaryBlock('Advance Taken', '₹${NumberFormat('#,##,###').format(_advanceDeduction)}', Colors.red, isBold: true),
                        const Text('=', style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
                        _summaryBlock(
                          _isPaid ? 'Net Paid' : 'Pending Payable', 
                          _isPaid 
                              ? '₹${NumberFormat('#,##,###').format(_draft?.netSalary ?? (_totalGrossSalary - _advanceDeduction))}' 
                              : '₹${NumberFormat('#,##,###').format(_totalPayable)}', 
                          _isPaid ? const Color(0xFF047857) : AppTheme.primary, 
                          isBold: true
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 3. Commission Breakdown (Expandable Card) - Only show if Staff is commission-based or both
            if (widget.staff.salaryType == 'Commission Based' || widget.staff.salaryType == 'Both' || widget.staff.salaryType == 'Fixed + Commission' || widget.staff.salaryType == 'Percentage' || widget.staff.salaryType == 'Commission') ...[
              _expandableSection(
                title: '1. COMMISSION BREAKDOWN',
                badge: 'Total Commission: ₹${NumberFormat('#,##,###').format(_commission)}',
                isExpanded: _commissionExpanded,
                onToggle: () => setState(() => _commissionExpanded = !_commissionExpanded),
                child: _buildCommissionTable(),
              ),
              const SizedBox(height: 12),
            ],

            // 4. Leave Details (Expandable Card)
            _expandableSection(
              title: '2. LEAVE DETAILS',
              badge: 'Absent: ${_leaveDetails?['absent_days'] ?? 0} | Late: ${_leaveDetails?['late_days'] ?? 0} | Leaves: ${_leaveDetails?['approved_leave_days'] ?? 0} Days',
              isExpanded: _leavesExpanded,
              onToggle: () => setState(() => _leavesExpanded = !_leavesExpanded),
              child: _buildLeaveTable(),
            ),
            const SizedBox(height: 12),

            // Advance Details
            if (_advances.isNotEmpty) ...[
              _expandableSection(
                title: 'ADVANCE SALARY',
                badge: 'Total: ₹${NumberFormat('#,##,###').format(_advancesTotal)} | Recovered: ₹${NumberFormat('#,##,###').format(_advancesRecovered)} | Pending: ₹${NumberFormat('#,##,###').format(_advancesPending)}',
                isExpanded: _advancesExpanded,
                onToggle: () => setState(() => _advancesExpanded = !_advancesExpanded),
                child: _buildAdvancesTable(),
              ),
              const SizedBox(height: 12),
            ],

            // 5. Adjustments Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '3. ADJUSTMENTS (ADD / DEDUCT)',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (!_isPaid && !widget.readOnly)
                        TextButton.icon(
                          onPressed: _addAdjustmentDialog,
                          icon: const Icon(Icons.add, size: 14, color: AppTheme.primary),
                          label: Text(
                            'Add',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_advanceDeduction > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.5))),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.remove_circle,
                            color: Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Salary Advance Recovery', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                Text('Advance Deduction', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          Text(
                            '- ₹${_advanceDeduction.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              fontSize: 13, 
                              fontWeight: FontWeight.bold, 
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                  ],
                  ...List.generate(_dbAdjustments.length, (idx) {
                    final item = _dbAdjustments[idx];
                    final isAddition = item.type == 'Addition';
                    return Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.5))),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isAddition ? Icons.add_circle : Icons.remove_circle,
                            color: isAddition ? Colors.green : Colors.red,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.reason, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                                Text(item.type, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                              ],
                            ),
                          ),
                          Text(
                            isAddition ? '+ ₹${item.amount.toStringAsFixed(0)}' : '- ₹${item.amount.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(
                              fontSize: 13, 
                              fontWeight: FontWeight.bold, 
                              color: isAddition ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _adjustmentSummaryText('Total Addition', '+ ₹$_totalAddition', Colors.green),
                      _adjustmentSummaryText('Total Deduction', '- ₹$_totalDeduction', Colors.red),
                      _adjustmentSummaryText('Net Adjustment', _netAdjustment >= 0 ? '+ ₹$_netAdjustment' : '- ₹${_netAdjustment.abs()}', _netAdjustment >= 0 ? Colors.green : Colors.red),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            if (!widget.readOnly) ...[
            if (_isPaid) ...[
              // 6. Paid Settlement Receipt Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'PAYMENT SETTLEMENT RECEIPT',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF047857)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Month Compensation', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                        Text('₹${NumberFormat('#,##,###').format(_totalGrossSalary)}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      ],
                    ),
                    if (_advanceDeduction > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Advance Deducted', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                          Text('- ₹${NumberFormat('#,##,###').format(_advanceDeduction)}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red)),
                        ],
                      ),
                    ],
                    const Divider(height: 18, color: Color(0xFFA7F3D0)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Net Paid Amount', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF047857))),
                        Text('₹${NumberFormat('#,##,###').format((_totalGrossSalary - _advanceDeduction) > 0 ? (_totalGrossSalary - _advanceDeduction) : (_draft?.netSalary ?? _totalGrossSalary))}', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF047857))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFA7F3D0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Salary for ${widget.selectedMonth} is Paid',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF047857)),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // 6. Payment Details Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '4. PAYMENT DETAILS',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Payment Method', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                              DropdownButton<String>(
                                value: _selectedMethod,
                                isExpanded: true,
                                items: ['Cash', 'UPI', 'Bank', 'Cheque'].map((m) {
                                  return DropdownMenuItem(value: m, child: Text(m));
                                }).toList(),
                                onChanged: (val) => setState(() => _selectedMethod = val!),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _referenceController,
                            decoration: const InputDecoration(
                              labelText: 'Reference ID',
                              labelStyle: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _paymentDate,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => _paymentDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Payment Date: $formattedDate', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary)),
                            const Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.primary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(labelText: 'Notes (Optional)'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 7. Bottom Confirmation & Pay Button
              ElevatedButton(
                onPressed: _handlePaySalary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.send, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Pay Salary',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You are about to pay salary of ₹${NumberFormat('#,##,###').format(_totalPayable)} to ${widget.staff.name} for ${widget.selectedMonth}.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
            ],
          ],
        ),
      );

    if (widget.readOnly) {
      return body;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pay Salary',
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            Text(
              widget.selectedMonth,
              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
      body: body,
    );
  }

  Widget _summaryBlock(String title, String value, Color valueColor, {bool isBold = false}) {
    return Column(
      children: [
        Text(title, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14, 
            fontWeight: isBold ? FontWeight.w800 : FontWeight.bold, 
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _adjustmentSummaryText(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 9, color: AppTheme.textSecondary)),
        Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _expandableSection({
    required String title,
    required String badge,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary)),
            subtitle: Text(badge, style: GoogleFonts.inter(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w600)),
            trailing: Icon(isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppTheme.primary),
            onTap: onToggle,
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: child,
            ),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildCommissionTable() {
    if (_commissions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No commissions recorded.',
          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
        ),
      );
    }

    return Column(
      children: [
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
                _tableHeader('Source/Ref'),
                _tableHeader('Recd.'),
                _tableHeader('Rate'),
                _tableHeader('Comm.'),
              ],
            ),
            ..._commissions.map((it) {
              final dateParsed = DateTime.tryParse(it['created_at']?.toString() ?? '') ?? DateTime.now();
              final dateStr = DateFormat('dd MMM').format(dateParsed);
              final sourceRef = it['payment_id']?.toString().split('-').last ?? 'Payment';
              final double recd = (it['payment_received'] as num? ?? 0.0).toDouble();
              final double rate = (it['commission_rate'] as num? ?? 0.0).toDouble();
              final double comm = (it['amount'] as num? ?? 0.0).toDouble();
              return TableRow(
                children: [
                  _tableCell(dateStr),
                  _tableCell(sourceRef),
                  _tableCell('₹${recd.toStringAsFixed(0)}'),
                  _tableCell('${rate.toStringAsFixed(0)}%'),
                  _tableCell('₹${comm.toStringAsFixed(0)}', isBold: true, color: Colors.green),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildLeaveTable() {
    if (_leaves.isEmpty && _attendanceLogs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            'No leaves or attendance exceptions recorded for this month.',
            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_attendanceLogs.isNotEmpty) ...[
          Text(
            'Attendance Logs (Absent / Late)',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
          ),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1.0),
              2: FlexColumnWidth(1.2),
              3: FlexColumnWidth(1.2),
            },
            children: [
              TableRow(
                children: [
                  _tableHeader('Date'),
                  _tableHeader('Status'),
                  _tableHeader('Check In'),
                  _tableHeader('Check Out'),
                ],
              ),
              ..._attendanceLogs.map((it) {
                final dateStr = it['date']?.toString() ?? '';
                final status = it['status']?.toString() ?? '';
                final checkIn = it['check_in']?.toString() ?? 'N/A';
                final checkOut = it['check_out']?.toString() ?? 'N/A';
                final isAbsent = status == 'Absent';
                return TableRow(
                  children: [
                    _tableCell(dateStr),
                    _tableCell(
                      status, 
                      isBold: true, 
                      color: isAbsent ? AppTheme.danger : Colors.orange
                    ),
                    _tableCell(isAbsent ? '-' : checkIn),
                    _tableCell(isAbsent ? '-' : checkOut),
                  ],
                );
              }),
            ],
          ),
          if (_leaves.isNotEmpty) const SizedBox(height: 20),
        ],
        if (_leaves.isNotEmpty) ...[
          Text(
            'Approved Leave Requests',
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
          ),
          const SizedBox(height: 8),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.2),
              1: FlexColumnWidth(1.2),
              2: FlexColumnWidth(1.2),
              3: FlexColumnWidth(1.6),
            },
            children: [
              TableRow(
                children: [
                  _tableHeader('Start Date'),
                  _tableHeader('End Date'),
                  _tableHeader('Type'),
                  _tableHeader('Reason'),
                ],
              ),
              ..._leaves.map((it) {
                final startDateStr = it['start_date']?.toString() ?? '';
                final endDateStr = it['end_date']?.toString() ?? '';
                final type = it['leave_type']?.toString() ?? '';
                final reason = it['reason']?.toString() ?? '';
                return TableRow(
                  children: [
                    _tableCell(startDateStr),
                    _tableCell(endDateStr),
                    _tableCell(type, color: AppTheme.primary),
                    _tableCell(reason),
                  ],
                );
              }),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAdvancesTable() {
    if (_advances.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No advances recorded.',
          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted),
        ),
      );
    }
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1.5),
        2: FlexColumnWidth(0.9),
        3: FlexColumnWidth(0.9),
        4: FlexColumnWidth(0.9),
        5: FlexColumnWidth(1.0),
      },
      children: [
        TableRow(
          children: [
            _tableHeader('Given On'),
            _tableHeader('Reason'),
            _tableHeader('Advance'),
            _tableHeader('Recd.'),
            _tableHeader('Pending'),
            _tableHeader('Status'),
          ],
        ),
        ..._advances.map((it) {
          final reqDate = DateTime.tryParse(it['given_date']?.toString() ?? '') ?? DateTime.now();
          final dateStr = DateFormat('dd MMM yyyy').format(reqDate);
          final reasonStr = it['reason']?.toString() ?? 'Personal';
          final double advAmt = (it['advance_amount'] ?? it['amount'] as num? ?? 0.0).toDouble();
          final double recAmt = (it['recovered_amount'] as num? ?? 0.0).toDouble();
          final double remAmt = (it['remaining_amount'] ?? it['amount'] as num? ?? 0.0).toDouble();
          final statusStr = it['status']?.toString() ?? 'Pending';
          
          Color statusColor = Colors.orange;
          if (statusStr.toLowerCase() == 'recovered') {
            statusColor = Colors.green;
          } else if (statusStr.toLowerCase() == 'rejected') {
            statusColor = Colors.red;
          }

          return TableRow(
            children: [
              _tableCell(dateStr),
              _tableCell(reasonStr),
              _tableCell('₹${advAmt.toStringAsFixed(0)}'),
              _tableCell('₹${recAmt.toStringAsFixed(0)}', color: Colors.green),
              _tableCell('₹${remAmt.toStringAsFixed(0)}', color: Colors.red),
              _tableCell(statusStr, isBold: true, color: statusColor),
            ],
          );
        }),
      ],
    );
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _tableCell(String text, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color ?? AppTheme.textPrimary,
        ),
      ),
    );
  }
}
