import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/custom_button.dart';
import 'package:provider/provider.dart';
import '../../../core/repository/gym_repository.dart';
import '../../authentication/auth_viewmodel.dart';
import '../../../core/models/member.dart';

class NewRequestScreen extends StatefulWidget {
  const NewRequestScreen({super.key});

  @override
  State<NewRequestScreen> createState() => _NewRequestScreenState();
}

class _NewRequestScreenState extends State<NewRequestScreen> {
  String _selectedType = 'Advance Salary'; // Advance Salary or Holiday Request
  final _amountController = TextEditingController(text: '5000');
  final _reasonController = TextEditingController(text: 'Needed for personal work');

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

              // 2. Amount field
              Text(
                _selectedType == 'Advance Salary' ? 'Amount (₹)' : 'Number of Days',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: _selectedType == 'Advance Salary' ? 'Enter amount' : 'Enter days number',
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
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
                  hintText: 'Reason for request...',
                  contentPadding: EdgeInsets.all(16),
                ),
              ),
              const SizedBox(height: 20),

              // 4. Attachment field
              Text(
                'Attachment (Optional)',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Upload Receipt',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    const Icon(Icons.cloud_upload_outlined, color: AppTheme.primary, size: 20),
                  ],
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
                  final countVal = double.tryParse(_amountController.text) ?? 1.0;

                  if (reason.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a reason.'), backgroundColor: AppTheme.danger),
                    );
                    return;
                  }

                  try {
                    if (_selectedType == 'Advance Salary') {
                      await repo.saveSalaryAdvanceOffline(
                        gymId: gymId,
                        staffId: staffId,
                        amount: countVal,
                        reason: reason,
                        date: DateTime.now().toIso8601String(),
                        status: 'Pending', // Sent as pending request!
                      );
                    } else {
                      // Holiday/Leave Request
                      final start = DateTime.now();
                      final end = start.add(Duration(days: countVal.toInt() - 1));
                      await repo.createLeaveRequestOffline(
                        gymId: gymId,
                        staffId: staffId,
                        startDate: start.toIso8601String(),
                        endDate: end.toIso8601String(),
                        reason: reason,
                        leaveType: 'Casual', // Default leave type
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
