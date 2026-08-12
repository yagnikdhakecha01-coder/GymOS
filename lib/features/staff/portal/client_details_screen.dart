import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_card.dart';
import '../../../core/widgets/custom_button.dart';
import '../../../core/repository/gym_repository.dart';
import '../../../core/models/member.dart';
import '../../../core/models/membership_plan.dart';
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
  bool _loadingCommissions = false;

  @override
  void initState() {
    super.initState();
    _currentMember = widget.member;
    _loadCommissionHistory();
  }

  Future<void> _loadCommissionHistory() async {
    if (!mounted) return;
    setState(() => _loadingCommissions = true);
    final repo = Provider.of<GymRepository>(context, listen: false);
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final profileUserId = authVm.currentProfile?.id ?? authVm.currentUser?.id;
    
    if (profileUserId == null) {
      if (mounted) setState(() => _loadingCommissions = false);
      return;
    }
    
    final matchingStaff = repo.getStaff().where((s) => s.userId == profileUserId).toList();
    final staff = matchingStaff.isNotEmpty ? matchingStaff.first : null;
    
    if (staff != null) {
      final list = await repo.fetchStaffCommissions(staff.id, pendingOnly: false);
      if (mounted) {
        setState(() {
          _commissions = list.where((c) => c['member_id'] == _currentMember.id).toList();
        });
      }
    }
    if (mounted) {
      setState(() => _loadingCommissions = false);
    }
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
    final repo = Provider.of<GymRepository>(context, listen: false);
    final plans = repo.getMemberships();
    final plan = plans.firstWhere(
      (p) => p.id == _currentMember.membershipPlanId,
      orElse: () => MembershipPlan(
        id: '',
        title: 'Standard Plan',
        price: 3000.0,
        durationMonths: 1,
        durationDays: 30,
        ptIncluded: false,
        dietIncluded: false,
        workoutIncluded: false,
        freezeDays: 0,
        reminderDays: 0,
      ),
    );

    final avatarUrl = _currentMember.avatar.isNotEmpty
        ? _currentMember.avatar
        : 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=150';

    return DefaultTabController(
      length: 5,
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
            // Profile Card Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundImage: NetworkImage(avatarUrl),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentMember.name,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _currentMember.phone.isNotEmpty ? _currentMember.phone : 'No Phone Number',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.program,
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(widget.status),
                ],
              ),
            ),

            // Tab selector
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
                  Tab(text: 'Attendance'),
                  Tab(text: 'Progress'),
                  Tab(text: 'Plan'),
                  Tab(text: 'Payments'),
                ],
              ),
            ),

            // Tab body
            Expanded(
              child: TabBarView(
                children: [
                  _buildOverviewTab(plan),
                  _buildAttendanceTab(repo),
                  _buildProgressTab(),
                  _buildPlanTab(repo),
                  _buildPaymentsTab(plan),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab(MembershipPlan plan) {
    final joined = _formatDate(_currentMember.joinDate);
    final expiry = _formatDate(_currentMember.extraFields['expiryDate']?.toString() ?? '');
    final goal = _currentMember.extraFields['goal']?.toString() ?? 'General Fitness';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Joined / Sessions info card
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailsStat('Joined On', joined),
                  _buildDetailsStat('Next Expiry', expiry),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailsStat('Medical Details', _currentMember.medicalDetails.isNotEmpty ? _currentMember.medicalDetails : 'None'),
                  _buildDetailsStat('Discount Applied', '₹${_currentMember.discountAmount.toInt()}'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Program Details card
        Text(
          'Program Details',
          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildProgramRow('Assigned PT Goal', goal),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Membership Plan', plan.title),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Plan Duration', '${plan.durationMonths} Months (${plan.durationDays} Days)'),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Email Address', _currentMember.email.isNotEmpty ? _currentMember.email : 'No Email Provided'),
            ],
          ),
        ),
        if (_currentMember.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Special Notes',
            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 10),
          CustomCard(
            padding: const EdgeInsets.all(16),
            child: Text(
              _currentMember.notes,
              style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAttendanceTab(GymRepository repo) {
    final logs = repo.getAttendance().where((r) => r.userId == _currentMember.id && r.userType == 'Member').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Attendance Logs (${logs.length})',
                style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Log', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _showMarkAttendanceBottomSheet,
              ),
            ],
          ),
        ),
        Expanded(
          child: logs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today_outlined, size: 40, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text(
                          'No attendance logs recorded.',
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final timeStr = log.checkInTime.isNotEmpty ? log.checkInTime : '—';
                    final statusColor = log.status == 'Present' ? Colors.green : Colors.red;

                    return CustomCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.circle, size: 10, color: AppTheme.primary),
                              const SizedBox(width: 12),
                              Text(
                                log.date,
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Text(
                                'In: $timeStr',
                                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                              const SizedBox(width: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  log.status,
                                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildProgressTab() {
    final Map<String, dynamic> extra = _currentMember.extraFields;
    final Map<String, dynamic> measurements = (extra['measurements'] is Map<String, dynamic>)
        ? extra['measurements'] as Map<String, dynamic>
        : {};

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

  Widget _buildPlanTab(GymRepository repo) {
    final workouts = repo.getWorkouts();
    final diets = repo.getDiets();

    final workout = workouts.firstWhere(
      (w) => w.id == _currentMember.assignedWorkoutId,
      orElse: () => workouts.isNotEmpty ? workouts.first : null as dynamic,
    );

    final diet = diets.firstWhere(
      (d) => d.id == _currentMember.assignedDietId,
      orElse: () => diets.isNotEmpty ? diets.first : null as dynamic,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Plan Validity Details',
              style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
            IconButton(
              icon: const Icon(Icons.calendar_month_outlined, color: AppTheme.primary, size: 18),
              onPressed: _showEditPlanValidityBottomSheet,
            ),
          ],
        ),
        const SizedBox(height: 8),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildProgramRow('Start Date', _formatDate(_currentMember.joinDate)),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              _buildProgramRow('Expiry Date', _formatDate(_currentMember.extraFields['expiryDate']?.toString() ?? '')),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Workout Schedule',
          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                workout != null ? workout.title : 'No Workout Assigned',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              if (workout != null && workout.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  workout.description,
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Diet & Nutrition Plan',
          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                diet != null ? diet.title : 'No Diet Plan Assigned',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              if (diet != null && diet.notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  diet.notes,
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentsTab(MembershipPlan plan) {
    final double totalAmount = plan.price - _currentMember.discountAmount;
    final statusColor = _currentMember.paymentStatus == 'Paid'
        ? Colors.green
        : (_currentMember.paymentStatus == 'Partial' ? Colors.orange : Colors.red);

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
                  Text(
                    'Payment Status',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _currentMember.paymentStatus,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              const SizedBox(height: 18),
              _buildProgramRow('Base Plan Price', '₹${plan.price.toInt()}'),
              _buildProgramRow('Discount Applied', '- ₹${_currentMember.discountAmount.toInt()}', valueColor: Colors.red),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              const SizedBox(height: 8),
              _buildProgramRow('Net Receivable', '₹${totalAmount.toInt()}'),
              _buildProgramRow('Total Received', '₹${_currentMember.totalReceivedAmount.toInt()}', valueColor: Colors.green),
              _buildProgramRow('Pending Balance', '₹${_currentMember.pendingAmount.toInt()}', valueColor: Colors.orange),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Your PT Commission History',
          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        _loadingCommissions
            ? const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator(color: AppTheme.primary)))
            : _commissions.isEmpty
                ? CustomCard(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'No commissions recorded for this member.',
                        style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textMuted),
                      ),
                    ),
                  )
                : Column(
                    children: _commissions.map((comm) {
                      final receivedAmt = (comm['payment_received'] as num?)?.toDouble() ?? 0.0;
                      final earnedAmt = (comm['amount'] as num?)?.toDouble() ?? 0.0;
                      final rate = (comm['commission_rate'] as num?)?.toDouble() ?? 0.0;
                      final payoutStatus = comm['status']?.toString() ?? 'Pending';
                      final isPaid = payoutStatus == 'Paid';
                      final payMonth = comm['payment_month']?.toString() ?? 'This Month';
                      
                      return CustomCard(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  payMonth,
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isPaid ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isPaid ? 'Paid in Salary' : 'Pending Payout',
                                    style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.bold, color: isPaid ? Colors.green : Colors.orange),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Received by Gym', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                Text('₹ ${receivedAmt.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Commission Rate', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                Text('${rate.toStringAsFixed(1)} %', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Commission Earned', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                Text('₹ ${earnedAmt.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
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
    final Map<String, dynamic> extra = _currentMember.extraFields;
    final Map<String, dynamic> measurements = (extra['measurements'] is Map<String, dynamic>)
        ? Map<String, dynamic>.from(extra['measurements'] as Map<String, dynamic>)
        : {};

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
                            final updatedExtra = Map<String, dynamic>.from(_currentMember.extraFields);
                            updatedExtra['measurements'] = updatedMeasurements;
                            
                            if (newWeight != null) updatedExtra['weight'] = newWeight;
                            if (newHeight != null) updatedExtra['height'] = newHeight;

                            final updatedMember = _currentMember.copyWith(
                              extraFields: updatedExtra,
                            );

                            await repo.saveMember(updatedMember);
                            
                            if (mounted) {
                              Navigator.pop(context); // Close loader
                              setState(() {
                                _currentMember = updatedMember;
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
    DateTime joinDate = DateTime.tryParse(_currentMember.joinDate) ?? DateTime.now();
    DateTime expiryDate = DateTime.now();
    
    final exp = _currentMember.extraFields['expiryDate'] as String?;
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
                            Navigator.pop(context); // Close loader
                            setState(() {
                              _currentMember = updatedMember;
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
