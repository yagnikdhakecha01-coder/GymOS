import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
import '../authentication/auth_viewmodel.dart';
import '../receptionist/receptionist_viewmodel.dart';
import '../gym_settings/gym_settings_viewmodel.dart';
import '../../core/models/association_model.dart';
import '../../core/models/user_profile.dart';
import '../../core/services/supabase_service.dart';
import '../../core/services/image_security_service.dart';
import '../../core/widgets/app_cached_avatar.dart';
import '../../core/widgets/invitation_share_sheet.dart';
import '../../core/models/gym_rules_model.dart';
import '../../core/repository/gym_repository.dart';
import '../member_app/widgets/member_rules_agreement_dialog.dart';
import '../../core/models/attendance.dart';
import '../attendance/attendance_viewmodel.dart';
import '../attendance/owner_history_screen.dart';
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

  // Gym Rules Agreement tracking (Phase 09)
  MemberAgreementRecord? _memberAgreement;

  double _activeCommissionPercentage = 0.0;
  bool _loadingPt = false;
  bool _isUploadingPhoto = false;

  Future<void> _pickAndUploadPhoto(ImageSource source, Member member) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (pickedFile == null) return;

      final file = File(pickedFile.path);
      final bytes = await file.readAsBytes();

      if (mounted) {
        setState(() => _isUploadingPhoto = true);
      }

      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? 'default_gym';

      final publicUrl = await ImageSecurityService.uploadSecureImage(
        bucket: 'avatars',
        directoryPath: '$gymId/members',
        bytes: bytes,
      );

      final updated = member.copyWith(avatar: publicUrl);
      final membersVm = Provider.of<MembersViewModel>(context, listen: false);
      await membersVm.updateMemberProfile(updated);

      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Member photo updated successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload photo: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _showFullPhotoDialog(BuildContext context, Member member) {
    if (member.avatar.isEmpty) {
      _showPhotoPickerBottomSheet(context, member);
      return;
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'MemberPhoto',
      barrierColor: Colors.black.withOpacity(0.92),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (dialogContext, anim1, anim2) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: Column(
              children: [
                // Header with Member Details & Close Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          AppCachedAvatar(
                            imageUrl: member.avatar,
                            name: member.name,
                            size: 36,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.name,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Profile Photo',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                ),
                // Center Zoomable Photo with InteractiveViewer
                Expanded(
                  child: Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(dialogContext).size.height * 0.65,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.6),
                              blurRadius: 28,
                              spreadRadius: 6,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.network(
                            member.avatar,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return SizedBox(
                                height: 260,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (_, __, ___) => Container(
                              height: 260,
                              color: Colors.white10,
                              child: const Center(
                                child: Icon(Icons.broken_image_rounded, color: Colors.white54, size: 64),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Bottom Action Button: Change Photo
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            _showPhotoPickerBottomSheet(context, member);
                          },
                          icon: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 20),
                          label: Text(
                            'Change Photo',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white38),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  void _showPhotoPickerBottomSheet(BuildContext context, Member member) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Member Photo',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                Text(
                  member.name,
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.photo_library_outlined, color: AppTheme.primary),
                  ),
                  title: Text('Upload from Gallery', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text('Choose a photo from your device', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndUploadPhoto(ImageSource.gallery, member);
                  },
                ),
                const Divider(height: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.camera_alt_outlined, color: AppTheme.primary),
                  ),
                  title: Text('Take Photo', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text('Capture new photo with camera', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndUploadPhoto(ImageSource.camera, member);
                  },
                ),
                if (member.avatar.isNotEmpty) ...[
                  const Divider(height: 16),
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
                    ),
                    title: Text('Remove Photo', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.danger)),
                    subtitle: Text('Revert to initial avatar', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      final updated = member.copyWith(avatar: '');
                      final membersVm = Provider.of<MembersViewModel>(context, listen: false);
                      await membersVm.updateMemberProfile(updated);
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Member photo removed.')),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _shareInvitationCode(String code, String phone) {
    InvitationShareSheet.show(
      context: context,
      invitationCode: code,
      phone: phone,
      recipientName: widget.member.name,
      isStaff: false,
    );
  }

  // Notes Controllers
  final _ownerNotesController = TextEditingController();
  final _trainerNotesController = TextEditingController();
  final _privateNotesController = TextEditingController();
  bool _isSavingNotes = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadInvitation();
        _loadPtAssignment();
        _loadAgreement();
      }
    });
    // Load actual notes specific to this member without hardcoded dummy defaults
    _ownerNotesController.text = widget.member.notes.isNotEmpty
        ? widget.member.notes
        : (widget.member.extraFields['owner_notes']?.toString() ?? '');
    _trainerNotesController.text = widget.member.extraFields['trainer_notes']?.toString() ?? '';
    _privateNotesController.text = widget.member.extraFields['private_notes']?.toString() ?? '';
  }

  Future<void> _saveMemberNotes(Member currentMember) async {
    setState(() => _isSavingNotes = true);
    try {
      final membersVm = Provider.of<MembersViewModel>(context, listen: false);
      final updatedExtra = Map<String, dynamic>.from(currentMember.extraFields);
      final ownerNote = _ownerNotesController.text.trim();
      final trainerNote = _trainerNotesController.text.trim();
      final privateNote = _privateNotesController.text.trim();

      updatedExtra['owner_notes'] = ownerNote;
      updatedExtra['trainer_notes'] = trainerNote;
      updatedExtra['private_notes'] = privateNote;

      final updated = currentMember.copyWith(
        notes: ownerNote,
        extraFields: updatedExtra,
      );

      await membersVm.updateMemberProfile(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Notes saved successfully!'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save notes: $e'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingNotes = false);
      }
    }
  }

  Future<void> _loadAgreement() async {
    final authVm = Provider.of<AuthViewModel>(context, listen: false);
    final repo = Provider.of<GymRepository>(context, listen: false);
    final gymId = authVm.activeAssociation?.gymId ?? (authVm.gymInfo?['id']?.toString() ?? '');
    if (gymId.isEmpty) return;

    final rec = await repo.fetchMemberAgreement(gymId, widget.member.id);
    if (mounted) {
      setState(() {
        _memberAgreement = rec;
      });
    }
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
    var invite = await membersVm.getLatestInvitation(widget.member.id);
    if (invite == null) {
      try {
        final code = await membersVm.generateInvitation(
          recordId: widget.member.id,
          name: widget.member.name,
          phone: widget.member.phone,
        );
        invite = {
          'invitation_code': code,
          'status': 'Pending',
          'code_used': false,
          'member_id': widget.member.id,
        };
      } catch (e) {
        debugPrint('Auto invitation generation error: $e');
      }
    }
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
                                phoneNumber: member.phone,
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
                                phoneNumber: member.phone,
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

  void _showEditMemberDetailsSheet(BuildContext context, Member member) {
    final membersVm = Provider.of<MembersViewModel>(context, listen: false);
    final workoutVm = Provider.of<WorkoutViewModel>(context, listen: false);
    final dietVm = Provider.of<DietViewModel>(context, listen: false);
    final settingsVm = Provider.of<GymSettingsViewModel>(context, listen: false);

    final nameController = TextEditingController(text: member.name);
    final phoneController = TextEditingController(text: member.phone);
    final emailController = TextEditingController(text: member.email);
    final addressController = TextEditingController(text: member.extraFields['address']?.toString() ?? '');
    final notesController = TextEditingController(text: member.notes);
    final biometricPinController = TextEditingController(text: member.biometricPin != null ? member.biometricPin.toString() : '');
    
    DateTime? selectedDob;
    final dobStr = member.extraFields['dob']?.toString() ?? '';
    if (dobStr.isNotEmpty) {
      try {
        selectedDob = DateTime.parse(dobStr);
      } catch (_) {}
    }

    String selectedGender = member.extraFields['gender']?.toString() ?? 'Male';
    if (!['Male', 'Female', 'Other'].contains(selectedGender)) {
      selectedGender = 'Male';
    }

    String selectedBloodGroup = member.extraFields['bloodGroup']?.toString() ?? 'O+';
    final bloodGroups = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-', 'Not Specified'];
    if (!bloodGroups.contains(selectedBloodGroup)) {
      selectedBloodGroup = 'Not Specified';
    }

    String selectedGoal = member.extraFields['goal']?.toString() ?? 'General Fitness';
    final goalsList = settingsVm.goals.map((g) => g.name).toList();
    if (goalsList.isEmpty) {
      goalsList.addAll([
        'Weight Loss',
        'Muscle Gain',
        'Fat Loss',
        'General Fitness',
        'Strength Training',
        'Endurance',
        'Body Recomposition',
      ]);
    }
    if (!goalsList.contains(selectedGoal)) {
      goalsList.insert(0, selectedGoal);
    }

    String selectedWorkoutId = member.assignedWorkoutId;
    String selectedDietId = member.assignedDietId;

    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Edit Member Details & Goals',
                          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Full Name *', prefixIcon: Icon(Icons.person_outline_rounded)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Phone Number *', prefixIcon: Icon(Icons.phone_outlined)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: biometricPinController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Face & Biometric PIN / User ID',
                        prefixIcon: const Icon(Icons.face_retouching_natural_rounded, color: AppTheme.primary),
                        hintText: 'e.g. 101, 1024',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.auto_awesome_rounded, size: 18, color: AppTheme.primary),
                          tooltip: 'Auto-Assign Next Free PIN',
                          onPressed: () async {
                            final authVm = Provider.of<AuthViewModel>(context, listen: false);
                            final gymId = authVm.activeAssociation?.gymId ?? authVm.gymInfo?['id'] ?? '';
                            if (gymId.isEmpty) return;
                            try {
                              final res = await SupabaseService.client.rpc('get_next_available_biometric_pin', params: {'p_gym_id': gymId});
                              if (res != null && res['next_pin'] != null) {
                                biometricPinController.text = res['next_pin'].toString();
                              }
                            } catch (_) {}
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email Address', prefixIcon: Icon(Icons.email_outlined)),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDob ?? DateTime(1998, 1, 1),
                          firstDate: DateTime(1940),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setSheetState(() => selectedDob = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.cake_outlined, size: 20, color: AppTheme.textSecondary),
                                const SizedBox(width: 10),
                                Text(
                                  selectedDob != null ? DateFormat('dd MMM yyyy').format(selectedDob!) : 'Select Date of Birth',
                                  style: GoogleFonts.inter(fontSize: 13, color: selectedDob != null ? AppTheme.textPrimary : AppTheme.textMuted),
                                ),
                              ],
                            ),
                            const Icon(Icons.calendar_today_rounded, size: 16, color: AppTheme.primary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedGender,
                            decoration: const InputDecoration(labelText: 'Gender'),
                            items: ['Male', 'Female', 'Other'].map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (val) {
                              if (val != null) setSheetState(() => selectedGender = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: selectedBloodGroup,
                            decoration: const InputDecoration(labelText: 'Blood Group'),
                            items: bloodGroups.map((bg) => DropdownMenuItem(value: bg, child: Text(bg))).toList(),
                            onChanged: (val) {
                              if (val != null) setSheetState(() => selectedBloodGroup = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressController,
                      decoration: const InputDecoration(labelText: 'Address', prefixIcon: Icon(Icons.location_on_outlined)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Notes / Medical Info', prefixIcon: Icon(Icons.notes_rounded)),
                    ),
                    const SizedBox(height: 16),

                    // --- FITNESS GOAL & DYNAMIC PROGRAM ASSIGNMENT ---
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryLight.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.track_changes_rounded, color: AppTheme.primary, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Fitness Goal & Plan Alignment',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Goal Dropdown
                          DropdownButtonFormField<String>(
                            value: selectedGoal,
                            decoration: const InputDecoration(
                              labelText: 'Fitness Goal *',
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: Icon(Icons.flag_outlined, color: AppTheme.primary),
                            ),
                            items: goalsList.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setSheetState(() {
                                  selectedGoal = val;
                                });
                              }
                            },
                          ),
                          const SizedBox(height: 12),

                          // Workout Plan Dropdown (Matching Goal highlighted)
                          DropdownButtonFormField<String>(
                            value: workoutVm.workouts.any((w) => w.id == selectedWorkoutId) ? selectedWorkoutId : '',
                            decoration: InputDecoration(
                              labelText: 'Workout Routine',
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: const Icon(Icons.fitness_center_rounded, color: Colors.blue),
                              helperText: 'Showing plans matching "$selectedGoal"',
                              helperStyle: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                            items: [
                              const DropdownMenuItem(value: '', child: Text('No Workout Assigned')),
                              ...workoutVm.workouts.map((w) {
                                final matches = w.goal.toLowerCase() == selectedGoal.toLowerCase();
                                return DropdownMenuItem(
                                  value: w.id,
                                  child: Text(
                                    matches ? '${w.title} (${w.goal}) ⭐' : '${w.title} (${w.goal})',
                                    style: GoogleFonts.inter(
                                      fontWeight: matches ? FontWeight.bold : FontWeight.normal,
                                      color: matches ? AppTheme.primary : AppTheme.textPrimary,
                                    ),
                                  ),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              if (val != null) setSheetState(() => selectedWorkoutId = val);
                            },
                          ),
                          const SizedBox(height: 12),

                          // Diet Plan Dropdown (Matching Goal highlighted)
                          DropdownButtonFormField<String>(
                            value: dietVm.diets.any((d) => d.id == selectedDietId) ? selectedDietId : '',
                            decoration: InputDecoration(
                              labelText: 'Diet Plan',
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: const Icon(Icons.restaurant_rounded, color: Colors.orange),
                              helperText: 'Showing diets matching "$selectedGoal"',
                              helperStyle: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                            ),
                            items: [
                              const DropdownMenuItem(value: '', child: Text('No Diet Assigned')),
                              ...dietVm.diets.map((d) {
                                final matches = d.goal.toLowerCase() == selectedGoal.toLowerCase();
                                return DropdownMenuItem(
                                  value: d.id,
                                  child: Text(
                                    matches ? '${d.title} (${d.goal}) ⭐' : '${d.title} (${d.goal})',
                                    style: GoogleFonts.inter(
                                      fontWeight: matches ? FontWeight.bold : FontWeight.normal,
                                      color: matches ? AppTheme.primary : AppTheme.textPrimary,
                                    ),
                                  ),
                                );
                              }),
                            ],
                            onChanged: (val) {
                              if (val != null) setSheetState(() => selectedDietId = val);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: isSaving ? null : () async {
                        final updatedName = nameController.text.trim();
                        final updatedPhone = phoneController.text.trim();
                        if (updatedName.isEmpty || updatedPhone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Name and Phone cannot be empty.')),
                          );
                          return;
                        }

                        setSheetState(() => isSaving = true);

                        final newExtra = Map<String, dynamic>.from(member.extraFields);
                        if (selectedDob != null) {
                          newExtra['dob'] = selectedDob!.toIso8601String().split('T').first;
                        }
                        newExtra['gender'] = selectedGender;
                        newExtra['bloodGroup'] = selectedBloodGroup;
                        newExtra['address'] = addressController.text.trim();
                        newExtra['goal'] = selectedGoal;

                        final updated = member.copyWith(
                          name: updatedName,
                          phone: updatedPhone,
                          email: emailController.text.trim(),
                          notes: notesController.text.trim(),
                          assignedWorkoutId: selectedWorkoutId,
                          assignedDietId: selectedDietId,
                          extraFields: newExtra,
                          biometricPin: int.tryParse(biometricPinController.text.trim()),
                        );

                        try {
                          await membersVm.saveMember(updated);

                          if (Navigator.canPop(sheetContext)) {
                            Navigator.pop(sheetContext);
                          }

                          if (mounted) {
                            setState(() {});
                            SuccessDialog.show(
                              context,
                              title: 'Member Details Updated!',
                              message: 'Goal and profile information for ${updated.name} have been updated successfully.',
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            setSheetState(() => isSaving = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed to update member: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      child: isSaving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Save Changes', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
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

  void _showEditBodyMeasurementsSheet(BuildContext context, Member member) {
    final membersVm = Provider.of<MembersViewModel>(context, listen: false);
    final extra = member.extraFields;
    final Map<String, dynamic> measurements = (extra['measurements'] is Map<String, dynamic>)
        ? extra['measurements'] as Map<String, dynamic>
        : (extra['measurements'] is Map ? Map<String, dynamic>.from(extra['measurements'] as Map) : <String, dynamic>{});

    final heightController = TextEditingController(text: measurements['height']?.toString() ?? extra['height']?.toString() ?? '');
    final weightController = TextEditingController(text: measurements['weight']?.toString() ?? extra['weight']?.toString() ?? '');
    final chestController = TextEditingController(text: measurements['chest']?.toString() ?? extra['chest']?.toString() ?? '');
    final waistController = TextEditingController(text: measurements['waist']?.toString() ?? extra['waist']?.toString() ?? '');
    final bicepsController = TextEditingController(text: measurements['biceps']?.toString() ?? extra['biceps']?.toString() ?? '');
    final hipController = TextEditingController(text: measurements['hip']?.toString() ?? extra['hip']?.toString() ?? '');

    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Update Body Measurements',
                          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.textSecondary),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: heightController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Height (cm)', prefixIcon: Icon(Icons.height_rounded)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: weightController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Weight (kg)', prefixIcon: Icon(Icons.monitor_weight_outlined)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: chestController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Chest (in)', prefixIcon: Icon(Icons.fitness_center_rounded)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: waistController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Waist (in)', prefixIcon: Icon(Icons.straighten_rounded)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: bicepsController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Biceps (in)', prefixIcon: Icon(Icons.accessibility_new_rounded)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: hipController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Hip (in)', prefixIcon: Icon(Icons.attribution_rounded)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: isSaving ? null : () async {
                        setSheetState(() => isSaving = true);

                        final newMeasurements = {
                          'height': heightController.text.trim(),
                          'weight': weightController.text.trim(),
                          'chest': chestController.text.trim(),
                          'waist': waistController.text.trim(),
                          'biceps': bicepsController.text.trim(),
                          'hip': hipController.text.trim(),
                          'updated_at': DateTime.now().toIso8601String(),
                        };

                        final newExtra = Map<String, dynamic>.from(member.extraFields);
                        newExtra['measurements'] = newMeasurements;
                        newExtra['height'] = heightController.text.trim();
                        newExtra['weight'] = weightController.text.trim();
                        newExtra['chest'] = chestController.text.trim();
                        newExtra['waist'] = waistController.text.trim();
                        newExtra['biceps'] = bicepsController.text.trim();
                        newExtra['hip'] = hipController.text.trim();

                        final updated = member.copyWith(extraFields: newExtra);
                        await membersVm.saveMember(updated);

                        if (Navigator.canPop(sheetContext)) {
                          Navigator.pop(sheetContext);
                        }

                        if (mounted) {
                          setState(() {});
                          SuccessDialog.show(
                            context,
                            title: 'Body Measurements Saved!',
                            message: 'Measurements for ${member.name} have been updated successfully.',
                          );
                        }
                      },
                      child: isSaving
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text('Save Measurements', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
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
                                phoneNumber: member.phone,
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
                                phoneNumber: member.phone,
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
    final memberGoal = (member.extraFields['goal'] ?? '').toString().trim();
    final currentWorkout = workouts.where((w) => w.id == member.assignedWorkoutId).firstOrNull;
    WorkoutPlan? selectedWorkout = currentWorkout ??
        (memberGoal.isNotEmpty ? workouts.where((w) => w.goal.toLowerCase() == memberGoal.toLowerCase()).firstOrNull : null) ??
        (workouts.isNotEmpty ? workouts.first : null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.fitness_center_rounded, color: AppTheme.primary, size: 22),
                            const SizedBox(width: 8),
                            Text('Assign Workout Routine', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    if (memberGoal.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.flag_outlined, size: 16, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Member Goal: $memberGoal  (Recommended plans marked with ⭐)',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('Select Workout Plan *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<WorkoutPlan>(
                      value: selectedWorkout,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppTheme.surfaceGray,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      items: workouts.map((w) {
                        final isGoalMatch = memberGoal.isNotEmpty && w.goal.toLowerCase() == memberGoal.toLowerCase();
                        return DropdownMenuItem(
                          value: w,
                          child: Text(
                            isGoalMatch ? '${w.title} (${w.goal}) ⭐' : '${w.title} (${w.goal})',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: isGoalMatch ? FontWeight.bold : FontWeight.normal,
                              color: isGoalMatch ? AppTheme.primary : AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setSheetState(() => selectedWorkout = val);
                      },
                    ),
                    if (selectedWorkout != null) ...[
                      const SizedBox(height: 16),
                      Text('Plan Details', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppTheme.surfaceGray, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          children: [
                            _buildDetailIconRow(Icons.timer_outlined, 'Duration', '8 Weeks'),
                            const Divider(height: 14),
                            _buildDetailIconRow(Icons.emoji_events_outlined, 'Focus / Goal', selectedWorkout!.goal),
                            const Divider(height: 14),
                            _buildDetailIconRow(Icons.bar_chart_rounded, 'Difficulty Level', selectedWorkout!.difficulty),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedWorkout == null) return;
                        Navigator.pop(sheetContext);
                        await membersVm.assignWorkout(member.id, selectedWorkout!.id);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Workout routine assigned: ${selectedWorkout!.title}')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text('Assign Workout', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
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

  void _showAssignDietBottomSheet(MembersViewModel membersVm, Member member) {
    final dietVm = Provider.of<DietViewModel>(context, listen: false);
    final diets = dietVm.diets;
    final memberGoal = (member.extraFields['goal'] ?? '').toString().trim();
    final currentDiet = diets.where((d) => d.id == member.assignedDietId).firstOrNull;
    DietPlan? selectedDiet = currentDiet ??
        (memberGoal.isNotEmpty ? diets.where((d) => d.goal.toLowerCase() == memberGoal.toLowerCase()).firstOrNull : null) ??
        (diets.isNotEmpty ? diets.first : null);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.restaurant_rounded, color: Colors.orange, size: 22),
                            const SizedBox(width: 8),
                            Text('Assign Diet Plan', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    if (memberGoal.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.flag_outlined, size: 16, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Member Goal: $memberGoal  (Recommended plans marked with ⭐)',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text('Select Diet Plan *', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<DietPlan>(
                      value: selectedDiet,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: AppTheme.surfaceGray,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      items: diets.map((d) {
                        final isGoalMatch = memberGoal.isNotEmpty && d.goal.toLowerCase() == memberGoal.toLowerCase();
                        return DropdownMenuItem(
                          value: d,
                          child: Text(
                            isGoalMatch ? '${d.title} (${d.goal}) ⭐' : '${d.title} (${d.goal})',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: isGoalMatch ? FontWeight.bold : FontWeight.normal,
                              color: isGoalMatch ? Colors.orange.shade900 : AppTheme.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setSheetState(() => selectedDiet = val);
                      },
                    ),
                    if (selectedDiet != null) ...[
                      const SizedBox(height: 16),
                      Text('Plan Details', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppTheme.surfaceGray, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          children: [
                            _buildDetailIconRow(Icons.restaurant_menu_rounded, 'Diet Type', selectedDiet!.title),
                            const Divider(height: 14),
                            _buildDetailIconRow(Icons.local_fire_department_outlined, 'Calories', '${selectedDiet!.calories ?? 2000} kcal / Day'),
                            const Divider(height: 14),
                            _buildDetailIconRow(Icons.emoji_events_outlined, 'Target Goal', selectedDiet!.goal),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () async {
                        if (selectedDiet == null) return;
                        Navigator.pop(sheetContext);
                        await membersVm.assignDiet(member.id, selectedDiet!.id);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Diet plan assigned: ${selectedDiet!.title}')),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text('Assign Diet', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
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
            InkWell(
              onTap: _isUploadingPhoto ? null : () => _showFullPhotoDialog(context, member),
              onLongPress: _isUploadingPhoto
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      _showPhotoPickerBottomSheet(context, member);
                    },
              borderRadius: BorderRadius.circular(40),
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: !AppCachedAvatar.isDummyUrl(member.avatar)
                        ? ResizeImage(NetworkImage(member.avatar), width: 160, height: 160)
                        : null,
                    backgroundColor: AppCachedAvatar.getColorPair(member.name).bg,
                    child: _isUploadingPhoto
                        ? const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 3, color: AppTheme.primary),
                          )
                        : (AppCachedAvatar.isDummyUrl(member.avatar)
                            ? Text(
                                member.name.isNotEmpty ? member.name[0].toUpperCase() : 'M',
                                style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.bold, color: AppCachedAvatar.getColorPair(member.name).text),
                              )
                            : null),
                  ),
                  if (!_isUploadingPhoto)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _showPhotoPickerBottomSheet(context, member);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.face_retouching_natural_rounded, size: 12, color: AppTheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        member.biometricPin != null
                            ? 'Face & Biometric PIN: #${member.biometricPin}'
                            : 'Face/Biometric: Not linked',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: member.biometricPin != null ? AppTheme.primary : AppTheme.textMuted,
                        ),
                      ),
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
        const SizedBox(height: 16),

        // Gym Rules Agreement Status Card (Phase 09)
        _buildRulesAgreementCard(),
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

        // 3.8 Fitness Goal & Plans Card
        Consumer2<WorkoutViewModel, DietViewModel>(
          builder: (context, workoutVm, dietVm, _) {
            final memberGoal = (member.extraFields['goal'] ?? 'General Fitness').toString();
            final currentWorkout = workoutVm.workouts.where((w) => w.id == member.assignedWorkoutId).firstOrNull;
            final currentDiet = dietVm.diets.where((d) => d.id == member.assignedDietId).firstOrNull;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('FITNESS GOAL & ASSIGNED PLANS', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
                    GestureDetector(
                      onTap: () => _showEditMemberDetailsSheet(context, member),
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // Goal Row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.track_changes_rounded, color: AppTheme.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Current Goal', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                const SizedBox(height: 2),
                                Text(memberGoal, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Goal',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      // Workout Row
                      InkWell(
                        onTap: () => _showAssignWorkoutBottomSheet(membersVm, member),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.fitness_center_rounded, color: Colors.blue, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Assigned Workout Routine', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                    const SizedBox(height: 2),
                                    Text(
                                      currentWorkout?.title ?? 'No Routine Assigned',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: currentWorkout != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                                      ),
                                    ),
                                    if (currentWorkout != null)
                                      Text(
                                        'Focus: ${currentWorkout.goal} • ${currentWorkout.difficulty}',
                                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 20),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 24),
                      // Diet Row
                      InkWell(
                        onTap: () => _showAssignDietBottomSheet(membersVm, member),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.restaurant_rounded, color: Colors.orange, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Assigned Diet Plan', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                    const SizedBox(height: 2),
                                    Text(
                                      currentDiet?.title ?? 'No Diet Assigned',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: currentDiet != null ? AppTheme.textPrimary : AppTheme.textSecondary,
                                      ),
                                    ),
                                    if (currentDiet != null)
                                      Text(
                                        'Target: ${currentDiet.goal} • ${currentDiet.calories ?? 2000} kcal',
                                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textSecondary),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, color: AppTheme.textSecondary, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),

        // 4. Member Information
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('MEMBER INFO', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
            GestureDetector(
              onTap: () => _showEditMemberDetailsSheet(context, member),
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
              _buildRowInfo(Icons.flag_outlined, 'Fitness Goal', member.extraFields['goal'] ?? 'General Fitness'),
              const Divider(height: 1),
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
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('BODY MEASUREMENTS', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 0.5)),
            GestureDetector(
              onTap: () => _showEditBodyMeasurementsSheet(context, member),
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

  Widget _buildRulesAgreementCard() {
    final hasAgreed = _memberAgreement != null && _memberAgreement!.agreed;
    final dateStr = hasAgreed
        ? DateFormat('dd MMM yyyy, hh:mm a').format(_memberAgreement!.agreedAt)
        : null;
    final langEnum = hasAgreed ? RuleLanguage.fromCode(_memberAgreement!.language) : null;

    return CustomCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasAgreed ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasAgreed ? Icons.verified_user_rounded : Icons.gavel_rounded,
                  color: hasAgreed ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gym Rules & Legal Agreement',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasAgreed
                          ? 'Agreed on $dateStr (v${_memberAgreement!.rulesVersion})'
                          : 'Member has not accepted gym rules yet',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: hasAgreed ? const Color(0xFF047857) : const Color(0xFFB45309),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasAgreed ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasAgreed ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                  ),
                ),
                child: Text(
                  hasAgreed ? '✅ Agreed' : '⚠️ Pending',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: hasAgreed ? const Color(0xFF047857) : const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          if (hasAgreed) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Language: ',
                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                    Text(
                      '${langEnum?.flag} ${langEnum?.label}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    MemberRulesAgreementDialog.show(
                      context,
                      isViewOnly: true,
                      existingAgreement: _memberAgreement,
                    );
                  },
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: Text('View Agreement', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
  Widget _buildNotesTab(Member member) {
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
          onPressed: _isSavingNotes ? null : () => _saveMemberNotes(member),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isSavingNotes
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text('Save Notes', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  void _showMemberAttendanceSheet(BuildContext context, Member member) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final repo = Provider.of<GymRepository>(context, listen: false);
            final allRecords = repo.getAttendance();
            final memberRecords = allRecords.where((r) {
              final matchId = r.userId.isNotEmpty && r.userId == member.id;
              final matchPhone = member.phone.isNotEmpty && r.userId == member.phone;
              final matchName = member.name.isNotEmpty && r.userName.trim().toLowerCase() == member.name.trim().toLowerCase();
              return matchId || matchPhone || matchName;
            }).toList();

            final totalVisits = memberRecords.length;
            final now = DateTime.now();
            final currentMonthPrefix = DateFormat('-MM-yyyy').format(now);
            final thisMonthVisits = memberRecords.where((r) => r.date.endsWith(currentMonthPrefix)).length;
            final todayStr = DateFormat('dd-MM-yyyy').format(now);
            final todayRecord = memberRecords.where((r) => r.date == todayStr).firstOrNull;

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.co_present_rounded, color: AppTheme.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Attendance History',
                                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${member.name} • ${member.phone.isNotEmpty ? member.phone : 'Member'}',
                                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textSecondary),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceGray,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Text('$totalVisits', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                const SizedBox(height: 2),
                                Text('Total Visits', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceGray,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Text('$thisMonthVisits', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: const Color(0xFF16A34A))),
                                const SizedBox(height: 2),
                                Text('This Month', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            decoration: BoxDecoration(
                              color: todayRecord != null ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: todayRecord != null ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  todayRecord != null ? 'Present' : 'Not In',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: todayRecord != null ? const Color(0xFF047857) : const Color(0xFFB45309),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text('Today', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (todayRecord == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final nowTime = DateFormat('hh:mm a').format(DateTime.now());
                          await repo.saveMemberAttendanceLog(
                            memberId: member.id,
                            memberName: member.name,
                            date: todayStr,
                            status: 'Present',
                            checkInTime: nowTime,
                            checkOutTime: null,
                          );
                          setModalState(() {});
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('✅ Attendance recorded for ${member.name}!'),
                                backgroundColor: AppTheme.success,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppTheme.primary),
                        label: Text('Mark Present Today', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppTheme.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          minimumSize: const Size.fromHeight(40),
                        ),
                      ),
                    ),
                  const Divider(height: 20),
                  Expanded(
                    child: memberRecords.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.calendar_month_outlined, size: 48, color: AppTheme.textSecondary.withOpacity(0.4)),
                                const SizedBox(height: 12),
                                Text('No attendance records yet', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                const SizedBox(height: 4),
                                Text('Member check-ins will show up here.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                            itemCount: memberRecords.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final rec = memberRecords[i];
                              final isPresent = rec.status.toLowerCase() == 'present';
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: isPresent ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isPresent ? Icons.check_circle_rounded : Icons.schedule_rounded,
                                    size: 18,
                                    color: isPresent ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  ),
                                ),
                                title: Text(
                                  rec.date,
                                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                                ),
                                subtitle: Text(
                                  'In: ${rec.checkInTime.isNotEmpty ? rec.checkInTime : '—'}${rec.checkOutTime != null && rec.checkOutTime!.isNotEmpty ? '  •  Out: ${rec.checkOutTime}' : ''}',
                                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isPresent ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isPresent ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
                                    ),
                                  ),
                                  child: Text(
                                    rec.status,
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isPresent ? const Color(0xFF047857) : const Color(0xFFB45309),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const OwnerAttendanceHistoryScreen(userTypeFilter: 'Member'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text('View Full Gym Attendance Logs', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // More Tab
  Widget _buildMoreTab(Member member) {
    final items = [
      {'title': 'Attendance', 'icon': Icons.co_present_rounded, 'action': 'attendance'},
      {'title': 'Body Measurements', 'icon': Icons.scale_rounded, 'action': 'measurements'},
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
              final isMeasurements = item['action'] == 'measurements';
              final isAttendance = item['action'] == 'attendance';

              return Column(
                children: [
                  ListTile(
                    onTap: isMeasurements
                        ? () => _showEditBodyMeasurementsSheet(context, member)
                        : (isAttendance ? () => _showMemberAttendanceSheet(context, member) : null),
                    leading: Icon(item['icon'] as IconData, color: AppTheme.primary),
                    title: Text(item['title'] as String, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(isAttendance ? 'View Logs' : 'Edit / View', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, size: 14, color: AppTheme.primary),
                        ],
                      ),
                    ),
                  ),
                  if (idx < items.length - 1) const Divider(height: 1),
                ],
              );
            }),
          ),
        ),
        if (_canDeleteMember(context)) ...[
          const SizedBox(height: 24),
          Text('Danger Zone', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.danger)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppTheme.danger, size: 20),
                    const SizedBox(width: 8),
                    Text('Delete Member', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.danger)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Permanently delete this member from the gym database. This will reclaim and free up 1 membership slot.',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF7F1D1D)),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: () => _confirmDeleteMember(context, member),
                  icon: const Icon(Icons.delete_forever_rounded, size: 18),
                  label: const Text('Delete Member'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.danger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'photo') {
                _showPhotoPickerBottomSheet(context, member);
              } else if (val == 'edit') {
                _showEditMemberDetailsSheet(context, member);
              } else if (val == 'delete') {
                _confirmDeleteMember(context, member);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'photo',
                child: Row(
                  children: [
                    Icon(Icons.camera_alt_outlined, color: AppTheme.primary, size: 20),
                    SizedBox(width: 10),
                    Text('Change Photo', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, color: AppTheme.textPrimary, size: 20),
                    SizedBox(width: 10),
                    Text('Edit Member Details', style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              if (_canDeleteMember(context)) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                      SizedBox(width: 10),
                      Text('Delete Member', style: TextStyle(color: AppTheme.danger, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ],
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
                            ? _buildNotesTab(member)
                            : _buildMoreTab(member),
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

  bool _canDeleteMember(BuildContext context) {
    try {
      final authVm = Provider.of<AuthViewModel>(context, listen: false);
      final isOwner = authVm.selectedRole?.toLowerCase() == 'owner' ||
          authVm.activeAssociation?.role == UserRole.owner;
      if (isOwner) return true;

      // Staff permissions
      final staffPerms = authVm.staffRecord?.permissions;
      if (staffPerms != null && staffPerms['delete_member'] == true) {
        return true;
      }
      final isReceptionist = authVm.selectedRole?.toLowerCase().contains('reception') == true ||
          authVm.staffRecord?.role.toLowerCase().contains('reception') == true;
      if (isReceptionist) return true;
    } catch (_) {
      return true;
    }
    return false;
  }

  Future<void> _confirmDeleteMember(BuildContext context, Member member) async {
    String selectedScope = 'profile_only';

    final confirmedScope = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.delete_sweep_rounded, color: AppTheme.danger, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Delete Member',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose how you want to delete "${member.name}":',
                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),

              // Option 1: Profile Only (Recommended)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setDialogState(() => selectedScope = 'profile_only'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selectedScope == 'profile_only'
                        ? AppTheme.primary.withValues(alpha: 0.08)
                        : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selectedScope == 'profile_only'
                          ? AppTheme.primary
                          : AppTheme.border,
                      width: selectedScope == 'profile_only' ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Radio<String>(
                        value: 'profile_only',
                        groupValue: selectedScope,
                        activeColor: AppTheme.primary,
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedScope = val);
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delete Profile Only (Recommended)',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: selectedScope == 'profile_only' ? AppTheme.primary : AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Removes member profile and frees up 1 slot. Retains all past payments and revenue records in gym finances.',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Option 2: Delete Everything (Cascade)
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setDialogState(() => selectedScope = 'all'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: selectedScope == 'all'
                        ? AppTheme.danger.withValues(alpha: 0.08)
                        : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selectedScope == 'all'
                          ? AppTheme.danger
                          : AppTheme.border,
                      width: selectedScope == 'all' ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Radio<String>(
                        value: 'all',
                        groupValue: selectedScope,
                        activeColor: AppTheme.danger,
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedScope = val);
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delete Member & All Linked Records',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: selectedScope == 'all' ? AppTheme.danger : AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Removes member, linked payment records from active revenue/dues calculations, and attendance logs.',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Safe Archive Notice
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: Colors.blue, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Data is safely archived in the database and can be restored anytime by an Admin.',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF1E40AF), fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, null),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(dialogCtx, selectedScope),
              child: Text('Delete Member', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmedScope != null && mounted) {
      final membersVm = Provider.of<MembersViewModel>(context, listen: false);
      try {
        await membersVm.deleteMember(member.id, deleteScope: confirmedScope);
        
        try {
          final recVm = Provider.of<ReceptionistViewModel>(context, listen: false);
          recVm.logActivity('Member Deleted', 'members', targetMember: member.name);
          recVm.fetchDashboardStats();
        } catch (_) {}

        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Member "${member.name}" deleted successfully. 1 membership slot freed.'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete member: $e'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }

  bool _isLoading = false;
}
