import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/theme.dart';
import '../../core/services/image_security_service.dart';
import '../../core/models/trial_member.dart';
import 'trial_members_viewmodel.dart';
import '../authentication/auth_viewmodel.dart';
import '../../core/widgets/success_dialog.dart';

class AddTrialMemberScreen extends StatefulWidget {
  final TrialMember? editTrial;

  const AddTrialMemberScreen({super.key, this.editTrial});

  @override
  State<AddTrialMemberScreen> createState() => _AddTrialMemberScreenState();
}

class _AddTrialMemberScreenState extends State<AddTrialMemberScreen> {
  final _formKey = GlobalKey<FormState>();

  // Image Upload State
  final ImagePicker _imagePicker = ImagePicker();
  String _avatarUrl = '';
  bool _isUploadingPhoto = false;
  double _photoUploadProgress = 0.0;

  // Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _daysController = TextEditingController(text: '7');
  
  // Trial type & dates
  String _selectedTrialType = 'Free'; // Free, Paid
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 7));

  // Payment controllers (Used for Paid Trial)
  final _feeController = TextEditingController(text: '0');
  final _discountController = TextEditingController(text: '0');
  final _receivedController = TextEditingController(text: '0');
  final _remainingController = TextEditingController(text: '0');
  String _paymentMethod = 'Cash';
  DateTime _paymentDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    if (widget.editTrial != null) {
      final trial = widget.editTrial!;
      _nameController.text = trial.name;
      _phoneController.text = trial.phone;
      _avatarUrl = trial.avatar;
      _selectedTrialType = trial.trialType;
      _daysController.text = trial.trialDays.toString();
      _startDate = DateTime.tryParse(trial.startDate) ?? DateTime.now();
      _endDate = DateTime.tryParse(trial.endDate) ?? DateTime.now();
      
      _feeController.text = trial.fee.toStringAsFixed(0);
      _discountController.text = trial.discount.toStringAsFixed(0);
      _receivedController.text = trial.receivedAmount.toStringAsFixed(0);
      _paymentMethod = trial.paymentMethod ?? 'Cash';
      _paymentDate = trial.paymentDate != null ? (DateTime.tryParse(trial.paymentDate!) ?? DateTime.now()) : DateTime.now();
    }
    _recalculateEndDate();
    _recalculatePayments();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _daysController.dispose();
    _feeController.dispose();
    _discountController.dispose();
    _receivedController.dispose();
    _remainingController.dispose();
    super.dispose();
  }

  void _recalculateEndDate() {
    final days = int.tryParse(_daysController.text) ?? 0;
    setState(() {
      _endDate = _startDate.add(Duration(days: days));
    });
  }

  void _recalculatePayments() {
    final fee = double.tryParse(_feeController.text) ?? 0.0;
    final discount = double.tryParse(_discountController.text) ?? 0.0;
    final finalAmount = (fee - discount).clamp(0.0, double.infinity);
    final received = double.tryParse(_receivedController.text) ?? 0.0;
    final remaining = (finalAmount - received).clamp(0.0, double.infinity);
    
    _remainingController.text = remaining.toStringAsFixed(0);
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
        directoryPath: '$gymId/trials',
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
    required DateTime value,
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
                DateFormat('dd MMM yyyy').format(value),
                style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textPrimary),
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

  Widget _trialTypeChip(String label) {
    final isSelected = _selectedTrialType == label;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedTrialType = label;
            _recalculatePayments();
          });
        },
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
              Icon(
                label == 'Free' ? Icons.card_giftcard : Icons.payment,
                size: 18,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                '$label Trial',
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

  String _generateUUIDv4() {
    final random = Random.secure();
    const chars = '0123456789abcdef';
    String hexStr(int length) {
      return List.generate(length, (index) => chars[random.nextInt(16)]).join();
    }
    final y = ['8', '9', 'a', 'b'][random.nextInt(4)];
    return '${hexStr(8)}-${hexStr(4)}-4${hexStr(3)}-$y${hexStr(3)}-${hexStr(12)}';
  }

  Future<void> _saveTrial() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final days = int.tryParse(_daysController.text) ?? 7;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter full name'), backgroundColor: AppTheme.danger));
      return;
    }
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter mobile number'), backgroundColor: AppTheme.danger));
      return;
    }

    final fee = double.tryParse(_feeController.text) ?? 0.0;
    final discount = double.tryParse(_discountController.text) ?? 0.0;
    final finalAmount = (fee - discount).clamp(0.0, double.infinity);
    final received = double.tryParse(_receivedController.text) ?? 0.0;

    if (fee < 0 || discount < 0 || received < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fees, discounts and received amounts cannot be negative.'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    if (_selectedTrialType == 'Paid') {
      if (received > finalAmount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Received Amount cannot exceed Final Amount'), backgroundColor: AppTheme.danger),
        );
        return;
      }
    }

    // Show loading spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
    );

    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? '';
      
      final id = widget.editTrial?.id ?? _generateUUIDv4();

      final trial = TrialMember(
        id: id,
        gymId: gymId,
        name: name,
        phone: phone,
        avatar: _avatarUrl,
        trialType: _selectedTrialType,
        trialDays: days,
        startDate: DateFormat('yyyy-MM-dd').format(_startDate),
        endDate: DateFormat('yyyy-MM-dd').format(_endDate),
        status: widget.editTrial?.status ?? 'Active',
        fee: _selectedTrialType == 'Paid' ? fee : 0.0,
        discount: _selectedTrialType == 'Paid' ? discount : 0.0,
        receivedAmount: _selectedTrialType == 'Paid' ? received : 0.0,
        paymentMethod: _selectedTrialType == 'Paid' ? _paymentMethod : null,
        paymentDate: _selectedTrialType == 'Paid' ? DateFormat('yyyy-MM-dd').format(_paymentDate) : null,
        createdAt: widget.editTrial?.createdAt ?? DateTime.now().toIso8601String(),
      );

      final vm = Provider.of<TrialMembersViewModel>(context, listen: false);
      if (widget.editTrial != null) {
        await vm.updateTrialMember(trial, paymentMethod: _paymentMethod);
      } else {
        await vm.addTrialMember(trial, paymentMethod: _paymentMethod);
      }

      if (mounted) {
        Navigator.pop(context); // Pop loading spinner
        SuccessDialog.show(
          context,
          title: widget.editTrial != null ? 'Trial Updated!' : 'Trial Created!',
          message: '$name trial details saved successfully.',
          onDone: () {
            Navigator.pop(context); // Return to list
          },
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop loading spinner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Database Error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.editTrial != null ? 'Edit Trial Member' : 'Add Trial Member';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(title, style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // CARD 1: Basic Information
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BASIC INFORMATION',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 16),

                            // Camera photo upload
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
                            const SizedBox(height: 20),

                            _fieldLabel('Full Name', required: true),
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(hintText: 'Enter full name'),
                              validator: (val) => (val == null || val.trim().isEmpty) ? 'Name is required' : null,
                            ),
                            const SizedBox(height: 16),

                            _fieldLabel('Mobile Number', required: true),
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
                                    validator: (val) => (val == null || val.trim().isEmpty) ? 'Mobile is required' : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // CARD 2: Trial Information
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TRIAL INFORMATION',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 16),

                            _fieldLabel('Trial Type', required: true),
                            Row(
                              children: [
                                _trialTypeChip('Free'),
                                const SizedBox(width: 12),
                                _trialTypeChip('Paid'),
                              ],
                            ),
                            const SizedBox(height: 16),

                            _fieldLabel('Trial Days', required: true),
                            TextFormField(
                              controller: _daysController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(hintText: 'e.g. 7'),
                              onChanged: (_) => _recalculateEndDate(),
                              validator: (val) => (val == null || val.trim().isEmpty || int.tryParse(val) == 0) ? 'Days must be at least 1' : null,
                            ),
                            const SizedBox(height: 16),

                            _fieldLabel('Trial Start Date', required: true),
                            _datePicker(
                              hint: 'Select start date',
                              value: _startDate,
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _startDate,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _startDate = picked;
                                    _recalculateEndDate();
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 16),

                            _fieldLabel('Trial End Date'),
                            _readOnlyField(DateFormat('dd MMM yyyy').format(_endDate)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // CARD 3: Payment (Paid Trial only)
                      if (_selectedTrialType == 'Paid')
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PAYMENT DETAILS',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5),
                              ),
                              const SizedBox(height: 16),

                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _fieldLabel('Trial Fee (₹)', required: true),
                                        TextFormField(
                                          controller: _feeController,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(hintText: 'Enter amount'),
                                          onChanged: (_) => setState(() => _recalculatePayments()),
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
                                          decoration: const InputDecoration(hintText: 'Enter discount'),
                                          onChanged: (_) => setState(() => _recalculatePayments()),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _fieldLabel('Received Amount (₹)', required: true),
                                        TextFormField(
                                          controller: _receivedController,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(hintText: 'Enter received amount'),
                                          onChanged: (_) => setState(() => _recalculatePayments()),
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
                              const SizedBox(height: 16),

                              _fieldLabel('Payment Method', required: true),
                              DropdownButtonFormField<String>(
                                value: _paymentMethod,
                                items: ['Cash', 'UPI', 'Card', 'Bank Transfer', 'Cheque', 'Other']
                                    .map((method) => DropdownMenuItem(value: method, child: Text(method)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _paymentMethod = val;
                                    });
                                  }
                                },
                              ),
                              const SizedBox(height: 16),

                              _fieldLabel('Payment Date', required: true),
                              _datePicker(
                                hint: 'Select payment date',
                                value: _paymentDate,
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _paymentDate,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _paymentDate = picked;
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Bottom Actions
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
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
                    onPressed: _saveTrial,
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: Text(
                      widget.editTrial != null ? 'Update Details' : 'Create Trial Member',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
