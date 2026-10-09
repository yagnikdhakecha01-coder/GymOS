import 'dart:async';
import 'package:image_picker/image_picker.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/image_security_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/navigation/app_router.dart';
import '../../core/models/association_model.dart';
import 'auth_viewmodel.dart';
import 'role_selection_screen.dart';
import '../dashboard/main_navigation_holder.dart';
import '../../core/widgets/app_cached_avatar.dart';

class FirstTimeSetupScreen extends StatefulWidget {
  final bool isAddingAdditionalGym;
  const FirstTimeSetupScreen({super.key, this.isAddingAdditionalGym = false});

  @override
  State<FirstTimeSetupScreen> createState() => _FirstTimeSetupScreenState();
}

class _FirstTimeSetupScreenState extends State<FirstTimeSetupScreen> with SingleTickerProviderStateMixin {
  int _currentStep = 1;
  bool _isLoading = false;
  UserGymAssociation? _createdAssociation;

  // Upload state simulation
  bool _isUploadingLogo = false;
  double _logoUploadProgress = 0.0;
  String _gymLogoUrl = '';

  bool _isUploadingPhoto = false;
  double _photoUploadProgress = 0.0;
  String _profilePhotoUrl = '';

  // Form Keys
  final _formKeyStep1 = GlobalKey<FormState>();
  final _formKeyStep2 = GlobalKey<FormState>();

  // Step 1: Gym Info Controllers
  final _gymNameController = TextEditingController();
  String _selectedGymType = 'Commercial Gym';
  final _gymPhoneController = TextEditingController();
  final _gymEmailController = TextEditingController();
  final _gymAddressController = TextEditingController();
  final _gymCityController = TextEditingController();
  String _selectedState = 'Gujarat';
  String _selectedCountry = 'India';
  final _gymPinCodeController = TextEditingController();

  // Step 2: Owner Info Controllers
  final _ownerFullNameController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _ownerEmailController = TextEditingController();
  final _ownerDobController = TextEditingController();
  String _selectedExperience = '5+ Years';
  final String _ownerRole = 'Owner';

  // Dropdown Options
  final List<String> _gymTypes = [
    'Commercial Gym',
    'CrossFit Box',
    'Yoga Studio',
    'Pilates Studio',
    'MMA Academy',
    'Personal Training Studio',
    'Other'
  ];

  final List<String> _states = [
    'Gujarat',
    'Maharashtra',
    'Delhi',
    'Karnataka',
    'Tamil Nadu',
    'Uttar Pradesh',
    'Rajasthan',
    'Other'
  ];

  final List<String> _countries = [
    'India',
    'USA',
    'UK',
    'Canada',
    'Australia',
    'Singapore',
    'UAE',
    'Other'
  ];

  final List<String> _experiences = [
    'No Experience',
    '< 1 Year',
    '1-3 Years',
    '3-5 Years',
    '5+ Years'
  ];

  // Animation controller for Success page transitions
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    // Populate current auth user email and owner details if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (SupabaseService.client.auth.currentSession == null) {
        Navigator.pushAndRemoveUntil(
          context,
          AppRouter.scaleRoute(const RoleSelectionScreen()),
          (route) => false,
        );
        return;
      }

      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      if (authVm.currentUser != null) {
        _ownerEmailController.text = authVm.currentUser!.email ?? '';
        _gymEmailController.text = authVm.currentUser!.email ?? '';
      }

      if (widget.isAddingAdditionalGym) {
        final profile = authVm.currentProfile;
        if (profile != null) {
          _ownerFullNameController.text = profile.fullName ?? '';
          _ownerPhoneController.text = profile.phoneNumber ?? '';
          _ownerEmailController.text = profile.email;
          _ownerDobController.text = profile.dob ?? '';
          _selectedExperience = profile.experience ?? '5+ Years';
          _profilePhotoUrl = profile.photoUrl ?? '';
        }
      }
    });
  }

  @override
  void dispose() {
    _gymNameController.dispose();
    _gymPhoneController.dispose();
    _gymEmailController.dispose();
    _gymAddressController.dispose();
    _gymCityController.dispose();
    _gymPinCodeController.dispose();

    _ownerFullNameController.dispose();
    _ownerPhoneController.dispose();
    _ownerEmailController.dispose();
    _ownerDobController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  final ImagePicker _imagePicker = ImagePicker();

  Future<void> _pickAndUploadPhoto(bool isLogo, ImageSource source) async {
    try {
      final XFile? file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 85,
      );
      if (file == null) return;

      setState(() {
        if (isLogo) {
          _isUploadingLogo = true;
          _logoUploadProgress = 0.2;
        } else {
          _isUploadingPhoto = true;
          _photoUploadProgress = 0.2;
        }
      });

      final bytes = await file.readAsBytes();

      setState(() {
        if (isLogo) {
          _logoUploadProgress = 0.5;
        } else {
          _photoUploadProgress = 0.5;
        }
      });

      setState(() {
        if (isLogo) {
          _logoUploadProgress = 0.7;
        } else {
          _photoUploadProgress = 0.7;
        }
      });

      final publicUrl = await ImageSecurityService.uploadSecureImage(
        bucket: 'avatars',
        directoryPath: 'onboarding/${isLogo ? 'logos' : 'owners'}',
        bytes: bytes,
      );

      setState(() {
        if (isLogo) {
          _gymLogoUrl = publicUrl;
          _isUploadingLogo = false;
          _logoUploadProgress = 0.0;
        } else {
          _profilePhotoUrl = publicUrl;
          _isUploadingPhoto = false;
          _photoUploadProgress = 0.0;
        }
      });
    } catch (e) {
      setState(() {
        if (isLogo) {
          _isUploadingLogo = false;
          _logoUploadProgress = 0.0;
        } else {
          _isUploadingPhoto = false;
          _photoUploadProgress = 0.0;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload image: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _showImagePickerBottomSheet({required bool isLogo}) {
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
                  isLogo ? 'Add Gym Logo' : 'Add Profile Photo',
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
                    _pickAndUploadPhoto(isLogo, ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.primary),
                  title: Text('Capture Photo', style: GoogleFonts.inter(fontSize: 14)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context);
                    _pickAndUploadPhoto(isLogo, ImageSource.camera);
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

  // --- Date of Birth Picker ---
  Future<void> _selectDob(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(1995, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 16)), // Must be at least 16
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
      final formatted = DateFormat('dd MMM yyyy').format(picked);
      setState(() {
        _ownerDobController.text = formatted;
      });
    }
  }

  // --- Submit Final Data ---
  Future<void> _handleCreateGym() async {
    setState(() => _isLoading = true);
    final authVm = Provider.of<AuthViewModel>(context, listen: false);

    try {
      if (widget.isAddingAdditionalGym) {
        final newAssoc = await authVm.createAdditionalGym(
          gymName: _gymNameController.text,
          gymLogo: _gymLogoUrl.isEmpty ? 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=400&auto=format&fit=crop&q=80' : _gymLogoUrl,
          gymType: _selectedGymType,
          gymPhone: _gymPhoneController.text,
          gymEmail: _gymEmailController.text,
          gymAddress: _gymAddressController.text,
          gymCity: _gymCityController.text,
          gymState: _selectedState,
          gymCountry: _selectedCountry,
          gymPinCode: _gymPinCodeController.text,
        );
        _createdAssociation = newAssoc;
      } else {
        await authVm.completeOwnerOnboarding(
          gymName: _gymNameController.text,
          gymLogo: _gymLogoUrl.isEmpty ? 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=400&auto=format&fit=crop&q=80' : _gymLogoUrl,
          gymType: _selectedGymType,
          gymPhone: _gymPhoneController.text,
          gymEmail: _gymEmailController.text,
          gymAddress: _gymAddressController.text,
          gymCity: _gymCityController.text,
          gymState: _selectedState,
          gymCountry: _selectedCountry,
          gymPinCode: _gymPinCodeController.text,
          ownerFullName: _ownerFullNameController.text,
          ownerPhone: _ownerPhoneController.text,
          ownerEmail: _ownerEmailController.text,
          ownerPhoto: _profilePhotoUrl,
          ownerDob: _ownerDobController.text,
          ownerExperience: _selectedExperience,
        );
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentStep = 4;
        });
        _animationController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            content: Text('Setup failed: ${e.toString().replaceAll('Exception:', '')}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentStep > 1) {
          setState(() {
            if (widget.isAddingAdditionalGym && _currentStep == 3) {
              _currentStep = 1;
            } else {
              _currentStep--;
            }
          });
        } else {
          if (widget.isAddingAdditionalGym) {
            Navigator.pop(context);
          } else {
            final authVm = Provider.of<AuthViewModel>(context, listen: false);
            await authVm.logout();
            if (context.mounted) {
              Navigator.pushAndRemoveUntil(
                context,
                AppRouter.scaleRoute(const RoleSelectionScreen()),
                (route) => false,
              );
            }
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FC), // Apple off-white background
        appBar: _currentStep == 4 ? null : _buildAppBar(),
        body: SafeArea(
          child: _currentStep == 4 ? _buildSuccessStep() : _buildWizardSteps(),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppTheme.textPrimary, size: 18),
        onPressed: () async {
          if (_currentStep > 1) {
            setState(() {
              if (widget.isAddingAdditionalGym && _currentStep == 3) {
                _currentStep = 1;
              } else {
                _currentStep--;
              }
            });
          } else {
            if (widget.isAddingAdditionalGym) {
              Navigator.pop(context);
            } else {
              final authVm = Provider.of<AuthViewModel>(context, listen: false);
              await authVm.logout();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  AppRouter.scaleRoute(const RoleSelectionScreen()),
                  (route) => false,
                );
              }
            }
          }
        },
      ),
      title: Container(
        height: 6,
        constraints: const BoxConstraints(maxWidth: 200),
        child: Row(
          children: List.generate(widget.isAddingAdditionalGym ? 2 : 4, (index) {
            final stepMap = widget.isAddingAdditionalGym ? [1, 3] : [1, 2, 3, 4];
            final stepIndex = stepMap[index];
            final isFilled = stepIndex <= _currentStep;
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: isFilled ? AppTheme.primary : const Color(0xFFEDE9FE),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            );
          }),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Center(
            child: Text(
              widget.isAddingAdditionalGym
                  ? 'Step ${_currentStep == 1 ? 1 : 2} of 2'
                  : 'Step $_currentStep of 4',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        )
      ],
    );
  }

  Widget _buildWizardSteps() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_currentStep == 1) _buildStep1GymInfo(),
          if (_currentStep == 2) _buildStep2OwnerInfo(),
          if (_currentStep == 3) _buildStep3Review(),
        ],
      ),
    );
  }

  // --- Step 1: Gym Information Form ---
  Widget _buildStep1GymInfo() {
    return Form(
      key: _formKeyStep1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Headers
          Text(
            'Gym Information',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tell us about your gym',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),

          // Gym Name
          _buildLabel('Gym Name'),
          TextFormField(
            controller: _gymNameController,
            decoration: const InputDecoration(
              hintText: 'e.g. Iron Fitness Gym',
              prefixIcon: Icon(Icons.storefront_rounded),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Please enter gym name';
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Gym Logo Upload Simulation Card
          _buildLabel('Gym Logo'),
          GestureDetector(
            onTap: () => _showImagePickerBottomSheet(isLogo: true),
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 1.5),
                boxShadow: AppTheme.cardShadow,
              ),
              child: _buildLogoWidgetState(),
            ),
          ),
          const SizedBox(height: 20),

          // Gym Type Dropdown
          _buildLabel('Gym Type'),
          DropdownButtonFormField<String>(
            value: _selectedGymType,
            items: _gymTypes.map((type) {
              return DropdownMenuItem(value: type, child: Text(type));
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedGymType = val);
            },
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.fitness_center_rounded),
            ),
          ),
          const SizedBox(height: 20),

          // Phone Number Row (+91 country code input)
          _buildLabel('Phone Number'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 90,
                child: TextFormField(
                  initialValue: '🇮🇳 +91',
                  readOnly: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _gymPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '98765 43210',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter phone number';
                    if (value.trim().length < 8) return 'Invalid phone number';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Email
          _buildLabel('Email'),
          TextFormField(
            controller: _gymEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'info@ironfitness.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Please enter email';
              if (!value.contains('@')) return 'Invalid email address';
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Address
          _buildLabel('Address'),
          TextFormField(
            controller: _gymAddressController,
            decoration: const InputDecoration(
              hintText: '123, Fitness Street, City Center',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Please enter address';
              return null;
            },
          ),
          const SizedBox(height: 20),

          // City & State Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('City'),
                    TextFormField(
                      controller: _gymCityController,
                      decoration: const InputDecoration(hintText: 'Surat'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Please enter city';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('State'),
                    DropdownButtonFormField<String>(
                      value: _selectedState,
                      items: _states.map((state) {
                        return DropdownMenuItem(value: state, child: Text(state));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedState = val);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Country & PIN Code Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('Country'),
                    DropdownButtonFormField<String>(
                      value: _selectedCountry,
                      items: _countries.map((country) {
                        return DropdownMenuItem(value: country, child: Text(country));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCountry = val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('PIN Code'),
                    TextFormField(
                      controller: _gymPinCodeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '395001'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Enter PIN';
                        if (value.trim().length < 4) return 'Invalid';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Next Button
          ElevatedButton(
            onPressed: () {
              if (_formKeyStep1.currentState!.validate()) {
                setState(() => _currentStep = widget.isAddingAdditionalGym ? 3 : 2);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Next',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoWidgetState() {
    if (_isUploadingLogo) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: _logoUploadProgress,
                strokeWidth: 3,
                color: AppTheme.primary,
                backgroundColor: AppTheme.primaryLight,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Uploading logo... ${(100 * _logoUploadProgress).toInt()}%',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
            )
          ],
        ),
      );
    }

    if (_gymLogoUrl.isNotEmpty) {
      return Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(_gymLogoUrl, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap to change logo',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted, fontWeight: FontWeight.w500),
                )
              ],
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () {
                setState(() => _gymLogoUrl = '');
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Color(0xFFF3F4F6), shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
              ),
            ),
          ),
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_upload_outlined, color: AppTheme.primary, size: 28),
          const SizedBox(height: 8),
          Text(
            'Tap to upload logo',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 2: Owner Information Form ---
  Widget _buildStep2OwnerInfo() {
    return Form(
      key: _formKeyStep2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Headers
          Text(
            'Owner Information',
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tell us about yourself',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),

          // Owner Avatar Upload
          Center(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => _showImagePickerBottomSheet(isLogo: false),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.primary.withOpacity(0.2), width: 2),
                      boxShadow: AppTheme.cardShadow,
                    ),
                    child: ClipOval(
                      child: _buildOwnerPhotoState(),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => _showImagePickerBottomSheet(isLogo: false),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Upload Photo',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Full Name
          _buildLabel('Full Name'),
          TextFormField(
            controller: _ownerFullNameController,
            decoration: const InputDecoration(
              hintText: 'e.g. John Carter',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Please enter your name';
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Phone Number
          _buildLabel('Phone Number'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 90,
                child: TextFormField(
                  initialValue: '🇮🇳 +91',
                  readOnly: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _ownerPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: '98765 43210',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter phone number';
                    if (value.trim().length < 8) return 'Invalid phone number';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Email
          _buildLabel('Email'),
          TextFormField(
            controller: _ownerEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'owner@gmail.com',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Please enter email';
              if (!value.contains('@')) return 'Invalid email address';
              return null;
            },
          ),
          const SizedBox(height: 20),

          // DOB Picker
          _buildLabel('Date of Birth'),
          TextFormField(
            controller: _ownerDobController,
            readOnly: true,
            onTap: () => _selectDob(context),
            decoration: const InputDecoration(
              hintText: 'e.g. 12 Oct 1990',
              prefixIcon: Icon(Icons.calendar_today_outlined),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Please enter Date of Birth';
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Experience Dropdown
          _buildLabel('Experience in Fitness Industry'),
          DropdownButtonFormField<String>(
            value: _selectedExperience,
            items: _experiences.map((exp) {
              return DropdownMenuItem(value: exp, child: Text(exp));
            }).toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedExperience = val);
            },
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.fitness_center_rounded),
            ),
          ),
          const SizedBox(height: 20),

          // Role (Read-only)
          _buildLabel('Your Role in Gym'),
          TextFormField(
            initialValue: _ownerRole,
            readOnly: true,
            style: const TextStyle(color: AppTheme.textSecondary),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.admin_panel_settings_outlined),
              fillColor: Color(0xFFF3F4F6),
              filled: true,
            ),
          ),
          const SizedBox(height: 32),

          // Back & Next Buttons Row
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _currentStep = 1);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF3F4F6),
                    foregroundColor: AppTheme.textPrimary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    if (_formKeyStep2.currentState!.validate()) {
                      setState(() => _currentStep = 3);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Next',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerPhotoState() {
    if (_isUploadingPhoto) {
      return Center(
        child: CircularProgressIndicator(
          value: _photoUploadProgress,
          strokeWidth: 3,
          color: AppTheme.primary,
          backgroundColor: AppTheme.primaryLight,
        ),
      );
    }

    if (_profilePhotoUrl.isNotEmpty) {
      return Image.network(_profilePhotoUrl, fit: BoxFit.cover);
    }

    return const Icon(Icons.person, size: 54, color: AppTheme.textMuted);
  }

  // --- Step 3: Review Details Screen ---
  Widget _buildStep3Review() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Headers
        Text(
          'Review Your Details',
          style: GoogleFonts.inter(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Please review your information before we create your gym',
          style: GoogleFonts.inter(
            fontSize: 14,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 24),

        // Section 1: Gym Information Card
        _buildSectionHeader('Gym Information', onEdit: () => setState(() => _currentStep = 1)),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        _gymLogoUrl.isNotEmpty
                            ? _gymLogoUrl
                            : 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=400&auto=format&fit=crop&q=80',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _gymNameController.text,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        Text(
                          _selectedGymType,
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildReviewRow(Icons.phone_outlined, 'Phone', '+91 ${_gymPhoneController.text}'),
              const Divider(height: 18),
              _buildReviewRow(Icons.email_outlined, 'Email', _gymEmailController.text),
              const Divider(height: 18),
              _buildReviewRow(
                Icons.location_on_outlined,
                'Address',
                '${_gymAddressController.text}, ${_gymCityController.text}, $_selectedState, $_selectedCountry - ${_gymPinCodeController.text}',
              ),
              const Divider(height: 18),
              _buildReviewRow(Icons.access_time_rounded, 'Timing', '06:00 AM - 10:00 PM'),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Section 2: Owner Information Card
        _buildSectionHeader('Owner Information', onEdit: () => setState(() => _currentStep = 2)),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppCachedAvatar(
                    imageUrl: _profilePhotoUrl,
                    name: _ownerFullNameController.text,
                    size: 50,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _ownerFullNameController.text,
                          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        Text(
                          'Experience: $_selectedExperience',
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildReviewRow(Icons.person_outline_rounded, 'Name', _ownerFullNameController.text),
              const Divider(height: 18),
              _buildReviewRow(Icons.phone_outlined, 'Phone', '+91 ${_ownerPhoneController.text}'),
              const Divider(height: 18),
              _buildReviewRow(Icons.email_outlined, 'Email', _ownerEmailController.text),
              const Divider(height: 18),
              _buildReviewRow(Icons.cake_outlined, 'DOB', _ownerDobController.text),
              const Divider(height: 18),
              _buildReviewRow(Icons.badge_outlined, 'Role', _ownerRole),
            ],
          ),
        ),
        const SizedBox(height: 32),

        // Action Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() => _currentStep = widget.isAddingAdditionalGym ? 1 : 2);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF3F4F6),
                  foregroundColor: AppTheme.textPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _handleCreateGym,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                      )
                    : Text(
                        'Create My Gym',
                        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, {required VoidCallback onEdit}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primary),
          ),
          GestureDetector(
            onTap: onEdit,
            child: Row(
              children: [
                const Icon(Icons.edit_outlined, size: 14, color: AppTheme.primary),
                const SizedBox(width: 4),
                Text(
                  'Edit',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildReviewRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 12),
        Container(
          width: 80,
          child: Text(
            label,
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
        ),
      ],
    );
  }

  // --- Step 4: Success Screen ---
  Widget _buildSuccessStep() {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Success Animation Checkmark
            ScaleTransition(
              scale: _scaleAnimation,
              child: Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check_rounded, size: 48, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Congratulations Headers
            FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  Text(
                    'Your Gym is Ready!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Congratulations! Your gym has been\nsuccessfully created.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Premium checklist points card
            FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  children: [
                    _buildCheckPoint('Your gym is all set to go'),
                    const SizedBox(height: 16),
                    _buildCheckPoint('You can now add members and staff'),
                    const SizedBox(height: 16),
                    _buildCheckPoint('Manage your gym easily'),
                    const SizedBox(height: 16),
                    _buildCheckPoint('Track growth and achieve more together'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),

            // Go to Dashboard or Gym Switcher options
            FadeTransition(
              opacity: _fadeAnimation,
              child: widget.isAddingAdditionalGym
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            if (_createdAssociation != null) {
                              await authVm.selectAssociation(_createdAssociation!);
                            }
                            if (mounted) {
                              Navigator.pushAndRemoveUntil(
                                context,
                                AppRouter.scaleRoute(const MainNavigationHolder()),
                                (route) => false,
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            'Switch To This Gym',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: () {
                            Navigator.pushAndRemoveUntil(
                              context,
                              AppRouter.scaleRoute(const MainNavigationHolder()),
                              (route) => false,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.primary),
                            foregroundColor: AppTheme.primary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: Text(
                            'Stay On Current Gym',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ],
                    )
                  : ElevatedButton(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(
                          context,
                          AppRouter.scaleRoute(const MainNavigationHolder()),
                          (route) => false,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Go to Dashboard',
                            style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckPoint(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 14, color: AppTheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, top: 4.0),
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
