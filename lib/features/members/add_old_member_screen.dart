import 'dart:math';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../members/members_viewmodel.dart';
import '../membership/membership_viewmodel.dart';
import '../staff/staff_viewmodel.dart';
import '../authentication/auth_viewmodel.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/image_security_service.dart';
import '../../core/models/member.dart';
import '../../core/models/membership_plan.dart';
import 'member_add_success_screen.dart';
import '../subscription/subscription_limit_screen.dart';
import '../../core/repository/gym_repository.dart';

class AddOldMemberScreen extends StatefulWidget {
  const AddOldMemberScreen({super.key});

  @override
  State<AddOldMemberScreen> createState() => _AddOldMemberScreenState();
}

class _AddOldMemberScreenState extends State<AddOldMemberScreen> {
  // Image upload
  final ImagePicker _imagePicker = ImagePicker();
  String _avatarUrl = '';
  bool _isUploadingPhoto = false;
  double _photoUploadProgress = 0.0;

  // Basic Info
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _addressController = TextEditingController();
  bool _showAltPhone = false;
  String _selectedGender = 'Male';

  // Membership
  MembershipPlan? _selectedPlan;
  DateTime? _joiningDate;
  String _selectedDuration = '';
  DateTime? _expiryDate;
  final _feesController = TextEditingController();
  final _discountController = TextEditingController();

  // Payment (Old Data)
  String _oldPaymentStatus = 'full'; // 'full' or 'partial'
  final _amountReceivedController = TextEditingController();
  final _remainingController = TextEditingController(text: '0');
  DateTime? _paymentReceiveDate;
  String _paymentMethod = 'Cash';

  // PT (No commission)
  bool _hasPersonalTrainer = false;
  String? _selectedTrainerId;

  // Notes
  final _notesController = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _joiningDate = DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _addressController.dispose();
    _feesController.dispose();
    _discountController.dispose();
    _amountReceivedController.dispose();
    _remainingController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _finalPayable {
    final fees = double.tryParse(_feesController.text) ?? 0.0;
    final discount = double.tryParse(_discountController.text) ?? 0.0;
    return (fees - discount).clamp(0.0, double.infinity);
  }

  void _recalculateExpiry() {
    if (_selectedPlan != null && _joiningDate != null) {
      _expiryDate = _joiningDate!.add(Duration(days: _selectedPlan!.durationDays));
      _feesController.text = _selectedPlan!.price.toStringAsFixed(0);
      _selectedDuration = '${_selectedPlan!.durationMonths} Month${_selectedPlan!.durationMonths > 1 ? 's' : ''}';
      _recalculateRemaining();
    }
  }

  void _recalculateRemaining() {
    if (_oldPaymentStatus == 'full') {
      _amountReceivedController.text = _finalPayable.toStringAsFixed(0);
      _remainingController.text = '0';
    } else {
      final received = double.tryParse(_amountReceivedController.text) ?? 0.0;
      _remainingController.text = (_finalPayable - received).clamp(0.0, double.infinity).toStringAsFixed(0);
    }
  }

  Future<void> _pickAndUploadPhoto(ImageSource source) async {
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (file == null) return;

      setState(() {
        _isUploadingPhoto = true;
        _photoUploadProgress = 0.2;
      });

      final bytes = await file.readAsBytes();
      setState(() => _photoUploadProgress = 0.5);

      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? 'default_gym';

      setState(() => _photoUploadProgress = 0.7);

      final publicUrl = await ImageSecurityService.uploadSecureImage(
        bucket: 'avatars',
        directoryPath: '$gymId/members',
        bytes: bytes,
      );

      setState(() {
        _avatarUrl = publicUrl;
        _isUploadingPhoto = false;
        _photoUploadProgress = 0.0;
      });
    } catch (e) {
      setState(() {
        _isUploadingPhoto = false;
        _photoUploadProgress = 0.0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload photo: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  String _generateUUIDv4() {
    final rnd = Random.secure();
    final bytes = List.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final chars = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).toList();
    return '${chars[0]}${chars[1]}${chars[2]}${chars[3]}-'
        '${chars[4]}${chars[5]}-'
        '${chars[6]}${chars[7]}-'
        '${chars[8]}${chars[9]}-'
        '${chars[10]}${chars[11]}${chars[12]}${chars[13]}${chars[14]}${chars[15]}';
  }

  Future<void> _saveOldMember() async {
    // Validate required fields
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      _showError('Please enter member name');
      return;
    }
    if (phone.isEmpty) {
      _showError('Please enter contact number');
      return;
    }
    if (_selectedPlan == null) {
      _showError('Please select a membership plan');
      return;
    }
    if (_joiningDate == null) {
      _showError('Please select a joining date');
      return;
    }

    setState(() => _isSaving = true);

    // Check subscription limits
    try {
      final gymRepo = Provider.of<GymRepository>(context, listen: false);
      await gymRepo.checkSubscriptionLimit('member');
    } catch (e) {
      if (e.toString().contains('limit_reached:')) {
        final message = e.toString().split('limit_reached:')[1];
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SubscriptionLimitScreen(
              limitType: 'member',
              message: message,
            ),
          ),
        );
        setState(() => _isSaving = false);
        return;
      }
    }

    final id = _generateUUIDv4();
    final paidAmount = _oldPaymentStatus == 'full'
        ? _finalPayable
        : (double.tryParse(_amountReceivedController.text) ?? 0.0);
    final pendingAmount = _oldPaymentStatus == 'full'
        ? 0.0
        : (_finalPayable - paidAmount).clamp(0.0, double.infinity);

    // Determine member status based on expiry
    String memberStatus = 'Active';
    if (_expiryDate != null && _expiryDate!.isBefore(DateTime.now())) {
      memberStatus = 'Inactive';
    }

    final Map<String, dynamic> extra = {
      'goal': 'General Fitness',
      'is_old_member': true,
      'old_payment_status': _oldPaymentStatus,
      'old_amount_received': paidAmount,
      'old_payment_date': _paymentReceiveDate?.toIso8601String() ?? '',
      'old_payment_method': _paymentMethod,
      'altPhone': _altPhoneController.text.trim(),
      'address': _addressController.text.trim(),
      'gender': _selectedGender,
      'fees': double.tryParse(_feesController.text) ?? 0.0,
      'discount': double.tryParse(_discountController.text) ?? 0.0,
      'paid': paidAmount,
      'paymentMethod': _paymentMethod,
      'expiryDate': _expiryDate?.toIso8601String() ?? '',
    };

    final newMember = Member(
      id: id,
      name: name,
      email: '',
      phone: phone,
      avatar: _avatarUrl,
      joinDate: _joiningDate != null
          ? DateFormat('dd MMM yyyy').format(_joiningDate!)
          : DateFormat('dd MMM yyyy').format(DateTime.now()),
      status: memberStatus,
      membershipPlanId: _selectedPlan?.id ?? '',
      ptMember: _hasPersonalTrainer,
      ptTrainer: _hasPersonalTrainer ? (_selectedTrainerId ?? '') : '',
      assignedWorkoutId: '',
      assignedDietId: '',
      medicalDetails: 'None',
      notes: _notesController.text,
      pendingAmount: pendingAmount,
      discountAmount: double.tryParse(_discountController.text) ?? 0.0,
      totalReceivedAmount: paidAmount,
      paymentStatus: pendingAmount <= 0 ? 'Paid' : 'Partial',
      extraFields: extra,
    );

    final vm = Provider.of<MembersViewModel>(context, listen: false);

    // Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    try {
      // Save old member with historical payment date
      await vm.saveOldMember(
        newMember,
        paymentMethod: _paymentMethod.isNotEmpty ? _paymentMethod : 'Cash',
        paymentReceiveDate: _paymentReceiveDate ?? _joiningDate,
      );

      String invitationCode = '';
      try {
        invitationCode = await vm.generateInvitation(
          recordId: id,
          name: newMember.name,
          phone: newMember.phone,
        );
      } catch (e) {
        print('Background invitation generation error: $e');
      }

      if (mounted) {
        Navigator.pop(context); // Pop loading spinner
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MemberAddSuccessScreen(
              memberName: newMember.name,
              invitationCode: invitationCode,
              phone: newMember.phone,
            ),
          ),
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
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
    );
  }

  // ─────────────────────────────────────────────
  // REUSABLE WIDGETS
  // ─────────────────────────────────────────────
  Widget _fieldLabel(String label, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
          if (required) Text(' *', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
        ],
      ),
    );
  }

  Widget _datePicker({
    required String hint,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusInput),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null ? hint : DateFormat('dd MMM yyyy').format(value),
                style: GoogleFonts.inter(fontSize: 14, color: value == null ? AppTheme.textMuted : AppTheme.textPrimary),
              ),
            ),
            Icon(Icons.calendar_today_outlined, size: 18, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyField(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceGray,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted),
      ),
    );
  }

  Widget _genderChip(String label, IconData icon) {
    final isSelected = _selectedGender == label;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedGender = label),
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primary : Colors.white,
            border: Border.all(color: isSelected ? AppTheme.primary : AppTheme.border),
            borderRadius: BorderRadius.circular(AppTheme.radiusInput),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? Colors.white : AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final membershipVm = Provider.of<MembershipViewModel>(context);
    final staffVm = Provider.of<StaffViewModel>(context);
    final activePlans = membershipVm.plans.where((p) => p.status == 'Active').toList();
    final trainerList = staffVm.allStaff.where((s) =>
      s.role == 'Trainer' || s.role == 'Personal Trainer'
    ).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Import Old Member', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Old Member Info Banner
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.history_rounded, size: 20, color: Colors.orange.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Import pre-existing member data. No finance entries or PT commissions will be created for this data.',
                      style: GoogleFonts.inter(fontSize: 11.5, color: Colors.orange.shade800, fontWeight: FontWeight.w500, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable form
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ══════════════════════════════════════
                    // SECTION 1: BASIC INFO
                    // ══════════════════════════════════════
                    _sectionHeader('Basic Information', 'Personal & Contact Details', Icons.person_outline),

                    // Avatar
                    Center(
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: _showPhotoPickerBottomSheet,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 44,
                                  backgroundColor: AppTheme.primaryLight,
                                  backgroundImage: _avatarUrl.isNotEmpty ? NetworkImage(_avatarUrl) : null,
                                  child: _avatarUrl.isEmpty && !_isUploadingPhoto
                                      ? Icon(Icons.person, size: 44, color: AppTheme.primary)
                                      : null,
                                ),
                                if (_isUploadingPhoto)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.4),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          value: _photoUploadProgress,
                                          color: Colors.white,
                                          strokeWidth: 3,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 2),
                                    ),
                                    child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _avatarUrl.isEmpty ? 'Tap to add photo' : 'Tap to change photo',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Full Name
                    _fieldLabel('Full Name', required: true),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(hintText: 'Enter full name'),
                    ),
                    const SizedBox(height: 16),

                    // Contact Number
                    _fieldLabel('Contact Number', required: true),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppTheme.border),
                            borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                          ),
                          child: Row(
                            children: [
                              Text('+91', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                              const SizedBox(width: 4),
                              Icon(Icons.keyboard_arrow_down, size: 16, color: AppTheme.textMuted),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(hintText: 'Enter mobile number'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Alternate Number
                    if (!_showAltPhone) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _showAltPhone = true),
                          icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: AppTheme.primary),
                          label: Text(
                            'Add Alternate Number',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary),
                          ),
                        ),
                      ),
                    ] else ...[
                      _fieldLabel('Alternate Number'),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTheme.border),
                              borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                            ),
                            child: Row(
                              children: [
                                Text('+91', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500)),
                                const SizedBox(width: 4),
                                Icon(Icons.keyboard_arrow_down, size: 16, color: AppTheme.textMuted),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _altPhoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(hintText: 'Enter alternate number'),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                            onPressed: () {
                              _altPhoneController.clear();
                              setState(() => _showAltPhone = false);
                            },
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Address
                    _fieldLabel('Address'),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(hintText: 'Enter full address'),
                    ),
                    const SizedBox(height: 16),

                    // Gender
                    _fieldLabel('Gender'),
                    Row(
                      children: [
                        _genderChip('Male', Icons.male),
                        const SizedBox(width: 12),
                        _genderChip('Female', Icons.female),
                      ],
                    ),

                    // ══════════════════════════════════════
                    // SECTION 2: MEMBERSHIP
                    // ══════════════════════════════════════
                    _sectionHeader('Membership Details', 'Plan & Duration', Icons.card_membership_rounded),

                    // Membership Plan
                    _fieldLabel('Membership Plan', required: true),
                    DropdownButtonFormField<MembershipPlan>(
                      initialValue: activePlans.any((p) => p.id == _selectedPlan?.id)
                          ? activePlans.firstWhere((p) => p.id == _selectedPlan?.id)
                          : null,
                      hint: Text('Select membership plan', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
                      isExpanded: true,
                      items: activePlans.map((p) {
                        return DropdownMenuItem(
                          value: p,
                          child: Text('${p.title} — ₹${p.price.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 14)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedPlan = val;
                            _recalculateExpiry();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Joining Date (Past)
                    _fieldLabel('Date of Joining (When Membership Was Taken)', required: true),
                    _datePicker(
                      hint: 'Select date',
                      value: _joiningDate,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _joiningDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            _joiningDate = picked;
                            _recalculateExpiry();
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Duration + Expiry
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Duration'),
                              _readOnlyField(_selectedDuration.isNotEmpty ? _selectedDuration : 'Auto calculated'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Expiry Date'),
                              _readOnlyField(_expiryDate == null ? 'Auto calculated' : DateFormat('dd MMM yyyy').format(_expiryDate!)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Fees + Discount
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Membership Fees (₹)'),
                              TextFormField(
                                controller: _feesController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(hintText: 'Enter amount'),
                                onChanged: (_) => setState(() => _recalculateRemaining()),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _fieldLabel('Discount (₹)'),
                              TextFormField(
                                controller: _discountController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(hintText: '0'),
                                onChanged: (_) => setState(() => _recalculateRemaining()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ══════════════════════════════════════
                    // SECTION 3: PAYMENT STATUS (OLD DATA)
                    // ══════════════════════════════════════
                    _sectionHeader('Payment Status', 'Old Data — No finance entry will be created', Icons.payments_outlined),

                    // Full / Partial Toggle
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _oldPaymentStatus = 'full';
                                _recalculateRemaining();
                              });
                            },
                            borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _oldPaymentStatus == 'full' ? AppTheme.success.withValues(alpha: 0.1) : Colors.white,
                                border: Border.all(
                                  color: _oldPaymentStatus == 'full' ? AppTheme.success : AppTheme.border,
                                  width: _oldPaymentStatus == 'full' ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 18,
                                    color: _oldPaymentStatus == 'full' ? AppTheme.success : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Full Received',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _oldPaymentStatus == 'full' ? AppTheme.success : AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _oldPaymentStatus = 'partial';
                                _amountReceivedController.clear();
                                _recalculateRemaining();
                              });
                            },
                            borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: _oldPaymentStatus == 'partial' ? Colors.orange.shade50 : Colors.white,
                                border: Border.all(
                                  color: _oldPaymentStatus == 'partial' ? Colors.orange : AppTheme.border,
                                  width: _oldPaymentStatus == 'partial' ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: _oldPaymentStatus == 'partial' ? Colors.orange : AppTheme.textMuted,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Not Fully Received',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _oldPaymentStatus == 'partial' ? Colors.orange.shade800 : AppTheme.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (_oldPaymentStatus == 'full') ...[
                      // Full payment summary
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.success.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.success.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle, size: 20, color: AppTheme.success),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Full payment of ₹${_finalPayable.toStringAsFixed(0)} has been received. No pending amount.',
                                style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.success, fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Partial payment fields
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _fieldLabel('Amount Received (₹)'),
                                TextFormField(
                                  controller: _amountReceivedController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(hintText: 'Enter amount'),
                                  onChanged: (_) => setState(() => _recalculateRemaining()),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _fieldLabel('Remaining (₹)'),
                                _readOnlyField('₹${_remainingController.text}'),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Payment Receive Date
                    _fieldLabel('Payment Receive Date (Reference)'),
                    _datePicker(
                      hint: 'Select date (optional)',
                      value: _paymentReceiveDate,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _paymentReceiveDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() => _paymentReceiveDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // Payment Method
                    _fieldLabel('Payment Method'),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      items: ['Cash', 'UPI', 'Card', 'Net Banking', 'Cheque']
                          .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _paymentMethod = val);
                      },
                    ),

                    // ══════════════════════════════════════
                    // SECTION 4: PERSONAL TRAINER (Optional)
                    // ══════════════════════════════════════
                    if (_selectedPlan == null || _selectedPlan!.ptIncluded) ...[
                      _sectionHeader('Personal Trainer', 'Optional — No commission for old data', Icons.fitness_center),

                      // PT Toggle
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.fitness_center, size: 20, color: AppTheme.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Assign Personal Trainer', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                                  Text('(Optional)', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                                ],
                              ),
                            ),
                            Switch(
                              value: _hasPersonalTrainer,
                              activeThumbColor: AppTheme.primary,
                              onChanged: (val) => setState(() => _hasPersonalTrainer = val),
                            ),
                          ],
                        ),
                      ),

                      if (_hasPersonalTrainer) ...[
                        const SizedBox(height: 12),
                        // Warning banner
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'PT commission will NOT be generated for old data. Commission will apply on renewal.',
                                  style: GoogleFonts.inter(fontSize: 11.5, color: Colors.amber.shade900, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        _fieldLabel('Select Trainer'),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedTrainerId,
                          hint: Text('Select trainer', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
                          isExpanded: true,
                          items: trainerList.map((s) {
                            return DropdownMenuItem(
                              value: s.id,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: AppTheme.primaryLight,
                                    backgroundImage: s.avatar.isNotEmpty ? NetworkImage(s.avatar) : null,
                                    child: s.avatar.isEmpty
                                        ? Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : '?',
                                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.primary))
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(s.name, style: GoogleFonts.inter(fontSize: 14)),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _selectedTrainerId = val),
                        ),
                      ],
                    ],

                    // ══════════════════════════════════════
                    // SECTION 5: NOTES
                    // ══════════════════════════════════════
                    _sectionHeader('Additional Notes', 'Any extra information', Icons.note_alt_outlined),
                    TextFormField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: const InputDecoration(hintText: 'Enter notes (optional)'),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            // Bottom Save Button
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SizedBox(
                width: double.infinity,
                height: AppTheme.buttonHeight,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusButton)),
                  ),
                  onPressed: _isSaving ? null : _saveOldMember,
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: Text(
                    'Save Old Member',
                    style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPhotoPickerBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Add Photo',
                  style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: AppTheme.primary),
                  title: Text('Upload from Gallery', style: GoogleFonts.inter(fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadPhoto(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.primary),
                  title: Text('Capture Photo', style: GoogleFonts.inter(fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadPhoto(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.surfaceGray,
                    foregroundColor: AppTheme.textPrimary,
                    elevation: 0,
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
