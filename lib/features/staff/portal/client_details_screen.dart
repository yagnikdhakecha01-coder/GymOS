import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import '../../../core/repository/gym_repository.dart';
import '../../../core/models/member.dart';
import '../../../core/models/staff.dart';
import '../../../core/services/supabase_service.dart';
import '../../authentication/auth_viewmodel.dart';

class ClientDetailsScreen extends StatefulWidget {
  final Member member;
  final String program;
  final String status;

  const ClientDetailsScreen({
    super.key,
    required this.member,
    required this.program,
    required this.status,
  });

  @override
  State<ClientDetailsScreen> createState() => _ClientDetailsScreenState();
}

class _ClientDetailsScreenState extends State<ClientDetailsScreen> {
  late Member _currentMember;
  List<Map<String, dynamic>> _commissions = [];
  bool _loading = true;
  bool _loadingCommissions = false;

  // Loaded from database RPC
  double _commissionRate = 0;
  double _commissionEarned = 0;
  double _commissionPending = 0;
  double _memberPaymentsReceived = 0;
  String _planName = '';
  String _expiryDate = '';
  String _ptStartDate = '';

  @override
  void initState() {
    super.initState();
    _currentMember = widget.member;
    _parseCommissionFromProgram();
    _loadClientDetail();
  }

  void _parseCommissionFromProgram() {
    final match = RegExp(r'([\d.]+)\s*%\s*Comm').firstMatch(widget.program);
    if (match != null) {
      _commissionRate = double.tryParse(match.group(1) ?? '0') ?? 0;
    }
  }

  Map<String, dynamic> _safeMap(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  Future<Staff?> _resolveStaff() async {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final repo = Provider.of<GymRepository>(context, listen: false);
    final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;
    final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];

    Staff? staff = authVm.staffRecord;
    if (staff == null || staff.id.isEmpty) {
      final matching = repo.getStaff().where((s) {
        if (s.userId != profileUserId) return false;
        if (gymId != null && gymId.isNotEmpty && s.gymId.isNotEmpty) return s.gymId == gymId;
        return true;
      }).toList();
      staff = matching.isNotEmpty ? matching.first : null;
    }
    return staff;
  }

  Future<void> _loadClientDetail() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final staff = await _resolveStaff();
    final repo = Provider.of<GymRepository>(context, listen: false);

    if (staff != null && SupabaseService.isInitialized) {
      try {
        final detail = await repo.fetchTrainerClientDetail(staff.id, _currentMember.id);
        if (detail != null && mounted) {
          final extra = _safeMap(detail['extra_fields']);
          setState(() {
            _commissionRate = (detail['commission_rate'] as num?)?.toDouble() ?? _commissionRate;
            _commissionEarned = (detail['commission_earned'] as num?)?.toDouble() ?? 0;
            _commissionPending = (detail['commission_pending'] as num?)?.toDouble() ?? 0;
            _memberPaymentsReceived = (detail['member_payments_received'] as num?)?.toDouble() ?? _currentMember.totalReceivedAmount;
            _planName = detail['membership_plan_name']?.toString() ?? _planName;
            _expiryDate = detail['expiry_date']?.toString() ?? extra['expiryDate']?.toString() ?? '';
            _ptStartDate = detail['pt_start_date']?.toString() ?? detail['join_date']?.toString() ?? _currentMember.joinDate;
            _currentMember = _currentMember.copyWith(
              name: detail['member_name']?.toString() ?? _currentMember.name,
              email: detail['member_email']?.toString() ?? _currentMember.email,
              phone: detail['member_phone']?.toString() ?? _currentMember.phone,
              avatar: detail['member_avatar']?.toString() ?? _currentMember.avatar,
              joinDate: detail['join_date']?.toString() ?? _currentMember.joinDate,
              medicalDetails: detail['medical_details']?.toString() ?? _currentMember.medicalDetails,
              notes: detail['notes']?.toString() ?? _currentMember.notes,
              totalReceivedAmount: _memberPaymentsReceived,
              paymentStatus: detail['payment_status']?.toString() ?? _currentMember.paymentStatus,
              extraFields: extra,
            );
          });
        }
      } catch (e) {
        print('Error loading client detail: $e');
      }
    }

    await _loadCommissionHistory(staff);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadCommissionHistory(Staff? staff) async {
    if (!mounted) return;
    setState(() => _loadingCommissions = true);

    if (staff != null) {
      final repo = Provider.of<GymRepository>(context, listen: false);
      final list = await repo.fetchStaffCommissions(staff.id, pendingOnly: false);
      if (mounted) {
        setState(() {
          _commissions = list.where((c) => c['member_id'] == _currentMember.id).toList();
        });
      }
    }
    if (mounted) setState(() => _loadingCommissions = false);
  }

  String _formatDate(String rawDate) {
    if (rawDate.isEmpty) return '—';
    try {
      final parsed = DateTime.parse(rawDate);
      return DateFormat('dd MMM yyyy').format(parsed);
    } catch (_) {
      return rawDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Client Details', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        body: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    final avatarUrl = _currentMember.avatar.isNotEmpty
        ? _currentMember.avatar
        : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=150';

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Client Details',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
              child: Row(
                children: [
                  CircleAvatar(radius: 28, backgroundImage: NetworkImage(avatarUrl)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_currentMember.name, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 3),
                        Text(_currentMember.phone.isNotEmpty ? _currentMember.phone : 'No Phone', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                        const SizedBox(height: 2),
                        Text(widget.program, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  _buildStatusBadge(widget.status),
                ],
              ),
            ),
            Container(
              color: Colors.white,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                indicatorColor: AppTheme.primary,
                dividerColor: const Color(0xFFF3F4F6),
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'Body'),
                  Tab(text: 'Membership'),
                  Tab(text: 'Commission'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildOverviewTab(),
                  _buildProgressTab(),
                  _buildMembershipTab(),
                  _buildCommissionTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final joined = _formatDate(_ptStartDate.isNotEmpty ? _ptStartDate : _currentMember.joinDate);
    final expiry = _formatDate(_expiryDate.isNotEmpty ? _expiryDate : _currentMember.extraFields['expiryDate']?.toString() ?? '');
    final goal = _currentMember.extraFields['goal']?.toString() ?? 'General Fitness';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailsStat('Membership Start', joined),
                  _buildDetailsStat('Membership Expiry', expiry),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailsStat('Plan', _planName.isNotEmpty ? _planName : '—'),
                  _buildDetailsStat('PT Goal', goal),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildProgramRow('Your Commission Rate', '${_commissionRate.toStringAsFixed(1)}%'),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Commission Earned', '₹${_commissionEarned.toStringAsFixed(0)}', valueColor: AppTheme.primary),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Medical Details', _currentMember.medicalDetails.isNotEmpty ? _currentMember.medicalDetails : 'None'),
            ],
          ),
        ),
        if (_currentMember.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Notes', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          CustomCard(
            padding: const EdgeInsets.all(16),
            child: Text(_currentMember.notes, style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4)),
          ),
        ],
      ],
    );
  }

  Widget _buildMembershipTab() {
    final joined = _formatDate(_ptStartDate.isNotEmpty ? _ptStartDate : _currentMember.joinDate);
    final expiry = _formatDate(_expiryDate.isNotEmpty ? _expiryDate : _currentMember.extraFields['expiryDate']?.toString() ?? '');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Membership Dates', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: AppTheme.primary, size: 18),
              onPressed: _showEditPlanValidityBottomSheet,
            ),
          ],
        ),
        const SizedBox(height: 8),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildProgramRow('Start Date', joined),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Expiry Date', expiry),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Plan Name', _planName.isNotEmpty ? _planName : '—'),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('PT Program', widget.program),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommissionTab() {
    final calculatedFromReceived = _memberPaymentsReceived > 0 && _commissionRate > 0
        ? (_memberPaymentsReceived * _commissionRate / 100)
        : 0.0;
    final displayEarned = _commissionEarned > 0 ? _commissionEarned : calculatedFromReceived;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your PT Earnings', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Commission is calculated on payments received by gym — not total membership price.',
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted, height: 1.3),
              ),
              const SizedBox(height: 16),
              _buildProgramRow('Commission Rate', '${_commissionRate.toStringAsFixed(1)}%'),
              _buildProgramRow('Member Payments Received', '₹${_memberPaymentsReceived.toStringAsFixed(0)}'),
              _buildProgramRow('Your Commission (Calculated)', '₹${displayEarned.toStringAsFixed(0)}', valueColor: AppTheme.primary),
              _buildProgramRow('Pending Payout', '₹${_commissionPending.toStringAsFixed(0)}', valueColor: Colors.orange),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Commission History', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        _loadingCommissions
            ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: AppTheme.primary)))
            : _commissions.isEmpty
                ? CustomCard(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'No commission entries yet.\nWhen member pays, your ${_commissionRate.toStringAsFixed(0)}% commission will appear here.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textMuted),
                      ),
                    ),
                  )
                : Column(
                    children: _commissions.map((comm) {
                      final receivedAmt = (comm['payment_received'] as num?)?.toDouble() ?? 0.0;
                      final earnedAmt = (comm['amount'] as num?)?.toDouble() ?? 0.0;
                      final rate = (comm['commission_rate'] as num?)?.toDouble() ?? _commissionRate;
                      final payoutStatus = comm['status']?.toString() ?? 'Pending';
                      final isPaid = payoutStatus == 'Paid';

                      return CustomCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Payment Entry', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isPaid ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(isPaid ? 'Paid' : 'Pending', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: isPaid ? Colors.green : Colors.orange)),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            _buildProgramRow('Payment Received', '₹${receivedAmt.toStringAsFixed(0)}'),
                            _buildProgramRow('Commission Rate', '${rate.toStringAsFixed(1)}%'),
                            _buildProgramRow('You Earned', '₹${earnedAmt.toStringAsFixed(0)}', valueColor: AppTheme.primary),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
      ],
    );
  }

  Widget _buildProgressTab() {
    final extra = _safeMap(_currentMember.extraFields);
    final measurements = _safeMap(extra['measurements']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Body Measurements',
              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: AppTheme.primary, size: 18),
              onPressed: _showUpdateMeasurementsBottomSheet,
            ),
          ],
        ),
        const SizedBox(height: 8),
        measurements.isEmpty
            ? CustomCard(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.monitor_weight_outlined, size: 40, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text(
                        'No measurements recorded. Tap edit icon above to record.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              )
            : CustomCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildProgramRow('HEIGHT', '${measurements['height'] ?? '—'} cm'),
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    _buildProgramRow('WEIGHT', '${measurements['weight'] ?? '—'} kg'),
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    _buildProgramRow('CHEST', '${measurements['chest'] ?? '—'} in'),
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    _buildProgramRow('WAIST', '${measurements['waist'] ?? '—'} in'),
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    _buildProgramRow('BICEPS', '${measurements['biceps'] ?? '—'} in'),
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    _buildProgramRow('HIP', '${measurements['hip'] ?? '—'} in'),
                  ],
                ),
              ),
      ],
    );
  }

  Widget _buildDetailsStat(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: valueColor ?? AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildProgramRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary)),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color text;
    if (status == 'Active') {
      bg = const Color(0xFFE8F5E9);
      text = Colors.green;
    } else if (status == 'Trial') {
      bg = const Color(0xFFFFF3E0);
      text = Colors.orange;
    } else {
      bg = const Color(0xFFFFEBEE);
      text = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }

  void _showMarkAttendanceBottomSheet() {
    DateTime selectedDate = DateTime.now();
    String status = 'Present';
    TimeOfDay checkInTime = TimeOfDay.now();
    TimeOfDay? checkOutTime;
    
    final dateController = TextEditingController(text: DateFormat('dd-MM-yyyy').format(selectedDate));
    final checkInController = TextEditingController(text: const DefaultMaterialLocalizations().formatTimeOfDay(checkInTime, alwaysUse24HourFormat: false));
    final checkOutController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Record Manual Attendance', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Date Selection
                    Text('Select Date', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: dateController,
                      readOnly: true,
                      decoration: InputDecoration(
                        suffixIcon: const Icon(Icons.calendar_month, color: AppTheme.primary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null) {
                          setSheetState(() {
                            selectedDate = picked;
                            dateController.text = DateFormat('dd-MM-yyyy').format(picked);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Status Selection
                    Text('Attendance Status', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Present', child: Text('Present')),
                        DropdownMenuItem(value: 'Absent', child: Text('Absent')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => status = val);
                        }
                      },
                    ),
                    
                    if (status == 'Present') ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Check-In Time', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: checkInController,
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    suffixIcon: const Icon(Icons.access_time, color: AppTheme.primary),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onTap: () async {
                                    final picked = await showTimePicker(context: context, initialTime: checkInTime);
                                    if (picked != null) {
                                      setSheetState(() {
                                        checkInTime = picked;
                                        checkInController.text = picked.format(context);
                                      });
                                    }
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
                                Text('Check-Out Time (Opt)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: checkOutController,
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    suffixIcon: const Icon(Icons.access_time, color: AppTheme.textMuted),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onTap: () async {
                                    final picked = await showTimePicker(context: context, initialTime: checkOutTime ?? TimeOfDay.now());
                                    if (picked != null) {
                                      setSheetState(() {
                                        checkOutTime = picked;
                                        checkOutController.text = picked.format(context);
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () async {
                        Navigator.pop(context); // Close sheet
                        
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                        );

                        try {
                          final repo = Provider.of<GymRepository>(context, listen: false);
                          
                          await repo.saveMemberAttendanceLog(
                            memberId: _currentMember.id,
                            memberName: _currentMember.name,
                            date: dateController.text.trim(),
                            status: status,
                            checkInTime: status == 'Present' ? checkInController.text.trim() : '',
                            checkOutTime: status == 'Present' && checkOutController.text.isNotEmpty ? checkOutController.text.trim() : null,
                          );

                          if (mounted) {
                            Navigator.pop(context); // Close loader
                            setState(() {}); // Rebuild to display new attendance logs
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ Attendance log recorded successfully!'), backgroundColor: AppTheme.success),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            Navigator.pop(context); // Close loader
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error saving attendance: $e'), backgroundColor: AppTheme.danger),
                            );
                          }
                        }
                      },
                      child: const Text('Record Attendance', style: TextStyle(fontWeight: FontWeight.bold)),
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

  void _showUpdateMeasurementsBottomSheet() {
    final extra = _safeMap(_currentMember.extraFields);
    final measurements = _safeMap(extra['measurements']);

    final weightController = TextEditingController(text: measurements['weight']?.toString() ?? '');
    final heightController = TextEditingController(text: measurements['height']?.toString() ?? '');
    final chestController = TextEditingController(text: measurements['chest']?.toString() ?? '');
    final waistController = TextEditingController(text: measurements['waist']?.toString() ?? '');
    final bicepsController = TextEditingController(text: measurements['biceps']?.toString() ?? '');
    final hipController = TextEditingController(text: measurements['hip']?.toString() ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Update Body Measurements', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold)),
                          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Weight (kg)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: weightController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(hintText: 'e.g. 70.5', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Height (cm)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: heightController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(hintText: 'e.g. 175', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Chest (inches)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: chestController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(hintText: 'e.g. 38', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Waist (inches)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: waistController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(hintText: 'e.g. 32', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Biceps (inches)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: bicepsController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(hintText: 'e.g. 14', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Hip (inches)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: hipController,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(hintText: 'e.g. 40', contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 16)),
                        onPressed: () async {
                          final newWeight = double.tryParse(weightController.text.trim());
                          final newHeight = double.tryParse(heightController.text.trim());
                          final newChest = double.tryParse(chestController.text.trim());
                          final newWaist = double.tryParse(waistController.text.trim());
                          final newBiceps = double.tryParse(bicepsController.text.trim());
                          final newHip = double.tryParse(hipController.text.trim());

                          final updatedMeasurements = {
                            'weight': newWeight,
                            'height': newHeight,
                            'chest': newChest,
                            'waist': newWaist,
                            'biceps': newBiceps,
                            'hip': newHip,
                          };

                          Navigator.pop(context); // Close sheet
                          
                          // Show loader
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                          );

                          try {
                            final repo = Provider.of<GymRepository>(context, listen: false);
                            final staff = await _resolveStaff();

                            Map<String, dynamic> updatedExtra;
                            if (staff != null && SupabaseService.isInitialized) {
                              updatedExtra = await repo.updateMemberMeasurements(
                                staff.id,
                                _currentMember.id,
                                updatedMeasurements,
                              );
                            } else {
                              updatedExtra = Map<String, dynamic>.from(_currentMember.extraFields);
                              updatedExtra['measurements'] = updatedMeasurements;
                              if (newWeight != null) updatedExtra['weight'] = newWeight;
                              if (newHeight != null) updatedExtra['height'] = newHeight;
                              final updatedMember = _currentMember.copyWith(extraFields: updatedExtra);
                              await repo.saveMember(updatedMember);
                            }

                            if (mounted) {
                              Navigator.pop(context);
                              setState(() {
                                _currentMember = _currentMember.copyWith(extraFields: updatedExtra);
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('✅ Measurements updated successfully!'), backgroundColor: AppTheme.success),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              Navigator.pop(context); // Close loader
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error updating measurements: $e'), backgroundColor: AppTheme.danger),
                              );
                            }
                          }
                        },
                        child: const Text('Save Measurements', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditPlanValidityBottomSheet() {
    DateTime joinDate = DateTime.tryParse(_ptStartDate.isNotEmpty ? _ptStartDate : _currentMember.joinDate) ?? DateTime.now();
    DateTime expiryDate = DateTime.now();

    final exp = _expiryDate.isNotEmpty
        ? _expiryDate
        : _currentMember.extraFields['expiryDate']?.toString();
    if (exp != null && exp.isNotEmpty) {
      expiryDate = DateTime.tryParse(exp) ?? DateTime.now().add(const Duration(days: 30));
    } else {
      expiryDate = DateTime.now().add(const Duration(days: 30));
    }

    final joinController = TextEditingController(text: DateFormat('dd-MM-yyyy').format(joinDate));
    final expiryController = TextEditingController(text: DateFormat('dd-MM-yyyy').format(expiryDate));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Edit Plan Validity', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // Join Date
                    Text('Start Date (Join Date)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: joinController,
                      readOnly: true,
                      decoration: InputDecoration(
                        suffixIcon: const Icon(Icons.calendar_month, color: AppTheme.primary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: joinDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 730)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setSheetState(() {
                            joinDate = picked;
                            joinController.text = DateFormat('dd-MM-yyyy').format(picked);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Expiry Date
                    Text('Expiry Date (End Date)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: expiryController,
                      readOnly: true,
                      decoration: InputDecoration(
                        suffixIcon: const Icon(Icons.calendar_month, color: AppTheme.primary),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: expiryDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (picked != null) {
                          setSheetState(() {
                            expiryDate = picked;
                            expiryController.text = DateFormat('dd-MM-yyyy').format(picked);
                          });
                        }
                      },
                    ),
                    
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 16)),
                      onPressed: () async {
                        Navigator.pop(context); // Close sheet
                        
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                        );

                        try {
                          final repo = Provider.of<GymRepository>(context, listen: false);
                          
                          final updatedExtra = Map<String, dynamic>.from(_currentMember.extraFields);
                          updatedExtra['expiryDate'] = expiryDate.toIso8601String().substring(0, 10);
                          
                          final updatedMember = _currentMember.copyWith(
                            joinDate: joinDate.toIso8601String().substring(0, 10),
                            extraFields: updatedExtra,
                          );

                          await repo.saveMember(updatedMember);

                          if (mounted) {
                            Navigator.pop(context);
                            final joinStr = joinDate.toIso8601String().substring(0, 10);
                            final expiryStr = expiryDate.toIso8601String().substring(0, 10);
                            setState(() {
                              _currentMember = updatedMember;
                              _ptStartDate = joinStr;
                              _expiryDate = expiryStr;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ Plan validity updated successfully!'), backgroundColor: AppTheme.success),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            Navigator.pop(context); // Close loader
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error updating plan dates: $e'), backgroundColor: AppTheme.danger),
                            );
                          }
                        }
                      },
                      child: const Text('Save Validity Dates', style: TextStyle(fontWeight: FontWeight.bold)),
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
}
