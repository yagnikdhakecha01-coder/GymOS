import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_card.dart';
import '../../core/widgets/success_dialog.dart';
import 'payment_result_screen.dart';
import 'members_viewmodel.dart';
import '../../core/models/member.dart';
import '../workout/workout_viewmodel.dart';
import '../diet/diet_viewmodel.dart';
import '../membership/membership_viewmodel.dart';
import '../../core/models/membership_plan.dart';
import '../../core/models/finance.dart';
import '../../core/models/workout_plan.dart';
import '../../core/models/diet_plan.dart';
import 'package:url_launcher/url_launcher.dart';
import '../staff/staff_viewmodel.dart';
import '../../core/services/supabase_service.dart';
class MemberProfileScreen extends StatefulWidget {
  final Member member;
  const MemberProfileScreen({super.key, required this.member});

  @override
  State<MemberProfileScreen> createState() => _MemberProfileScreenState();
}

class _MemberProfileScreenState extends State<MemberProfileScreen> {
  int _currentTab = 0; // 0 = Info, 1 = History, 2 = Notes, 3 = More

  // Invitation tracking
  Map<String, dynamic>? _invitation;
  bool _loadingInvitation = false;

  double _activeCommissionPercentage = 0.0;
  bool _loadingPt = false;

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
                  final message = '''🏋️ Gym Invitation

Hello,

You have been invited to join our gym.

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
            ],
          ),
        );
      },
    );
  }

  // Notes Controllers
  final _ownerNotesController = TextEditingController();
  final _trainerNotesController = TextEditingController();
  final _privateNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInvitation();
    _loadPtAssignment();
    _ownerNotesController.text = widget.member.notes.isNotEmpty ? widget.member.notes : 'Prefers morning sessions.\nFocus on weight loss goal.';
    _trainerNotesController.text = 'Suggesting low carb diet and moderate cardio intensity.';
    _privateNotesController.text = 'VIP Client. Needs premium attention.';
  }

  @override
  void dispose() {
    _ownerNotesController.dispose();
    _trainerNotesController.dispose();
    _privateNotesController.dispose();
    super.dispose();
  }

  Future<void> _loadInvitation() async {
    setState(() => _loadingInvitation = true);
    final membersVm = Provider.of<MembersViewModel>(context, listen: false);
    final invite = await membersVm.getLatestInvitation(widget.member.id);
    if (mounted) {
      setState(() {
        _invitation = invite;
        _loadingInvitation = false;
      });
    }
  }

  bool _isValidUUID(String val) {
    return RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(val);
  }

  Future<void> _loadPtAssignment() async {
    if (!widget.member.ptMember || widget.member.ptTrainer.isEmpty) return;
    setState(() => _loadingPt = true);
    
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    final trainer = staffVm.allStaff.where((s) => s.id == widget.member.ptTrainer).firstOrNull;
    if (trainer != null) {
      _activeCommissionPercentage = trainer.commissionPercentage;
    }
    
    if (SupabaseService.isInitialized) {
      try {
        final res = await SupabaseService.client
            .from('pt_assignments')
            .select('commission_percentage')
            .eq('member_id', widget.member.id)
            .eq('assignment_status', 'Active')
            .maybeSingle();
            
        if (res != null && res['commission_percentage'] != null) {
          if (mounted) {
            setState(() {
              _activeCommissionPercentage = (res['commission_percentage'] as num).toDouble();
            });
          }
        }
      } catch (e) {
        print('Error loading active PT assignment: $e');
      }
    }
    if (mounted) {
      setState(() => _loadingPt = false);
    }
  }

  void _showEditTrainerBottomSheet(MembersViewModel membersVm) {
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);
    final trainerList = staffVm.allStaff.where((s) => 
      s.role == 'Trainer' || s.role == 'Personal Trainer' || s.role.toLowerCase().contains('trainer')
    ).toList();

    bool hasPT = widget.member.ptMember;
    String? selectedTrainerId = _isValidUUID(widget.member.ptTrainer) ? widget.member.ptTrainer : null;
    
    if (selectedTrainerId == null && trainerList.isNotEmpty) {
      selectedTrainerId = trainerList.first.id;
    }

    final commController = TextEditingController(text: _activeCommissionPercentage.toStringAsFixed(1));

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
                        Text('Edit PT Assignment', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    SwitchListTile(
                      activeColor: AppTheme.primary,
                      title: Text('Assign Personal Trainer', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('Enable personal training sessions for this member', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                      value: hasPT,
                      onChanged: (val) {
                        setSheetState(() {
                          hasPT = val;
                        });
                      },
                    ),
                    
                    if (hasPT) ...[
                      const SizedBox(height: 16),
                      Text('Select Trainer', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: selectedTrainerId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: trainerList.map((t) {
                          return DropdownMenuItem<String>(
                            value: t.id,
                            child: Text(t.name, style: GoogleFonts.inter(fontSize: 14)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setSheetState(() {
                            selectedTrainerId = val;
                            final selectedTrainer = trainerList.where((s) => s.id == val).firstOrNull;
                            if (selectedTrainer != null) {
                              commController.text = selectedTrainer.commissionPercentage.toStringAsFixed(1);
                            }
                          });
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      Text('Commission Percentage (%)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: commController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          hintText: 'e.g. 10.0',
                          suffixText: '%',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        if (hasPT && selectedTrainerId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please select a trainer'), backgroundColor: AppTheme.danger),
                          );
                          return;
                        }

                        final double percentage = hasPT
                            ? (double.tryParse(commController.text.trim()) ?? 0.0)
                            : 0.0;

                        Navigator.pop(context); // Close sheet
                        
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                        );

                        try {
                          await membersVm.updateMemberPt(
                            memberId: widget.member.id,
                            ptMember: hasPT,
                            ptTrainerId: hasPT ? selectedTrainerId! : '',
                            commissionPercentage: percentage,
                          );

                          if (mounted) {
                            Navigator.pop(context); // Close loader
                            setState(() {
                              _activeCommissionPercentage = percentage;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ Trainer assignment updated successfully!'), backgroundColor: AppTheme.success),
                            );
                            _loadPtAssignment(); // Reload from database
                          }
                        } catch (e) {
                          if (mounted) {
                            Navigator.pop(context); // Close loader
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error updating Trainer: $e'), backgroundColor: AppTheme.danger),
                            );
                          }
                        }
                      },
                      child: const Text('Save Details', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Future<void> _confirmUnlink(MembersViewModel vm, Member member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Unlink Account?', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text(
          'This member account will be unlinked.\nThey will require a new invitation code to connect again.',
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
      final newCode = await vm.unlinkAccount(member.id);
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

  Future<void> _generateNewCode(MembersViewModel vm, Member member) async {
    setState(() => _loadingInvitation = true);
    await vm.generateInvitation(
      recordId: member.id,
      name: member.name,
      phone: member.phone,
    );
    await _loadInvitation();
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  // --- Bottom Sheet Actions ---

  void _showReceivePaymentBottomSheet(MembersViewModel membersVm, Member member, MembershipPlan? plan) {
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final refController = TextEditingController();
    String selectedMethod = 'UPI';
    final double alreadyReceived = member.totalReceivedAmount;
    final double pendingAmount = member.pendingAmount;
    final double finalAmount = alreadyReceived + pendingAmount;
    bool isSubmitting = false;

    amountController.text = pendingAmount > 0 ? pendingAmount.toStringAsFixed(0) : '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Receive Payment', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: isSubmitting ? null : () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppTheme.surfaceGray, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(plan?.title ?? 'Gold Membership', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                                Text('Active', style: GoogleFonts.inter(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Final Amount', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                                Text('Received', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                                Text('Pending', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('₹ ${finalAmount.toStringAsFixed(0)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                                Text('₹ ${alreadyReceived.toStringAsFixed(0)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.green)),
                                Text('₹ ${pendingAmount.toStringAsFixed(0)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: Colors.red)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text('Receive Amount *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: amountController,
                        keyboardType: TextInputType.number,
                        enabled: !isSubmitting,
                        decoration: const InputDecoration(hintText: 'Enter amount', prefixText: '₹ '),
                      ),
                      const SizedBox(height: 16),
                      Text('Payment Method *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: selectedMethod,
                        items: ['UPI', 'Cash', 'Card', 'Bank Transfer', 'Cheque'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                        onChanged: isSubmitting ? null : (val) {
                          if (val != null) setSheetState(() => selectedMethod = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Reference No. (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: refController,
                        enabled: !isSubmitting,
                        decoration: const InputDecoration(hintText: 'e.g. TXN123456789'),
                      ),
                      const SizedBox(height: 16),
                      Text('Notes (Optional)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: notesController,
                        enabled: !isSubmitting,
                        decoration: const InputDecoration(hintText: 'Add notes'),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: isSubmitting ? null : () async {
                          final enteredAmount = double.tryParse(amountController.text) ?? 0.0;
                          if (enteredAmount <= 0) return;
                          
                          setSheetState(() => isSubmitting = true);

                          try {
                            await membersVm.recordPayment(
                              memberId: member.id,
                              amount: enteredAmount,
                              paymentMethod: selectedMethod,
                              category: 'Membership',
                              notes: notesController.text.trim().isNotEmpty ? notesController.text.trim() : 'Received Payment',
                            );
                            
                            // Close bottom sheet cleanly
                            if (Navigator.canPop(sheetContext)) {
                              Navigator.pop(sheetContext);
                            }

                            final double remaining = (pendingAmount - enteredAmount).clamp(0.0, double.infinity);
                            
                            if (mounted) {
                              PaymentResultScreen.show(
                                context,
                                isSuccess: true,
                                title: 'Payment Received Successfully!',
                                message: 'Payment of ₹${NumberFormat('#,##,###').format(enteredAmount)} has been credited to ${member.name}.',
                                memberName: member.name,
                                memberCode: member.memberCode,
                                amount: enteredAmount,
                                paymentMethod: selectedMethod,
                                planName: plan?.title ?? 'Membership Plan',
                                referenceNo: refController.text.trim().isNotEmpty ? refController.text.trim() : null,
                                remainingPending: remaining,
                              );
                            }
                          } catch (e) {
                            if (Navigator.canPop(sheetContext)) {
                              Navigator.pop(sheetContext);
                            }
                            if (mounted) {
                              PaymentResultScreen.show(
                                context,
                                isSuccess: false,
                                title: 'Payment Failed',
                                message: 'Unable to record payment. Please check your connection and try again.',
                                memberName: member.name,
                                memberCode: member.memberCode,
                                amount: enteredAmount,
                                paymentMethod: selectedMethod,
                                errorMessage: e.toString(),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text('Receive Payment', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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

  void _showRenewMembershipBottomSheet(MembersViewModel membersVm, Member member) {
    final membershipVm = Provider.of<MembershipViewModel>(context, listen: false);
    final plans = membershipVm.plans;
    MembershipPlan? selectedPlan = plans.isNotEmpty ? plans.first : null;
    final discountController = TextEditingController(text: '0');
    final receiveController = TextEditingController();
    final notesController = TextEditingController();
    String selectedMethod = 'UPI';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final double planPrice = selectedPlan?.price ?? 3000.0;
            final double discountVal = double.tryParse(discountController.text) ?? 0.0;
            final double finalAmount = (planPrice - discountVal).clamp(0.0, double.infinity);

            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(sheetContext).viewInsets.bottom + 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Renew Membership', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: isSubmitting ? null : () => Navigator.pop(sheetContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Select New Plan *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<MembershipPlan>(
                        value: plans.any((p) => p.id == selectedPlan?.id)
                            ? plans.firstWhere((p) => p.id == selectedPlan?.id)
                            : null,
                        items: plans.map((p) => DropdownMenuItem(value: p, child: Text('${p.title} (${p.durationMonths} Months)'))).toList(),
                        onChanged: isSubmitting ? null : (val) {
                          setSheetState(() => selectedPlan = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Plan Price', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                                const SizedBox(height: 4),
                                Text('₹ ${planPrice.toStringAsFixed(0)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Discount (₹)', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: discountController,
                                  keyboardType: TextInputType.number,
                                  enabled: !isSubmitting,
                                  onChanged: (_) => setSheetState(() {}),
                                  decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Final Amount', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                          Text('₹ ${finalAmount.toStringAsFixed(0)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primary)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Receive Today *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: receiveController,
                        keyboardType: TextInputType.number,
                        enabled: !isSubmitting,
                        decoration: const InputDecoration(hintText: 'Enter payment received today', prefixText: '₹ '),
                      ),
                      const SizedBox(height: 16),
                      Text('Payment Method *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: selectedMethod,
                        items: ['UPI', 'Cash', 'Card', 'Bank Transfer', 'Cheque'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                        onChanged: isSubmitting ? null : (val) {
                          if (val != null) setSheetState(() => selectedMethod = val);
                        },
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: isSubmitting ? null : () async {
                          if (selectedPlan == null) return;
                          final receiveToday = double.tryParse(receiveController.text) ?? 0.0;
                          
                          setSheetState(() => isSubmitting = true);

                          try {
                            final updated = member.copyWith(
                              membershipPlanId: selectedPlan!.id,
                              discountAmount: discountVal,
                              totalReceivedAmount: receiveToday,
                              pendingAmount: finalAmount - receiveToday,
                              paymentStatus: (finalAmount - receiveToday) <= 0 ? 'Paid' : 'Partial',
                            );
                            await membersVm.updateMember(updated, paymentMethod: selectedMethod, transactionAmount: receiveToday, isRenewal: true);
                            
                            // Close bottom sheet cleanly
                            if (Navigator.canPop(sheetContext)) {
                              Navigator.pop(sheetContext);
                            }

                            final double remaining = (finalAmount - receiveToday).clamp(0.0, double.infinity);
                            
                            if (mounted) {
                              PaymentResultScreen.show(
                                context,
                                isSuccess: true,
                                title: 'Membership Renewed Successfully!',
                                message: '${member.name}\'s membership has been renewed for ${selectedPlan!.title}.',
                                memberName: member.name,
                                memberCode: member.memberCode,
                                amount: receiveToday,
                                paymentMethod: selectedMethod,
                                planName: selectedPlan!.title,
                                remainingPending: remaining,
                              );
                            }
                          } catch (e) {
                            if (Navigator.canPop(sheetContext)) {
                              Navigator.pop(sheetContext);
                            }
                            if (mounted) {
                              PaymentResultScreen.show(
                                context,
                                isSuccess: false,
                                title: 'Renewal Failed',
                                message: 'Unable to renew membership. Please try again.',
                                memberName: member.name,
                                memberCode: member.memberCode,
                                amount: receiveToday,
                                paymentMethod: selectedMethod,
                                errorMessage: e.toString(),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text('Renew Membership', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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

  void _showAssignWorkoutBottomSheet(MembersViewModel membersVm, Member member) {
    final workoutVm = Provider.of<WorkoutViewModel>(context, listen: false);
    final workouts = workoutVm.workouts;
    WorkoutPlan? selectedWorkout = workouts.isNotEmpty ? workouts.first : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Assign Workout', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Select Workout Plan *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<WorkoutPlan>(
                    value: selectedWorkout,
                    items: workouts.map((w) => DropdownMenuItem(value: w, child: Text(w.title))).toList(),
                    onChanged: (val) {
                      setSheetState(() => selectedWorkout = val);
                    },
                  ),
                  if (selectedWorkout != null) ...[
                    const SizedBox(height: 20),
                    Text('Plan Details', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppTheme.surfaceGray, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          _buildDetailIconRow(Icons.timer_outlined, 'Duration', '8 Weeks'),
                          const Divider(height: 16),
                          _buildDetailIconRow(Icons.emoji_events_outlined, 'Focus', selectedWorkout!.goal),
                          const Divider(height: 16),
                          _buildDetailIconRow(Icons.bar_chart_rounded, 'Level', selectedWorkout!.difficulty),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      if (selectedWorkout == null) return;
                      Navigator.pop(context);
                      await membersVm.assignWorkout(member.id, selectedWorkout!.id);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Assign Workout', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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

  void _showAssignDietBottomSheet(MembersViewModel membersVm, Member member) {
    final dietVm = Provider.of<DietViewModel>(context, listen: false);
    final diets = dietVm.diets;
    DietPlan? selectedDiet = diets.isNotEmpty ? diets.first : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Assign Diet', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Select Diet Plan *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<DietPlan>(
                    value: selectedDiet,
                    items: diets.map((d) => DropdownMenuItem(value: d, child: Text(d.title))).toList(),
                    onChanged: (val) {
                      setSheetState(() => selectedDiet = val);
                    },
                  ),
                  if (selectedDiet != null) ...[
                    const SizedBox(height: 20),
                    Text('Plan Details', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppTheme.surfaceGray, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          _buildDetailIconRow(Icons.restaurant_menu_rounded, 'Type', 'High Protein'),
                          const Divider(height: 16),
                          _buildDetailIconRow(Icons.local_fire_department_outlined, 'Calories', '2000 kcal / Day'),
                          const Divider(height: 16),
                          _buildDetailIconRow(Icons.emoji_events_outlined, 'Goal', selectedDiet!.goal),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () async {
                      if (selectedDiet == null) return;
                      Navigator.pop(context);
                      await membersVm.assignDiet(member.id, selectedDiet!.id);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Assign Diet', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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

  Widget _buildDetailIconRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
        const Spacer(),
        Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // --- Sub tabs views ---

  Widget _buildInfoTab(MembersViewModel membersVm, Member member, MembershipPlan? assignedPlan) {
    final double planPrice = assignedPlan?.price ?? 3000.0;
    final double alreadyReceived = member.totalReceivedAmount;
    final double pendingAmount = member.pendingAmount;
    final double finalAmount = alreadyReceived + pendingAmount;
    final int percentPaid = finalAmount > 0 ? ((alreadyReceived / finalAmount) * 100).toInt() : 0;

    String expiryDateStr = '—';
    String remainingDaysStr = '—';
    Color remainingColor = AppTheme.textSecondary;

    final exp = member.extraFields['expiryDate'] as String?;
    if (exp != null && exp.isNotEmpty) {
      try {
        final expiryDate = DateTime.parse(exp);
        expiryDateStr = DateFormat('dd MMM yyyy').format(expiryDate);
        
        final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
        final expZero = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
        final diff = expZero.difference(today).inDays;
        
        if (diff < 0) {
          remainingDaysStr = 'Expired';
          remainingColor = AppTheme.danger;
        } else {
          remainingDaysStr = '$diff Days';
          if (diff <= 7) {
            remainingColor = AppTheme.danger;
          } else if (diff <= 15) {
            remainingColor = Colors.orange;
          } else {
            remainingColor = Colors.green;
          }
        }
      } catch (_) {
        expiryDateStr = exp;
      }
    }

    // Health & Measurements extraction
    final Map<String, dynamic> extra = member.extraFields;
    final Map<String, dynamic> measurements = (extra['measurements'] is Map<String, dynamic>)
        ? extra['measurements'] as Map<String, dynamic>
        : {};

    final String dob = (extra['dob']?.toString().isNotEmpty == true) ? extra['dob'].toString().split('T')[0] : '—';
    final String gender = extra['gender']?.toString() ?? '—';
    final String bloodGroup = extra['bloodGroup']?.toString() ?? extra['blood_group']?.toString() ?? '—';

    final String hVal = measurements['height']?.toString() ?? extra['height']?.toString() ?? '';
    final String wVal = measurements['weight']?.toString() ?? extra['weight']?.toString() ?? '';
    final String cVal = measurements['chest']?.toString() ?? extra['chest']?.toString() ?? '';
    final String waVal = measurements['waist']?.toString() ?? extra['waist']?.toString() ?? '';
    final String bVal = measurements['biceps']?.toString() ?? extra['biceps']?.toString() ?? '';
    final String hpVal = measurements['hip']?.toString() ?? extra['hip']?.toString() ?? '';

    final String height = hVal.isNotEmpty ? '$hVal cm' : '—';
    final String weight = wVal.isNotEmpty ? '$wVal kg' : '—';
    final String chest = cVal.isNotEmpty ? '$cVal in' : '—';
    final String waist = waVal.isNotEmpty ? '$waVal in' : '—';
    final String biceps = bVal.isNotEmpty ? '$bVal in' : '—';
    final String hip = hpVal.isNotEmpty ? '$hpVal in' : '—';

    final hasInvitation = _invitation != null;
    final isActivated = hasInvitation && (_invitation!['code_used'] == true);
    final invitationCode = _invitation?['invitation_code'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top profile Section
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage: member.avatar.isNotEmpty ? NetworkImage(member.avatar) : null,
                  backgroundColor: AppTheme.primaryLight,
                  child: member.avatar.isEmpty ? Text(member.name[0], style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold)) : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt_outlined, size: 14, color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          'Active Member',
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppTheme.primaryLight, borderRadius: BorderRadius.circular(4)),
                        child: Text(
                          'MEM-000124',
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.phone_outlined, size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(member.phone, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.email_outlined, size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(member.email, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined, size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text('Joined on ${member.joinDate}', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 2. Current Membership Card
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(assignedPlan?.title ?? 'Gold Membership', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                    child: Text('Active', style: GoogleFonts.inter(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 10)),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(assignedPlan != null 
                  ? '${assignedPlan.durationDays} Days Plan' 
                  : '30 Days Plan', 
                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Start Date', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text(member.joinDate, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('End Date', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text(expiryDateStr, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Remaining', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text(remainingDaysStr, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: remainingColor)),
                    ],
                  ),
                ],
              ),
              const Divider(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Final Amount', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text('₹ ${finalAmount.toStringAsFixed(0)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Received', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text('₹ ${alreadyReceived.toStringAsFixed(0)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Pending', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text('₹ ${pendingAmount.toStringAsFixed(0)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$percentPaid% Paid', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: finalAmount > 0 ? (alreadyReceived / finalAmount) : 0,
                  backgroundColor: AppTheme.surfaceGray,
                  color: AppTheme.primary,
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 3. Quick Actions
        Text('QUICK ACTIONS', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                icon: Icons.payments_outlined,
                color: Colors.green,
                label: 'Receive\nPayment',
                onTap: () => _showReceivePaymentBottomSheet(membersVm, member, assignedPlan),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildActionCard(
                icon: Icons.autorenew_rounded,
                color: Colors.deepPurple,
                label: 'Renew\nMembership',
                onTap: () => _showRenewMembershipBottomSheet(membersVm, member),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildActionCard(
                icon: Icons.fitness_center_rounded,
                color: Colors.blue,
                label: 'Assign\nWorkout',
                onTap: () => _showAssignWorkoutBottomSheet(membersVm, member),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildActionCard(
                icon: Icons.restaurant_rounded,
                color: Colors.orange,
                label: 'Assign\nDiet',
                onTap: () => _showAssignDietBottomSheet(membersVm, member),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 3.5 Personal Trainer & Commission
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('PERSONAL TRAINER & COMMISSION', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
            GestureDetector(
              onTap: () => _showEditTrainerBottomSheet(membersVm),
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
        const SizedBox(height: 10),
        CustomCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Consumer<StaffViewModel>(
            builder: (context, staffVm, child) {
              final trainer = staffVm.allStaff.where((s) => s.id == member.ptTrainer).firstOrNull;
              final trainerName = member.ptMember && trainer != null ? trainer.name : 'None / Unassigned';
              return Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_outline_rounded, color: AppTheme.primary, size: 18),
                          const SizedBox(width: 8),
                          Text('Assigned PT', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                        ],
                      ),
                      Text(trainerName, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                    ],
                  ),
                  if (member.ptMember) ...[
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.percent_rounded, color: AppTheme.primary, size: 18),
                            const SizedBox(width: 8),
                            Text('Commission Rate', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                          ],
                        ),
                        Text('${_activeCommissionPercentage.toStringAsFixed(1)} %', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // 4. Member Information
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('MEMBER INFO', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
            GestureDetector(
              onTap: () {},
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
        const SizedBox(height: 10),
        CustomCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              _buildRowInfo(Icons.cake_outlined, 'Date of Birth', dob),
              const Divider(height: 1),
              _buildRowInfo(Icons.wc_outlined, 'Gender', gender),
              const Divider(height: 1),
              _buildRowInfo(Icons.height_rounded, 'Height', height),
              const Divider(height: 1),
              _buildRowInfo(Icons.monitor_weight_outlined, 'Weight', weight),
              const Divider(height: 1),
              _buildRowInfo(Icons.bloodtype_outlined, 'Blood Group', bloodGroup),
              const Divider(height: 1),
              _buildRowInfo(Icons.phone_outlined, 'Phone', member.phone),
              const Divider(height: 1),
              _buildRowInfo(Icons.email_outlined, 'Email', member.email),
              const Divider(height: 1),
              _buildRowInfo(Icons.location_on_outlined, 'Address', member.extraFields['address'] ?? 'Indore, Madhya Pradesh'),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 5. Body Measurements Section
        Text('BODY MEASUREMENTS', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
        const SizedBox(height: 10),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildMeasurementTile(Icons.height_rounded, 'Height', height)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMeasurementTile(Icons.monitor_weight_outlined, 'Weight', weight)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMeasurementTile(Icons.fitness_center_rounded, 'Chest', chest)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildMeasurementTile(Icons.straighten_rounded, 'Waist', waist)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMeasurementTile(Icons.accessibility_new_rounded, 'Biceps', biceps)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildMeasurementTile(Icons.attribution_rounded, 'Hip', hip)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 5. Account Status
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ACCOUNT STATUS', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
          ],
        ),
        const SizedBox(height: 10),
        CustomCard(
          padding: const EdgeInsets.all(16),
          child: isActivated
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
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
                      'Member has successfully joined the gym.',
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Registered Mobile Number',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      member.phone,
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Registration Date',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _invitation!['activated_at'] != null
                          ? DateFormat('dd MMM yyyy').format(DateTime.parse(_invitation!['activated_at']))
                          : 'N/A',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
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
                      onPressed: () => _confirmUnlink(membersVm, member),
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
                            color: Colors.orange.withOpacity(0.1),
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
                                onTap: () => _shareInvitationCode(invitationCode, member.phone),
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
                      Text(member.phone, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 16),
                      Text(
                        'Waiting for the member to complete registration.',
                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                      ),
                    ] else ...[
                      Text(
                        'No active invitation found. Create one now to link this member profile.',
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
                        onPressed: () => _generateNewCode(membersVm, member),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildRowInfo(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
          const Spacer(),
          Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildActionCard({required IconData icon, required Color color, required String label, required VoidCallback onTap}) {
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
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
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

  // History Tab
  Widget _buildHistoryTab(MembersViewModel membersVm, Member member) {
    final transactions = membersVm.getMemberTransactions(member.id);

    String expiryDateStr = '—';
    final exp = member.extraFields['expiryDate'] as String?;
    if (exp != null && exp.isNotEmpty) {
      try {
        final expiryDate = DateTime.parse(exp);
        expiryDateStr = DateFormat('dd MMM yyyy').format(expiryDate);
      } catch (_) {
        expiryDateStr = exp;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Membership History', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        CustomCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.card_membership_rounded, color: AppTheme.primary),
                title: Text(membersVm.getMemberPlan(member.membershipPlanId)?.title ?? 'Gold Membership', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('Start: ${member.joinDate} • End: $expiryDateStr', style: GoogleFonts.inter(fontSize: 11)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                  child: Text('Active', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green)),
                ),
                onTap: () => _showMembershipDetailsBottomSheet(membersVm, member, membersVm.getMemberPlan(member.membershipPlanId)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Payment Transactions', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        CustomCard(
          padding: EdgeInsets.zero,
          child: transactions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Center(child: Text('No transaction history.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary))),
                )
              : Column(
                  children: List.generate(transactions.length, (idx) {
                    final tx = transactions[idx];
                    final isRevenue = tx.type == 'Revenue';
                    return Column(
                      children: [
                        ListTile(
                          leading: Icon(
                            isRevenue ? Icons.arrow_circle_down_rounded : Icons.arrow_circle_up_rounded,
                            color: isRevenue ? Colors.green : Colors.redAccent,
                          ),
                          title: Text(tx.title, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text('${tx.date} • ${tx.paymentMethod}', style: GoogleFonts.inter(fontSize: 11)),
                          trailing: Text(
                            '${isRevenue ? '+' : '-'} ₹${tx.amount.toStringAsFixed(0)}',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: isRevenue ? Colors.green : Colors.redAccent),
                          ),
                        ),
                        if (idx < transactions.length - 1) const Divider(height: 1),
                      ],
                    );
                  }),
                ),
        ),
      ],
    );
  }

  void _showMembershipDetailsBottomSheet(MembersViewModel membersVm, Member member, MembershipPlan? plan) {
    final double planPrice = plan?.price ?? 3000.0;
    final double finalAmount = member.totalReceivedAmount + member.pendingAmount;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Membership Details', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              _buildDetailRow('Membership Name', plan?.title ?? 'Gold Membership'),
              const Divider(height: 16),
              _buildDetailRow('Duration', plan != null ? '${plan.durationDays} Days' : '30 Days'),
              const Divider(height: 16),
              _buildDetailRow('Start Date', member.joinDate),
              const Divider(height: 16),
              _buildDetailRow('End Date', () {
                String expStr = '—';
                final exp = member.extraFields['expiryDate'] as String?;
                if (exp != null && exp.isNotEmpty) {
                  try {
                    final parsed = DateTime.parse(exp);
                    expStr = DateFormat('dd MMM yyyy').format(parsed);
                  } catch (_) {
                    expStr = exp;
                  }
                }
                return expStr;
              }()),
              const Divider(height: 16),
              _buildDetailRow('Status', 'Active'),
              const Divider(height: 16),
              _buildDetailRow('Final Amount', '₹ ${finalAmount.toStringAsFixed(0)}'),
              const Divider(height: 16),
              _buildDetailRow('Discount', '₹ ${(planPrice - finalAmount).clamp(0.0, double.infinity).toStringAsFixed(0)}'),
              const Divider(height: 16),
              _buildDetailRow('Received', '₹ ${member.totalReceivedAmount.toStringAsFixed(0)}'),
              const Divider(height: 16),
              _buildDetailRow('Pending', '₹ ${member.pendingAmount.toStringAsFixed(0)}'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
      },
    );
  }

  // Notes Tab
  Widget _buildNotesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Owner Notes', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _ownerNotesController,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Enter owner notes'),
        ),
        const SizedBox(height: 20),
        Text('Trainer Notes', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _trainerNotesController,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Enter trainer notes'),
        ),
        const SizedBox(height: 20),
        Text('Private Notes', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: _privateNotesController,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Enter private notes'),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Notes updated successfully!'), backgroundColor: AppTheme.success),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text('Save Notes', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // More Tab
  Widget _buildMoreTab() {
    final items = [
      {'title': 'Attendance', 'icon': Icons.co_present_rounded},
      {'title': 'Body Measurements', 'icon': Icons.scale_rounded},
      {'title': 'Progress Photos', 'icon': Icons.photo_library_rounded},
      {'title': 'Documents', 'icon': Icons.folder_shared_rounded},
      {'title': 'Medical History', 'icon': Icons.medical_services_rounded},
      {'title': 'Activity Log', 'icon': Icons.history_edu_rounded},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('More Actions', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        CustomCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: List.generate(items.length, (idx) {
              final item = items[idx];
              return Column(
                children: [
                  ListTile(
                    leading: Icon(item['icon'] as IconData, color: AppTheme.primary),
                    title: Text(item['title'] as String, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppTheme.surfaceGray, borderRadius: BorderRadius.circular(8)),
                      child: Text('Coming Soon', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                    ),
                  ),
                  if (idx < items.length - 1) const Divider(height: 1),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final membersVm = Provider.of<MembersViewModel>(context);
    final member = membersVm.allMembers.firstWhere((m) => m.id == widget.member.id, orElse: () => widget.member);
    final assignedPlan = membersVm.getMemberPlan(member.membershipPlanId);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text('Member Profile', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _currentTab == 0
                    ? _buildInfoTab(membersVm, member, assignedPlan)
                    : _currentTab == 1
                        ? _buildHistoryTab(membersVm, member)
                        : _currentTab == 2
                            ? _buildNotesTab()
                            : _buildMoreTab(),
              ),
            ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentTab,
          onTap: (idx) {
            setState(() {
              _currentTab = idx;
            });
          },
          backgroundColor: Colors.white,
          selectedItemColor: AppTheme.primary,
          unselectedItemColor: AppTheme.textSecondary,
          selectedLabelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11),
          unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.info_outline_rounded), label: 'Info'),
            BottomNavigationBarItem(icon: Icon(Icons.history_toggle_off_rounded), label: 'History'),
            BottomNavigationBarItem(icon: Icon(Icons.sticky_note_2_outlined), label: 'Notes'),
            BottomNavigationBarItem(icon: Icon(Icons.more_horiz_rounded), label: 'More'),
          ],
        ),
      ),
    );
  }

  Widget _buildMeasurementTile(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGray.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppTheme.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  bool _isLoading = false;
}
