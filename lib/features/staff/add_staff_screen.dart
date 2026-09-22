import 'dart:async';
import 'dart:math';
import 'package:image_picker/image_picker.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/image_security_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/models/staff.dart';
import 'staff_viewmodel.dart';
import 'staff_success_dialog.dart';
import '../authentication/auth_viewmodel.dart';
import '../subscription/owner_subscription_screen.dart';
import '../../core/navigation/app_router.dart';
import '../../core/repository/gym_repository.dart';
import '../subscription/subscription_limit_screen.dart';

class AddStaffScreen extends StatefulWidget {
  const AddStaffScreen({super.key});

  @override
  State<AddStaffScreen> createState() => _AddStaffScreenState();
}

class _AddStaffScreenState extends State<AddStaffScreen> {
  int _currentStep = 1;
  final int _totalSteps = 4;
  bool _isLoading = false;

  // Form Keys for separate step validations
  final _formKeyStep1 = GlobalKey<FormState>();
  final _formKeyStep2 = GlobalKey<FormState>();
  final _formKeyStep3 = GlobalKey<FormState>();

  // Profile Image Picker simulation
  bool _isUploadingPhoto = false;
  double _photoUploadProgress = 0.0;
  String _profilePhotoUrl = '';

  // Step 1 Controllers (Personal Info)
  final _fullNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _dobController = TextEditingController();
  final _aadhaarController = TextEditingController();
  final _addressController = TextEditingController();
  String _selectedGender = 'Male';

  // Step 2 Controllers (Work Info)
  final _joiningDateController = TextEditingController();
  String _selectedRole = 'Trainer';
  String _selectedEmployment = 'Full Time';
  String _selectedShift = 'Single Shift';
  bool _isActiveStatus = true;
  String _gymShiftMode = 'Single Shift';

  // Custom Shift State Variables
  String _shiftType = 'single'; // 'single' or 'both'
  String _shift1Start = '09:00 AM';
  String _shift1End = '05:00 PM';
  String _shift2Start = '04:00 PM';
  String _shift2End = '09:00 PM';

  // Step 3 Controllers (Salary Info)
  final _salaryController = TextEditingController();
  final _commissionController = TextEditingController();
  String _selectedSalaryType = 'Fixed Salary'; // Fixed Salary, Percentage, Both

  // Step 4 Controllers (Other Info)
  final _experienceController = TextEditingController();
  final _qualificationController = TextEditingController();
  final _notesController = TextEditingController();

  final List<String> _roles = [
    'Trainer',
    'Receptionist',
    'Manager',
    'Cleaner',
    'Accountant',
    'Sales Executive',
    'Nutritionist',
    'Personal Trainer',
    'Other'
  ];

  final List<String> _employments = ['Full Time', 'Part Time', 'Freelancer'];
  final List<String> _shifts = ['Morning', 'Evening', 'Both'];
  final List<String> _salaryTypes = ['Fixed Salary', 'Percentage', 'Both'];

  @override
  void initState() {
    super.initState();
    _joiningDateController.text = DateFormat('dd MMM yyyy').format(DateTime.now());
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'];
      if (gymId != null) {
        try {
          final settingsRes = await SupabaseService.client
              .from('gym_shift_settings')
              .select('mode')
              .eq('gym_id', gymId)
              .maybeSingle();
              
          if (settingsRes != null) {
            _gymShiftMode = settingsRes['mode'] ?? 'Single Shift';
          }
          if (_gymShiftMode == 'Single Shift') {
            _selectedShift = 'Single Shift';
          } else {
            _selectedShift = 'Morning Shift';
          }
        } catch (e) {
          print('Error fetching gym shift mode: $e');
        }

        final staffVm = Provider.of<StaffViewModel>(context, listen: false);
        await staffVm.fetchRoles(gymId);
        final enabled = staffVm.getEnabledRoleNames();
        if (enabled.isNotEmpty && mounted) {
          setState(() {
            _selectedRole = enabled.first;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _aadhaarController.dispose();
    _addressController.dispose();
    _joiningDateController.dispose();
    _salaryController.dispose();
    _commissionController.dispose();
    _experienceController.dispose();
    _qualificationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // --- Photo Bottom Sheet Upload Simulation ---
  final ImagePicker _imagePicker = ImagePicker();

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
        directoryPath: '$gymId/staff',
        bytes: bytes,
      );

      setState(() {
        _profilePhotoUrl = publicUrl;
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

// Predefined date selections below

  // --- Date Pickers ---
  Future<void> _selectDate(BuildContext context, TextEditingController controller, {bool isDob = false}) async {
    DateTime initial = DateTime.now();
    if (controller.text.isNotEmpty) {
      try {
        initial = DateFormat('dd MMM yyyy').parse(controller.text);
      } catch (_) {}
    } else if (isDob) {
      initial = DateTime.now().subtract(const Duration(days: 365 * 25));
    }

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        controller.text = DateFormat('dd MMM yyyy').format(picked);
      });
    }
  }

  // --- Time Picker ---
  Future<void> _pickTime(BuildContext context, String currentVal, Function(String) onPicked) async {
    TimeOfDay initial = const TimeOfDay(hour: 9, minute: 0);
    try {
      final parts = currentVal.split(' ');
      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      int minute = int.parse(timeParts[1]);
      if (parts.length > 1 && parts[1].toUpperCase() == 'PM' && hour < 12) hour += 12;
      if (parts.length > 1 && parts[1].toUpperCase() == 'AM' && hour == 12) hour = 0;
      initial = TimeOfDay(hour: hour, minute: minute);
    } catch (_) {}

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final now = DateTime.now();
      final dt = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      onPicked(DateFormat('hh:mm a').format(dt));
    }
  }

  // --- Step Indicator Builder ---
  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_totalSteps, (index) {
          final stepNum = index + 1;
          final isCompleted = stepNum < _currentStep;
          final isCurrent = stepNum == _currentStep;

          return Row(
            children: [
              // Circle indicator
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppTheme.primary
                      : (isCompleted ? AppTheme.primary : Colors.transparent),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isCurrent || isCompleted ? AppTheme.primary : AppTheme.border,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: isCompleted
                    ? const Icon(Icons.check, color: Colors.white, size: 16)
                    : Text(
                        '$stepNum',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isCurrent ? Colors.white : AppTheme.textSecondary,
                        ),
                      ),
              ),
              // Connector Line
              if (stepNum < _totalSteps)
                Container(
                  width: 36,
                  height: 2,
                  color: isCompleted ? AppTheme.primary : AppTheme.border,
                ),
            ],
          );
        }),
      ),
    );
  }

  // --- Next Step logic ---
  void _nextStep() {
    bool isValid = false;
    if (_currentStep == 1) {
      isValid = _formKeyStep1.currentState!.validate();
    } else if (_currentStep == 2) {
      isValid = _formKeyStep2.currentState!.validate();
    } else if (_currentStep == 3) {
      isValid = _formKeyStep3.currentState!.validate();
    } else {
      isValid = true;
    }

    if (isValid) {
      setState(() {
        _currentStep++;
      });
    }
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
              'Upgrade Now',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // --- Save Staff logic ---
  Future<void> _handleSaveStaff() async {
    // Check subscription limits first
    try {
      final gymRepo = Provider.of<GymRepository>(context, listen: false);
      await gymRepo.checkSubscriptionLimit('staff');
    } catch (e) {
      if (e.toString().contains('limit_reached:')) {
        final message = e.toString().split('limit_reached:')[1];
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SubscriptionLimitScreen(
              limitType: 'staff',
              message: message,
            ),
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);
    final staffVm = Provider.of<StaffViewModel>(context, listen: false);

    final String staffId = _generateUUIDv4();
    final double salaryVal = double.tryParse(_salaryController.text) ?? 0.0;
    final double commissionVal = double.tryParse(_commissionController.text) ?? 0.0;

    final String formattedShift = _shiftType == 'both'
        ? '$_shift1Start - $_shift1End & $_shift2Start - $_shift2End'
        : '$_shift1Start - $_shift1End';

    final newStaff = Staff(
      id: staffId,
      name: _fullNameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _mobileController.text.trim(),
      role: _selectedRole,
      department: _selectedRole == 'Trainer' || _selectedRole == 'Personal Trainer' ? 'Training' : 'Administration',
      status: _isActiveStatus ? 'Active' : 'Inactive',
      joinDate: _joiningDateController.text,
      shift: formattedShift,
      experience: _experienceController.text.trim().isEmpty ? 'N/A' : _experienceController.text.trim(),
      rating: 5.0,
      sessionsCount: 0,
      membersTrained: 0,
      salary: salaryVal,
      salaryDue: salaryVal,
      avatar: _profilePhotoUrl.isEmpty
          ? 'https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?auto=format&fit=crop&q=80&w=200'
          : _profilePhotoUrl,
      gender: _selectedGender,
      dob: _dobController.text.trim(),
      aadhaar: _aadhaarController.text.trim(),
      emergencyName: '',
      emergencyPhone: '',
      address: _addressController.text.trim(),
      employmentType: _selectedEmployment,
      salaryType: _selectedSalaryType,
      commissionPercentage: commissionVal,
      qualification: _qualificationController.text.trim(),
      notes: _notesController.text.trim(),
      shiftType: _shiftType,
      shift1Start: _shift1Start,
      shift1End: _shift1End,
      shift2Start: _shift2Start,
      shift2End: _shift2End,
    );

    try {
      await staffVm.addStaffMember(newStaff);

      final String code = await staffVm.generateInvitation(
        recordId: staffId,
        name: newStaff.name,
        phone: newStaff.phone,
      );

      setState(() => _isLoading = false);

      if (mounted) {
        StaffSuccessDialog.show(
          context: context,
          staffName: newStaff.name,
          role: newStaff.role,
          invitationCode: code,
          phone: newStaff.phone,
          onDone: () {
            Navigator.pop(context);
            Navigator.pop(context);
          },
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save staff: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  // --- Step Widgets ---

  // Step 1: Personal Info
  Widget _buildStep1PersonalInfo() {
    return Form(
      key: _formKeyStep1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Photo section inside Step 1
          Center(
            child: GestureDetector(
              onTap: _showPhotoPickerBottomSheet,
              child: Stack(
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.border, width: 2),
                    ),
                    child: _isUploadingPhoto
                        ? const Center(
                            child: CircularProgressIndicator(color: AppTheme.primary),
                          )
                        : ClipOval(
                            child: _profilePhotoUrl.isNotEmpty
                                ? Image.network(_profilePhotoUrl, fit: BoxFit.cover)
                                : const Icon(
                                    Icons.photo_camera_outlined,
                                    color: AppTheme.primary,
                                    size: 36,
                                  ),
                          ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_a_photo_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              _profilePhotoUrl.isEmpty ? 'Tap to add photo' : 'Tap to change photo',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 24),

          _buildLabel('Full Name *'),
          TextFormField(
            controller: _fullNameController,
            decoration: const InputDecoration(hintText: 'Enter full name'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Full Name is required';
              return null;
            },
          ),
          const SizedBox(height: 16),

          _buildLabel('Mobile Number *'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80,
                child: TextFormField(
                  initialValue: '+91',
                  readOnly: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _mobileController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(hintText: 'Enter mobile number'),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Mobile number is required';
                    if (value.trim().length < 8) return 'Invalid phone number';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildLabel('Email (Optional)'),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(hintText: 'Enter email address'),
          ),
          const SizedBox(height: 16),

          _buildLabel('Gender'),
          DropdownButtonFormField<String>(
            value: _selectedGender,
            items: const [
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedGender = val);
            },
          ),
          const SizedBox(height: 16),

          _buildLabel('Date of Birth (Optional)'),
          TextFormField(
            controller: _dobController,
            readOnly: true,
            onTap: () => _selectDate(context, _dobController, isDob: true),
            decoration: const InputDecoration(
              hintText: 'Select date of birth',
              prefixIcon: Icon(Icons.cake_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          _buildLabel('Aadhar Card Number (Optional)'),
          TextFormField(
            controller: _aadhaarController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Enter Aadhar card number',
              prefixIcon: Icon(Icons.credit_card_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          _buildLabel('Address (Optional)'),
          TextFormField(
            controller: _addressController,
            decoration: const InputDecoration(
              hintText: 'Enter full address',
              prefixIcon: Icon(Icons.location_on_outlined, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  // Step 2: Work Info
  Widget _buildStep2WorkInfo() {
    final staffVm = Provider.of<StaffViewModel>(context);
    final enabledRoles = staffVm.getEnabledRoleNames();
    final rolesList = enabledRoles.isNotEmpty ? enabledRoles : ['Trainer', 'Personal Trainer', 'Manager', 'Receptionist'];
    
    if (!rolesList.contains(_selectedRole)) {
      _selectedRole = rolesList.first;
    }

    return Form(
      key: _formKeyStep2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLabel('Role *'),
          DropdownButtonFormField<String>(
            value: _selectedRole,
            items: rolesList.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedRole = val);
            },
          ),
          const SizedBox(height: 16),

          _buildLabel('Date of Joining *'),
          TextFormField(
            controller: _joiningDateController,
            readOnly: true,
            onTap: () => _selectDate(context, _joiningDateController),
            decoration: const InputDecoration(
              hintText: 'Select date',
              prefixIcon: Icon(Icons.calendar_month_outlined, size: 20),
            ),
          ),
          const SizedBox(height: 16),

          _buildLabel('Employment Type'),
          DropdownButtonFormField<String>(
            value: _selectedEmployment,
            items: _employments.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedEmployment = val);
            },
          ),
          const SizedBox(height: 16),

          _buildLabel('Gym Shift Configuration *'),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _shiftType = 'single'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _shiftType == 'single' ? AppTheme.primaryLight : AppTheme.surfaceGray,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _shiftType == 'single' ? AppTheme.primary : AppTheme.border,
                        width: _shiftType == 'single' ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      'Single Shift',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _shiftType == 'single' ? AppTheme.primary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _shiftType = 'both'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _shiftType == 'both' ? AppTheme.primaryLight : AppTheme.surfaceGray,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _shiftType == 'both' ? AppTheme.primary : AppTheme.border,
                        width: _shiftType == 'both' ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      'Both Shift (Double)',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: _shiftType == 'both' ? AppTheme.primary : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Shift 1 Timings
          Text('Shift 1 Timings', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickTime(context, _shift1Start, (val) => setState(() => _shift1Start = val)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_shift1Start, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                        const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('to', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickTime(context, _shift1End, (val) => setState(() => _shift1End = val)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(_shift1End, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                        const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_shiftType == 'both') ...[
            const SizedBox(height: 14),
            Text('Shift 2 Timings (Evening)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickTime(context, _shift2Start, (val) => setState(() => _shift2Start = val)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_shift2Start, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                          const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('to', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickTime(context, _shift2End, (val) => setState(() => _shift2End = val)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_shift2End, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                          const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),

          _buildLabel('Status *'),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isActiveStatus = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _isActiveStatus ? AppTheme.primary : AppTheme.surfaceGray,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _isActiveStatus ? AppTheme.primary : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      'Active',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: _isActiveStatus ? Colors.white : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _isActiveStatus = false),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: !_isActiveStatus ? AppTheme.primary : AppTheme.surfaceGray,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: !_isActiveStatus ? AppTheme.primary : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      'Inactive',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        color: !_isActiveStatus ? Colors.white : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Step 3: Salary Info
  Widget _buildStep3SalaryInfo() {
    return Form(
      key: _formKeyStep3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLabel('Salary Type *'),
          Row(
            children: _salaryTypes.map((type) {
              final isSel = _selectedSalaryType == type;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedSalaryType = type),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isSel ? AppTheme.primary : AppTheme.surfaceGray,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSel ? AppTheme.primary : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      type,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isSel ? Colors.white : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          if (_selectedSalaryType == 'Fixed Salary' || _selectedSalaryType == 'Both') ...[
            _buildLabel('Monthly Salary *'),
            TextFormField(
              controller: _salaryController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Enter fixed salary',
                prefixText: '₹ ',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Monthly Salary is required';
                if (double.tryParse(value) == null) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],

          if (_selectedSalaryType == 'Percentage' || _selectedSalaryType == 'Both') ...[
            _buildLabel('Commission Percentage *'),
            TextFormField(
              controller: _commissionController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Enter percentage',
                suffixText: ' %',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return 'Commission Percentage is required';
                if (double.tryParse(value) == null) return 'Enter a valid number';
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],

          if (_selectedSalaryType == 'Both') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primaryLight.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Staff will receive both fixed salary and percentage based on assigned sales/collections.',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primary, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Step 4: Other Info
  Widget _buildStep4OtherInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLabel('Experience'),
        TextFormField(
          controller: _experienceController,
          decoration: const InputDecoration(hintText: 'e.g. 3 Years'),
        ),
        const SizedBox(height: 16),

        _buildLabel('Qualification'),
        TextFormField(
          controller: _qualificationController,
          decoration: const InputDecoration(hintText: 'e.g. B.P.Ed / Certified Trainer'),
        ),
        const SizedBox(height: 16),

        _buildLabel('Notes (Optional)'),
        TextFormField(
          controller: _notesController,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Enter any notes'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          'Add New Staff',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () {
            if (_currentStep > 1) {
              setState(() {
                _currentStep--;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Column(
              children: [
                // Step Indicator Bar
                _buildStepIndicator(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _currentStep == 1
                          ? _buildStep1PersonalInfo()
                          : _currentStep == 2
                              ? _buildStep2WorkInfo()
                              : _currentStep == 3
                                  ? _buildStep3SalaryInfo()
                                  : _buildStep4OtherInfo(),
                    ),
                  ),
                ),
                // Footer Navigation Buttons
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      if (_currentStep > 1) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                _currentStep--;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.border),
                              foregroundColor: AppTheme.textPrimary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(
                              'Back',
                              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _currentStep < _totalSteps ? _nextStep : _handleSaveStaff,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            _currentStep < _totalSteps ? 'Next' : 'Save Staff',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, top: 4.0),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}
