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

class ClientDetailsScreen extends StatelessWidget {
  final Member member;
  final String program;
  final String status;

  const ClientDetailsScreen({
    super.key,
    required this.member,
    required this.program,
    required this.status,
  });

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
      (p) => p.id == member.membershipPlanId,
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

    final avatarUrl = member.avatar.isNotEmpty
        ? member.avatar
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
                          member.name,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          member.phone.isNotEmpty ? member.phone : 'No Phone Number',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          program,
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  _buildStatusBadge(status),
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
    final joined = _formatDate(member.joinDate);
    final expiry = _formatDate(member.extraFields['expiryDate']?.toString() ?? '');
    final goal = member.extraFields['goal']?.toString() ?? 'General Fitness';

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
                  _buildDetailsStat('Medical Details', member.medicalDetails.isNotEmpty ? member.medicalDetails : 'None'),
                  _buildDetailsStat('Discount Applied', '₹${member.discountAmount.toInt()}'),
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
              _buildProgramRow('Email Address', member.email.isNotEmpty ? member.email : 'No Email Provided'),
            ],
          ),
        ),
        if (member.notes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Special Notes',
            style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 10),
          CustomCard(
            padding: const EdgeInsets.all(16),
            child: Text(
              member.notes,
              style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textSecondary, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAttendanceTab(GymRepository repo) {
    final logs = repo.getAttendance().where((r) => r.userId == member.id && r.userType == 'Member').toList();
    if (logs.isEmpty) {
      return Center(
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
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        final timeStr = log.checkIn.isNotEmpty ? log.checkIn : '—';
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
    );
  }

  Widget _buildProgressTab() {
    final Map<String, dynamic> extra = member.extraFields;
    final Map<String, dynamic> measurements = (extra['measurements'] is Map<String, dynamic>)
        ? extra['measurements'] as Map<String, dynamic>
        : {};

    if (measurements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.monitor_weight_outlined, size: 40, color: Colors.grey[400]),
              const SizedBox(height: 12),
              Text(
                'No progress or measurements recorded yet.',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Body Measurements',
          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: measurements.entries.map((entry) {
              final label = entry.key.toUpperCase();
              final val = entry.value?.toString() ?? '—';
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                        Text(val, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFF3F4F6)),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPlanTab(GymRepository repo) {
    final workouts = repo.getWorkouts();
    final diets = repo.getDiets();

    final workout = workouts.firstWhere(
      (w) => w.id == member.assignedWorkoutId,
      orElse: () => workouts.isNotEmpty ? workouts.first : null as dynamic,
    );

    final diet = diets.firstWhere(
      (d) => d.id == member.assignedDietId,
      orElse: () => diets.isNotEmpty ? diets.first : null as dynamic,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
                workout != null ? workout.name : 'No Workout Assigned',
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
                diet != null ? diet.name : 'No Diet Plan Assigned',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
              if (diet != null && diet.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  diet.description,
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
    final double totalAmount = plan.price - member.discountAmount;
    final statusColor = member.paymentStatus == 'Paid'
        ? Colors.green
        : (member.paymentStatus == 'Partial' ? Colors.orange : Colors.red);

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
                      member.paymentStatus,
                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              const SizedBox(height: 18),
              _buildProgramRow('Base Plan Price', '₹${plan.price.toInt()}'),
              _buildProgramRow('Discount Applied', '- ₹${member.discountAmount.toInt()}', valueColor: Colors.red),
              const Divider(height: 1, color: Color(0xFFF3F4F6)),
              const SizedBox(height: 8),
              _buildProgramRow('Net Receivable', '₹${totalAmount.toInt()}'),
              _buildProgramRow('Total Received', '₹${member.totalReceivedAmount.toInt()}', valueColor: Colors.green),
              _buildProgramRow('Pending Balance', '₹${member.pendingAmount.toInt()}', valueColor: Colors.orange),
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
}
