import 'dart:math';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../members/members_viewmodel.dart';
import 'trial_members_viewmodel.dart';
import '../membership/membership_viewmodel.dart';
import '../staff/staff_viewmodel.dart';
import '../workout/workout_viewmodel.dart';
import '../diet/diet_viewmodel.dart';
import '../gym_settings/gym_settings_viewmodel.dart';
import '../authentication/auth_viewmodel.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/image_security_service.dart';
import '../../core/models/member.dart';
import '../../core/models/membership_plan.dart';
import '../../core/widgets/success_dialog.dart';
import 'member_add_success_screen.dart';
import '../subscription/owner_subscription_screen.dart';
import '../../core/navigation/app_router.dart';
import '../../core/repository/gym_repository.dart';
import '../subscription/subscription_limit_screen.dart';

class AddMemberWizardScreen extends StatefulWidget {
  final String? initialName;
  final String? initialPhone;
  final String? initialAvatarUrl;
  final String? sourceTrialId;
  final double? trialPaymentAmount;
  final String? trialStartDate; // yyyy-MM-dd
  final String? trialStartTime; // ISO string

  const AddMemberWizardScreen({
    super.key,
    this.initialName,
    this.initialPhone,
    this.initialAvatarUrl,
    this.sourceTrialId,
    this.trialPaymentAmount,
    this.trialStartDate,
    this.trialStartTime,
  });

  @override
  State<AddMemberWizardScreen> createState() => _AddMemberWizardScreenState();
}

class _AddMemberWizardScreenState extends State<AddMemberWizardScreen> {
  int _currentStep = 1;
  final int _totalSteps = 5;

  // Image upload state
  final ImagePicker _imagePicker = ImagePicker();
  String _avatarUrl = '';
  bool _isUploadingPhoto = false;
  double _photoUploadProgress = 0.0;

  bool _useTrialJoinDate = true;
  bool _adjustTrialPayment = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialName != null) {
      _nameController.text = widget.initialName!;
    }
    if (widget.initialPhone != null) {
      _phoneController.text = widget.initialPhone!;
    }
    if (widget.initialAvatarUrl != null) {
      _avatarUrl = widget.initialAvatarUrl!;
    }
    if (widget.sourceTrialId != null && widget.trialStartDate != null) {
      _joiningDate = DateTime.tryParse(widget.trialStartDate!);
    } else {
      _joiningDate = DateTime.now();
    }
    _recalculateExpiry();
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

      setState(() {
        _photoUploadProgress = 0.5;
      });

      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? 'default_gym';

      setState(() {
        _photoUploadProgress = 0.7;
      });

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

  // ── Step 1: Basic Information ──
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _biometricPinController = TextEditingController();
  bool _showAltPhone = false;
  String _selectedGender = 'Male';
  DateTime? _dob;
  int _calculatedAge = 0;

  // ── Step 2: Membership ──
  MembershipPlan? _selectedPlan;
  DateTime? _joiningDate;
  String _selectedDuration = '';
  DateTime? _expiryDate;
  final _feesController = TextEditingController();
  final _discountController = TextEditingController();
  final _paidController = TextEditingController();
  final _remainingController = TextEditingController(text: '0');
  String _paymentMethod = '';

  // ── Step 3: Goal & Plan ──
  String? _selectedGoal;
  String? _selectedWorkoutId;
  String? _selectedDietId;
  bool _hasPersonalTrainer = false;
  String? _selectedTrainerId;
  bool _trackBodyMeasurements = false;

  // Step 3 body measurements (shown if toggle on)
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _chestController = TextEditingController();
  final _waistController = TextEditingController();
  final _bicepsController = TextEditingController();
  final _hipController = TextEditingController();

  // ── Step 4: Health Information ──
  bool? _hasMedicalHistory; // null = not selected, true = Yes, false = No
  final _bloodGroup = ValueNotifier<String>('');
  final _allergiesController = TextEditingController();
  final _medicationController = TextEditingController();
  final _injuryHistoryController = TextEditingController();
  final _medicalDetailsController = TextEditingController();

  // ── Step 5: Review & Confirm ──
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _addressController.dispose();
    _biometricPinController.dispose();
    _feesController.dispose();
    _discountController.dispose();
    _paidController.dispose();
    _remainingController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _chestController.dispose();
    _waistController.dispose();
    _bicepsController.dispose();
    _hipController.dispose();
    _allergiesController.dispose();
    _medicationController.dispose();
    _injuryHistoryController.dispose();
    _medicalDetailsController.dispose();
    _notesController.dispose();
    _bloodGroup.dispose();
    super.dispose();
  }

  double get finalPayable {
    final fees = double.tryParse(_feesController.text) ?? 0.0;
    final discount = double.tryParse(_discountController.text) ?? 0.0;
    double val = (fees - discount).clamp(0.0, double.infinity);
    if (_adjustTrialPayment && widget.trialPaymentAmount != null) {
      val = (val - widget.trialPaymentAmount!).clamp(0.0, double.infinity);
    }
    return val;
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
    final paid = double.tryParse(_paidController.text) ?? 0.0;
    _remainingController.text = (finalPayable - paid).clamp(0.0, double.infinity).toStringAsFixed(0);
  }

  void _calculateAge() {
    if (_dob != null) {
      final today = DateTime.now();
      int age = today.year - _dob!.year;
      if (today.month < _dob!.month || (today.month == _dob!.month && today.day < _dob!.day)) {
        age--;
      }
      _calculatedAge = age;
    }
  }

  // ─────────────────────────────────────────────
  // FIELD LABEL
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

  // ─────────────────────────────────────────────
  // DATE PICKER FIELD
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  // READ-ONLY FIELD
  // ─────────────────────────────────────────────
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

  // ─────────────────────────────────────────────
  // STEP INDICATOR (Horizontal 1-5 with lines)
  // ─────────────────────────────────────────────
  Widget _buildStepIndicator() {
    List<Widget> children = [];
    for (int i = 0; i < _totalSteps; i++) {
      final stepNum = i + 1;
      final isCompleted = stepNum < _currentStep;
      final isCurrent = stepNum == _currentStep;

      // Circle
      children.add(
        GestureDetector(
          onTap: () {
            if (stepNum < _currentStep) {
              setState(() => _currentStep = stepNum);
            }
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isCurrent
                  ? AppTheme.primary
                  : (isCompleted ? AppTheme.primary : Colors.transparent),
              shape: BoxShape.circle,
              border: Border.all(
                color: isCurrent || isCompleted ? AppTheme.primary : AppTheme.textMuted.withValues(alpha: 0.4),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(
                    '$stepNum',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isCurrent ? Colors.white : AppTheme.textMuted,
                    ),
                  ),
          ),
        ),
      );

      // Connector line
      if (stepNum < _totalSteps) {
        children.add(
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: stepNum < _currentStep ? AppTheme.primary : AppTheme.border,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: children,
      ),
    );
  }

  // ─────────────────────────────────────────────
  // STEP TITLE HEADER
  // ─────────────────────────────────────────────
  Widget _buildStepHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
        const SizedBox(height: 2),
        Text(subtitle, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted)),
        const SizedBox(height: 20),
      ],
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
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
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

  // ═════════════════════════════════════════════
  // STEP 1: BASIC INFORMATION
  // ═════════════════════════════════════════════
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Basic Information', 'Personal & Contact Details'),

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
                            color: Colors.black.withOpacity(0.4),
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
        const SizedBox(height: 24),

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
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                  onPressed: () {
                    _altPhoneController.clear();
                    setState(() => _showAltPhone = false);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Address
        _fieldLabel('Address', required: true),
        TextFormField(
          controller: _addressController,
          decoration: InputDecoration(
            hintText: 'Enter full address',
            suffixIcon: _addressController.text.isNotEmpty
                ? Icon(Icons.check_circle, size: 20, color: AppTheme.success)
                : null,
          ),
        ),
        const SizedBox(height: 16),

        // Gender
        _fieldLabel('Gender', required: true),
        Row(
          children: [
            _genderChip('Male', Icons.male),
            const SizedBox(width: 12),
            _genderChip('Female', Icons.female),
          ],
        ),
        const SizedBox(height: 16),

        // Date of Birth
        _fieldLabel('Date of Birth', required: true),
        _datePicker(
          hint: 'Select date',
          value: _dob,
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _dob ?? DateTime.now(),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (picked != null) {
              setState(() {
                _dob = picked;
                _calculateAge();
              });
            }
          },
        ),
        const SizedBox(height: 16),

        // Age
        _fieldLabel('Age'),
        _readOnlyField(_calculatedAge > 0 ? '$_calculatedAge years' : 'Auto calculated'),
        const SizedBox(height: 16),

        // Biometric Machine PIN / User ID
        _fieldLabel('Biometric Machine User ID / PIN (Optional)'),
        TextFormField(
          controller: _biometricPinController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'e.g. 101, 1024',
            prefixIcon: const Icon(Icons.fingerprint_rounded, color: AppTheme.primary),
            helperText: 'Enroll this same ID number on the fingerprint/face machine',
            helperStyle: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _photoActionButton(IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        minimumSize: Size.zero,
        side: const BorderSide(color: AppTheme.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusInput)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: AppTheme.textSecondary),
      label: Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textPrimary)),
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

  // ═════════════════════════════════════════════
  // STEP 2: MEMBERSHIP
  // ═════════════════════════════════════════════
  Widget _buildStep2(MembershipViewModel membershipVm) {
    final activePlans = membershipVm.plans.where((p) => p.status == 'Active').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Membership', 'Plan & Duration'),

        if (widget.sourceTrialId != null) ...[
          _fieldLabel('Use Joining Date'),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _useTrialJoinDate = true;
                      if (widget.trialStartDate != null) {
                        _joiningDate = DateTime.tryParse(widget.trialStartDate!);
                        _recalculateExpiry();
                      }
                    });
                  },
                  child: Row(
                    children: [
                      Radio<bool>(
                        value: true,
                        groupValue: _useTrialJoinDate,
                        activeColor: AppTheme.primary,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _useTrialJoinDate = val;
                              if (widget.trialStartDate != null) {
                                _joiningDate = DateTime.tryParse(widget.trialStartDate!);
                                _recalculateExpiry();
                              }
                            });
                          }
                        },
                      ),
                      Expanded(
                        child: Text(
                          'Use Trial Join Date (Recommended)',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _useTrialJoinDate = false;
                    });
                  },
                  child: Row(
                    children: [
                      Radio<bool>(
                        value: false,
                        groupValue: _useTrialJoinDate,
                        activeColor: AppTheme.primary,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _useTrialJoinDate = val;
                            });
                          }
                        },
                      ),
                      Expanded(
                        child: Text(
                          'Select Custom Date',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        // Membership Plan
        _fieldLabel('Membership Plan', required: true),
        DropdownButtonFormField<MembershipPlan>(
          value: activePlans.any((p) => p.id == _selectedPlan?.id)
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

        // Date of Joining
        _fieldLabel('Date of Joining', required: true),
        _datePicker(
          hint: 'Select date',
          value: _joiningDate,
          onTap: (widget.sourceTrialId != null && _useTrialJoinDate)
              ? () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('To choose a custom date, select the "Select Custom Date" option above.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _joiningDate ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
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

        // Membership Duration
        _fieldLabel('Membership Duration'),
        _readOnlyField(_selectedDuration.isNotEmpty ? _selectedDuration : 'Select duration'),
        const SizedBox(height: 16),

        // Expiry Date
        _fieldLabel('Expiry Date'),
        _readOnlyField(_expiryDate == null ? 'Auto calculated' : DateFormat('dd MMM yyyy').format(_expiryDate!)),
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
                    decoration: const InputDecoration(hintText: 'Enter amount'),
                    onChanged: (_) => setState(() => _recalculateRemaining()),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Paid + Remaining
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel('Paid Amount (₹)', required: true),
                  TextFormField(
                    controller: _paidController,
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
                  _fieldLabel('Remaining Amount (₹)'),
                  _readOnlyField('₹${_remainingController.text}'),
                ],
              ),
            ),
          ],
        ),
        if (widget.trialPaymentAmount != null && widget.trialPaymentAmount! > 0) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _adjustTrialPayment,
                activeColor: AppTheme.primary,
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _adjustTrialPayment = val;
                      _paidController.text = finalPayable.toStringAsFixed(0);
                      _recalculateRemaining();
                    });
                  }
                },
              ),
              Expanded(
                child: Text(
                  'Adjust Trial Payment Into Membership (₹${widget.trialPaymentAmount!.toStringAsFixed(0)})',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          if (_adjustTrialPayment) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.successLight.withOpacity(0.3),
                borderRadius: BorderRadius.circular(AppTheme.radiusInput),
                border: Border.all(color: AppTheme.successLight),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Membership Fee:', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                      Text('₹${(double.tryParse(_feesController.text) ?? 0.0).toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Trial Adjusted:', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                      Text('-₹${widget.trialPaymentAmount!.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.success)),
                    ],
                  ),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Final Payable:', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      Text('₹${finalPayable.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 16),

        // Payment Method
        _fieldLabel('Payment Method'),
        DropdownButtonFormField<String>(
          value: _paymentMethod.isEmpty ? null : _paymentMethod,
          hint: Text('Select payment method', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
          items: ['Cash', 'UPI', 'Card', 'Net Banking', 'Cheque'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _paymentMethod = val);
          },
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════
  // STEP 3: GOAL & PLAN
  // ═════════════════════════════════════════════
  Widget _defaultTrainerAvatar(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.primary),
      ),
    );
  }

  Widget _buildStep3(
    GymSettingsViewModel settingsVm,
    WorkoutViewModel workoutVm,
    DietViewModel dietVm,
    StaffViewModel staffVm,
  ) {
    final goalsList = settingsVm.goals.map((e) => e.name).toList();
    if (goalsList.isEmpty) goalsList.add('Fitness');

    final filteredWorkouts = _selectedGoal != null
        ? workoutVm.workouts.where((w) => w.goal == _selectedGoal).toList()
        : workoutVm.workouts;
    final filteredDiets = _selectedGoal != null
        ? dietVm.diets.where((d) => d.goal == _selectedGoal).toList()
        : dietVm.diets;
    final trainerList = staffVm.allStaff.where((s) => 
      s.role == 'Trainer' || s.role == 'Personal Trainer'
    ).toList();

    // Membership Plan restrictions
    final showWorkout = _selectedPlan == null ? true : _selectedPlan!.workoutIncluded;
    final showDiet = _selectedPlan == null ? true : _selectedPlan!.dietIncluded;
    final showPt = _selectedPlan == null ? true : _selectedPlan!.ptIncluded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Goal & Plan', 'Workout & Diet Plan'),

        // Select Goal
        _fieldLabel('Select Goal', required: true),
        DropdownButtonFormField<String>(
          value: _selectedGoal,
          hint: Text('Select goal', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
          items: goalsList.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedGoal = val;
                _selectedWorkoutId = null;
                _selectedDietId = null;
              });
            }
          },
        ),
        const SizedBox(height: 14),

        // Info card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryLight.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppTheme.radiusInput),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: AppTheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Workout plans and diet plans will be filtered based on the selected goal.',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Workout Plan
        if (showWorkout) ...[
          _fieldLabel('Workout Plan', required: true),
          DropdownButtonFormField<String>(
            value: _selectedWorkoutId,
            hint: Text('Select workout plan', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
            items: filteredWorkouts.map((w) => DropdownMenuItem(value: w.id, child: Text(w.title))).toList(),
            onChanged: (val) => setState(() => _selectedWorkoutId = val),
          ),
          const SizedBox(height: 16),
        ],

        // Diet Plan
        if (showDiet) ...[
          _fieldLabel('Diet Plan', required: true),
          DropdownButtonFormField<String>(
            value: _selectedDietId,
            hint: Text('Select diet plan', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
            items: filteredDiets.map((d) => DropdownMenuItem(value: d.id, child: Text(d.title))).toList(),
            onChanged: (val) => setState(() => _selectedDietId = val),
          ),
          const SizedBox(height: 24),
        ],

        // ── Personal Trainer Toggle ──
        if (showPt) ...[
          _toggleOption(
            icon: Icons.fitness_center,
            title: 'Personal Trainer',
            subtitle: 'Assign personal trainer\nfor this member',
            tag: '(Optional)',
            value: _hasPersonalTrainer,
            onChanged: (val) => setState(() => _hasPersonalTrainer = val),
          ),

          // PT sub-form
          if (_hasPersonalTrainer) ...[
            const SizedBox(height: 14),
            _fieldLabel('Select Trainer', required: true),
            DropdownButtonFormField<String>(
              value: _selectedTrainerId,
              hint: Text('Choose a trainer', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
              items: trainerList.map((t) {
                return DropdownMenuItem(
                  value: t.id,
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 28,
                          height: 28,
                          color: AppTheme.primaryLight,
                          child: t.avatar.isNotEmpty
                              ? Image.network(t.avatar, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _defaultTrainerAvatar(t.name))
                              : _defaultTrainerAvatar(t.name),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(t.name, style: GoogleFonts.inter(fontSize: 14)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) => setState(() => _selectedTrainerId = val),
            ),
          ],
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 16),

        // ── Body Measurements Toggle ──
        _toggleOption(
          icon: Icons.straighten,
          title: 'Body Measurements',
          subtitle: 'Track body measurements\nfor this member',
          tag: '(Optional)',
          value: _trackBodyMeasurements,
          onChanged: (val) => setState(() => _trackBodyMeasurements = val),
        ),

        // Measurements sub-form
        if (_trackBodyMeasurements) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _measurementField('Weight (kg)', _weightController)),
              const SizedBox(width: 12),
              Expanded(child: _measurementField('Height (cm)', _heightController)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _measurementField('Chest (in)', _chestController)),
              const SizedBox(width: 12),
              Expanded(child: _measurementField('Waist (in)', _waistController)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _measurementField('Biceps (in)', _bicepsController)),
              const SizedBox(width: 12),
              Expanded(child: _measurementField('Hip (in)', _hipController)),
            ],
          ),
        ],
      ],
    );
  }

  Widget _toggleOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String tag,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: value ? AppTheme.primaryLight.withValues(alpha: 0.3) : AppTheme.surfaceGray,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: value ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: value ? AppTheme.primary.withValues(alpha: 0.15) : Colors.white,
              borderRadius: BorderRadius.circular(AppTheme.radiusInput),
            ),
            child: Icon(icon, size: 22, color: value ? AppTheme.primary : AppTheme.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    const SizedBox(width: 6),
                    Text(tag, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.3)),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: value,
              activeColor: AppTheme.primary,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _measurementField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w500, color: AppTheme.textSecondary)),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: label.split(' ').first),
        ),
      ],
    );
  }

  // ═════════════════════════════════════════════
  // STEP 4: HEALTH INFORMATION
  // ═════════════════════════════════════════════
  Widget _buildStep4() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Health Information', 'Medical & Health Details'),

        // Medical History
        _fieldLabel('Any sort of medical history?', required: true),
        const SizedBox(height: 4),
        Row(
          children: [
            _radioOption('Yes', _hasMedicalHistory == true, () => setState(() => _hasMedicalHistory = true)),
            const SizedBox(width: 16),
            _radioOption('No', _hasMedicalHistory == false, () => setState(() => _hasMedicalHistory = false)),
          ],
        ),

        // Medical Details (shown only when Yes)
        if (_hasMedicalHistory == true) ...[
          const SizedBox(height: 14),
          _fieldLabel('Medical Details'),
          TextFormField(
            controller: _medicalDetailsController,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Enter medical condition details...'),
          ),
        ],
        const SizedBox(height: 20),

        // Blood Group
        _fieldLabel('Blood Group (If known)'),
        DropdownButtonFormField<String>(
          value: _bloodGroup.value.isEmpty ? null : _bloodGroup.value,
          hint: Text('Select blood group', style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textMuted)),
          items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'].map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _bloodGroup.value = val);
          },
        ),
        const SizedBox(height: 16),

        // Allergies
        _fieldLabel('Allergies (If any)'),
        TextFormField(
          controller: _allergiesController,
          decoration: const InputDecoration(hintText: 'Enter allergies'),
        ),
        const SizedBox(height: 16),

        // Current Medication
        _fieldLabel('Current Medication (If any)'),
        TextFormField(
          controller: _medicationController,
          decoration: const InputDecoration(hintText: 'Enter medication'),
        ),
        const SizedBox(height: 16),

        // Injury or Surgery History
        _fieldLabel('Injury or Surgery History (If any)'),
        TextFormField(
          controller: _injuryHistoryController,
          decoration: const InputDecoration(hintText: 'Enter details'),
        ),
      ],
    );
  }

  Widget _radioOption(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? AppTheme.primary : AppTheme.textMuted, width: 2),
            ),
            padding: const EdgeInsets.all(3),
            child: selected
                ? Container(decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.primary))
                : null,
          ),
          const SizedBox(width: 8),
          Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  // ═════════════════════════════════════════════
  // STEP 5: REVIEW & CONFIRM
  // ═════════════════════════════════════════════
  Widget _buildStep5(StaffViewModel staffVm) {
    // Resolve names
    final trainerName = _selectedTrainerId != null
        ? staffVm.allStaff.where((s) => s.id == _selectedTrainerId).firstOrNull?.name ?? 'N/A'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader('Review & Confirm', 'Review all details before saving'),

        // Basic Info
        _reviewCard(
          icon: Icons.check_circle,
          iconColor: AppTheme.primary,
          title: 'Basic Information',
          summary: _nameController.text.isEmpty ? 'Not filled' : _nameController.text,
          onEdit: () => setState(() => _currentStep = 1),
        ),

        // Membership
        _reviewCard(
          icon: Icons.card_membership,
          iconColor: AppTheme.primary,
          title: 'Membership',
          summary: _selectedPlan != null
              ? '${_selectedPlan!.title} • $_selectedDuration'
              : 'Not selected',
          onEdit: () => setState(() => _currentStep = 2),
        ),

        // Goal & Plan
        _reviewCard(
          icon: Icons.track_changes,
          iconColor: AppTheme.primary,
          title: 'Goal & Plan',
          summary: _selectedGoal ?? 'Not selected',
          details: [
            if (_selectedWorkoutId != null) '• Workout Plan assigned',
            if (_selectedDietId != null) '• Diet Plan assigned',
          ],
          onEdit: () => setState(() => _currentStep = 3),
        ),

        // Trainer Assignment
        _reviewCard(
          icon: Icons.fitness_center,
          iconColor: AppTheme.primary,
          title: 'Trainer Assignment',
          summary: _hasPersonalTrainer
              ? '${trainerName ?? 'Unassigned'} (Optional)'
              : 'Not Assigned',
          onEdit: () => setState(() => _currentStep = 3),
        ),

        // Health Info
        _reviewCard(
          icon: Icons.favorite,
          iconColor: AppTheme.primary,
          title: 'Health Information',
          summary: _hasMedicalHistory == true
              ? 'Medical History Added'
              : 'No Medical History',
          onEdit: () => setState(() => _currentStep = 4),
        ),

        // Body Measurements
        _reviewCard(
          icon: Icons.straighten,
          iconColor: AppTheme.primary,
          title: 'Body Measurements',
          summary: _trackBodyMeasurements ? 'Measurements Added' : 'Not Added',
          onEdit: () => setState(() => _currentStep = 3),
        ),

        // Additional Information
        _reviewCard(
          icon: Icons.note_alt_outlined,
          iconColor: AppTheme.primary,
          title: 'Additional Information',
          summary: _notesController.text.isEmpty ? 'No notes' : 'Notes Added',
          onEdit: null,
          isLast: true,
        ),

        // Notes inline
        const SizedBox(height: 8),
        TextFormField(
          controller: _notesController,
          maxLines: 2,
          decoration: const InputDecoration(hintText: 'Add any additional notes (optional)...'),
        ),
      ],
    );
  }

  Widget _reviewCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String summary,
    List<String> details = const [],
    VoidCallback? onEdit,
    bool isLast = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: isLast ? BorderSide.none : BorderSide(color: AppTheme.border, width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                  const SizedBox(height: 2),
                  Text(summary, style: GoogleFonts.inter(fontSize: 12.5, color: AppTheme.textSecondary)),
                  ...details.map((d) => Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(d, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                  )),
                ],
              ),
            ),
            if (onEdit != null)
              InkWell(
                onTap: onEdit,
                child: Text('Edit', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
              ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // VALIDATION
  // ─────────────────────────────────────────────
  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 1:
        if (_nameController.text.trim().isEmpty) {
          _showError('Please enter Full Name');
          return false;
        }
        if (_phoneController.text.trim().isEmpty) {
          _showError('Please enter Contact Number');
          return false;
        }
        return true;
      case 2:
        if (_selectedPlan == null) {
          _showError('Please select a Membership Plan');
          return false;
        }
        if (_joiningDate == null) {
          _showError('Please select Date of Joining');
          return false;
        }
        return true;
      case 3:
        if (_hasPersonalTrainer && _selectedTrainerId == null) {
          _showError('Please select a Trainer');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
    );
  }

  void _nextStep() {
    if (!_validateCurrentStep()) return;
    if (_currentStep < _totalSteps) {
      setState(() => _currentStep++);
    }
  }

  void _prevStep() {
    if (_currentStep > 1) setState(() => _currentStep--);
  }

  // ─────────────────────────────────────────────
  // SAVE MEMBER
  // ─────────────────────────────────────────────
  String _generateUUIDv4() {
    final random = Random.secure();
    const chars = '0123456789abcdef';
    String hexStr(int length) {
      return List.generate(length, (index) => chars[random.nextInt(16)]).join();
    }
    final y = ['8', '9', 'a', 'b'][random.nextInt(4)];
    return '${hexStr(8)}-${hexStr(4)}-4${hexStr(3)}-$y${hexStr(3)}-${hexStr(12)}';
  }

  // ─────────────────────────────────────────────
  // SAVE MEMBER
  // ─────────────────────────────────────────────
  void _showUpgradeDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.star_rounded, color: AppTheme.warning, size: 24),
            const SizedBox(width: 10),
            Text(
              'Upgrade Subscription',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: AppTheme.textMuted, fontWeight: FontWeight.w600),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(context, AppRouter.slideRoute(const OwnerSubscriptionScreen()));
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: Text(
              'View Plan Details',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveMember() async {
    // Check subscription limits first
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
        return;
      }
    }

    final id = _generateUUIDv4();

    final Map<String, dynamic> extra = {
      'goal': _selectedGoal ?? 'General Fitness',
      'altPhone': _altPhoneController.text.trim(),
      'address': _addressController.text.trim(),
      'gender': _selectedGender,
      'dob': _dob?.toIso8601String() ?? '',
      'age': _calculatedAge,
      'fees': double.tryParse(_feesController.text) ?? 0.0,
      'discount': double.tryParse(_discountController.text) ?? 0.0,
      'paid': double.tryParse(_paidController.text) ?? 0.0,
      'paymentMethod': _paymentMethod,
      'expiryDate': _expiryDate?.toIso8601String() ?? '',
      'bloodGroup': _bloodGroup.value,
      'allergies': _allergiesController.text,
      'medication': _medicationController.text,
      'injuryHistory': _injuryHistoryController.text,
      'hasMedicalHistory': _hasMedicalHistory ?? false,
      'trackMeasurements': _trackBodyMeasurements,
      'measurements': {
        'weight': _weightController.text,
        'height': _heightController.text,
        'chest': _chestController.text,
        'waist': _waistController.text,
        'biceps': _bicepsController.text,
        'hip': _hipController.text,
      },
    };

    final showWorkout = _selectedPlan == null ? true : _selectedPlan!.workoutIncluded;
    final showDiet = _selectedPlan == null ? true : _selectedPlan!.dietIncluded;
    final showPt = _selectedPlan == null ? true : _selectedPlan!.ptIncluded;

    final paidToday = double.tryParse(_paidController.text) ?? 0.0;
    final trialPaidAmount = (_adjustTrialPayment && widget.trialPaymentAmount != null) ? widget.trialPaymentAmount! : 0.0;
    final totalReceived = paidToday + trialPaidAmount;

    String? customCreatedAt;
    if (widget.sourceTrialId != null && _useTrialJoinDate && widget.trialStartTime != null) {
      customCreatedAt = widget.trialStartTime;
    }

    final newMember = Member(
      id: id,
      name: _nameController.text.trim(),
      email: '',
      phone: _phoneController.text.trim(),
      avatar: _avatarUrl,
      joinDate: _joiningDate != null ? DateFormat('dd MMM yyyy').format(_joiningDate!) : DateFormat('dd MMM yyyy').format(DateTime.now()),
      status: 'Active',
      membershipPlanId: _selectedPlan?.id ?? '',
      ptMember: showPt && _hasPersonalTrainer,
      ptTrainer: (showPt && _hasPersonalTrainer) ? (_selectedTrainerId ?? '') : '',
      assignedWorkoutId: showWorkout ? (_selectedWorkoutId ?? '') : '',
      assignedDietId: showDiet ? (_selectedDietId ?? '') : '',
      medicalDetails: _hasMedicalHistory == true ? _medicalDetailsController.text : 'None',
      notes: _notesController.text,
      pendingAmount: double.tryParse(_remainingController.text) ?? 0.0,
      discountAmount: double.tryParse(_discountController.text) ?? 0.0,
      totalReceivedAmount: totalReceived,
      paymentStatus: (double.tryParse(_remainingController.text) ?? 0.0) <= 0 ? 'Paid' : 'Partial',
      extraFields: extra,
      createdAt: customCreatedAt,
      biometricPin: int.tryParse(_biometricPinController.text.trim()),
    );

    final vm = Provider.of<MembersViewModel>(context, listen: false);

    // Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    try {
      await vm.updateMember(
        newMember, 
        paymentMethod: _paymentMethod.isNotEmpty ? _paymentMethod : 'Cash',
        transactionAmount: paidToday,
      );

      // Mark trial as Converted
      if (widget.sourceTrialId != null) {
        try {
          final trialsVm = Provider.of<TrialMembersViewModel>(context, listen: false);
          await trialsVm.markAsConverted(widget.sourceTrialId!);
        } catch (e) {
          print('Error marking trial as converted: $e');
        }
      }

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
    }
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final membershipVm = Provider.of<MembershipViewModel>(context);
    final staffVm = Provider.of<StaffViewModel>(context);
    final workoutVm = Provider.of<WorkoutViewModel>(context);
    final dietVm = Provider.of<DietViewModel>(context);
    final settingsVm = Provider.of<GymSettingsViewModel>(context);

    Widget stepContent;
    switch (_currentStep) {
      case 1:
        stepContent = _buildStep1();
        break;
      case 2:
        stepContent = _buildStep2(membershipVm);
        break;
      case 3:
        stepContent = _buildStep3(settingsVm, workoutVm, dietVm, staffVm);
        break;
      case 4:
        stepContent = _buildStep4();
        break;
      case 5:
        stepContent = _buildStep5(staffVm);
        break;
      default:
        stepContent = const SizedBox();
    }

    return PopScope(
      canPop: _currentStep == 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentStep > 1) {
          _prevStep();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 20),
            onPressed: () {
              if (_currentStep > 1) {
                _prevStep();
              } else {
                Navigator.pop(context);
              }
            },
          ),
          title: Text('Add Member', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600)),
          centerTitle: true,
          elevation: 0,
        ),
        body: SafeArea(
          child: Builder(
            builder: (context) {
              final isDesktop = MediaQuery.of(context).size.width >= 900;

              return Column(
                children: [
                  // Step circles
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: _buildStepIndicator(),
                    ),
                  ),

                  // Scrollable step content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isDesktop ? 32 : 20,
                        vertical: isDesktop ? 16 : 4,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 820),
                          child: Container(
                            padding: isDesktop ? const EdgeInsets.all(28) : EdgeInsets.zero,
                            decoration: isDesktop
                                ? BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: AppTheme.border),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.02),
                                        blurRadius: 10,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  )
                                : null,
                            child: stepContent,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Bottom buttons
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: isDesktop ? const Border(top: BorderSide(color: AppTheme.border)) : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: _currentStep == 1
                            ? SizedBox(
                                width: double.infinity,
                                height: AppTheme.buttonHeight,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusButton)),
                                  ),
                                  onPressed: _nextStep,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Next', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward, size: 18),
                                    ],
                                  ),
                                ),
                              )
                            : Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: AppTheme.buttonHeight,
                                      child: OutlinedButton(
                                        onPressed: _prevStep,
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: AppTheme.border),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusButton)),
                                        ),
                                        child: Text('Back', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: SizedBox(
                                      height: AppTheme.buttonHeight,
                                      child: _currentStep == _totalSteps
                                          ? ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppTheme.primary,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusButton)),
                                              ),
                                              onPressed: _saveMember,
                                              icon: const Icon(Icons.check_circle_outline, size: 20),
                                              label: Text('Save Member', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                                            )
                                          : ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppTheme.primary,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusButton)),
                                              ),
                                              onPressed: _nextStep,
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  Text('Next', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600)),
                                                  const SizedBox(width: 8),
                                                  const Icon(Icons.arrow_forward, size: 18),
                                                ],
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
