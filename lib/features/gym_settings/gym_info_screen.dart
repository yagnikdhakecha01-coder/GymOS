import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/custom_button.dart';
import '../../core/widgets/custom_card.dart';
import 'gym_settings_viewmodel.dart';

class GymInfoScreen extends StatefulWidget {
  const GymInfoScreen({super.key});

  @override
  State<GymInfoScreen> createState() => _GymInfoScreenState();
}

class _SettingsTimingPicker extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SettingsTimingPicker({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(value, style: GoogleFonts.inter(fontSize: 13.5, color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
            const Icon(Icons.access_time_rounded, size: 16, color: AppTheme.primary),
          ],
        ),
      ),
    );
  }
}

class _GymInfoScreenState extends State<GymInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  
  String _openTime = '06:00 AM';
  String _closeTime = '10:00 PM';
  String _weeklyOff = 'Sunday';
  String _logo = '';

  String _shiftMode = 'Single Shift';
  String _singleStart = '05:00 AM';
  String _singleEnd = '10:00 PM';
  String _morningStart = '05:00 AM';
  String _morningEnd = '11:00 AM';
  String _eveningStart = '04:00 PM';
  String _eveningEnd = '10:00 PM';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = Provider.of<GymSettingsViewModel>(context, listen: false);
      final info = vm.gymInfo;
      _nameController.text = info['name'] ?? '';
      _addressController.text = info['address'] ?? '';
      _phoneController.text = info['phone'] ?? '';
      _emailController.text = info['email'] ?? '';
      
      final timing = info['timing'] as String? ?? '06:00 AM - 10:00 PM';
      if (timing.contains(' - ')) {
        final split = timing.split(' - ');
        _openTime = split[0];
        _closeTime = split[1];
      }
      _weeklyOff = info['weeklyOff'] ?? 'Sunday';
      _logo = info['logo'] ?? '';
      
      final activeGymId = info['id'];
      if (activeGymId != null) {
        vm.loadOperatingHours(activeGymId).then((_) {
          _shiftMode = vm.shiftMode;
          for (var shift in vm.shifts) {
            final type = shift['shift_type'];
            final start = shift['start_time'];
            final end = shift['end_time'];
            if (type == 'Single Shift') {
              _singleStart = start;
              _singleEnd = end;
            } else if (type == 'Morning Shift') {
              _morningStart = start;
              _morningEnd = end;
            } else if (type == 'Evening Shift') {
              _eveningStart = start;
              _eveningEnd = end;
            }
          }
          if (mounted) setState(() {});
        });
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _selectTime(BuildContext context, bool isOpenTime) async {
    final initial = isOpenTime 
        ? const TimeOfDay(hour: 6, minute: 0) 
        : const TimeOfDay(hour: 22, minute: 0);
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
      final min = picked.minute.toString().padLeft(2, '0');
      final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
      final formatted = '${hour.toString().padLeft(2, '0')}:$min $period';
      setState(() {
        if (isOpenTime) {
          _openTime = formatted;
        } else {
          _closeTime = formatted;
        }
      });
    }
  }

  String _to24h(String timeStr) {
    try {
      final format = DateFormat('hh:mm a');
      final date = format.parse(timeStr);
      return DateFormat('HH:mm:ss').format(date);
    } catch (_) {
      return '00:00:00';
    }
  }

  Future<void> _selectShiftTime(BuildContext context, String initialTime, Function(String) onSelected) async {
    try {
      final parsed = DateFormat('hh:mm a').parse(initialTime);
      final initial = TimeOfDay(hour: parsed.hour, minute: parsed.minute);
      final picked = await showTimePicker(context: context, initialTime: initial);
      if (picked != null) {
        final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
        final min = picked.minute.toString().padLeft(2, '0');
        final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
        onSelected('${hour.toString().padLeft(2, '0')}:$min $period');
      }
    } catch (_) {}
  }

  bool _validateTwoShifts() {
    if (_shiftMode == 'Two Shifts') {
      try {
        final morningEndDt = DateFormat('hh:mm a').parse(_morningEnd);
        final eveningStartDt = DateFormat('hh:mm a').parse(_eveningStart);
        final morningEndRef = DateTime(2020, 1, 1, morningEndDt.hour, morningEndDt.minute);
        final eveningStartRef = DateTime(2020, 1, 1, eveningStartDt.hour, eveningStartDt.minute);
        if (morningEndRef.isAfter(eveningStartRef) || morningEndRef.isAtSameMomentAs(eveningStartRef)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Morning Shift End must be before Evening Shift Start!'), backgroundColor: Colors.red),
          );
          return false;
        }
      } catch (_) {}
    }
    return true;
  }

  void _save(GymSettingsViewModel vm) async {
    if (_formKey.currentState?.validate() ?? false) {
      if (!_validateTwoShifts()) return;

      final activeGymId = vm.gymInfo['id'];
      if (activeGymId != null) {
        List<Map<String, dynamic>> shiftsList = [];
        if (_shiftMode == 'Single Shift') {
          shiftsList.add({
            'type': 'Single Shift',
            'start_t': _singleStart,
            'end_t': _singleEnd,
            'start_24': _to24h(_singleStart),
            'end_24': _to24h(_singleEnd),
          });
        } else {
          shiftsList.add({
            'type': 'Morning Shift',
            'start_t': _morningStart,
            'end_t': _morningEnd,
            'start_24': _to24h(_morningStart),
            'end_24': _to24h(_morningEnd),
          });
          shiftsList.add({
            'type': 'Evening Shift',
            'start_t': _eveningStart,
            'end_t': _eveningEnd,
            'start_24': _to24h(_eveningStart),
            'end_24': _to24h(_eveningEnd),
          });
        }

        final success = await vm.saveOperatingHours(activeGymId, _shiftMode, shiftsList);
        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Error saving shift settings!'), backgroundColor: Colors.red),
          );
          return;
        }
      }

      await vm.saveGymInfo(
        name: _nameController.text.trim(),
        logo: _logo,
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        timing: _shiftMode == 'Single Shift' ? '$_singleStart - $_singleEnd' : '$_morningStart - $_eveningEnd',
        weeklyOff: _weeklyOff,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gym details saved successfully!'), backgroundColor: AppTheme.success),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<GymSettingsViewModel>(context);
    
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Gym Information'),
        centerTitle: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppTheme.pagePadding, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Logo Upload Box
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: AppTheme.border),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: _logo.isEmpty
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.cloud_upload_outlined, color: AppTheme.primary, size: 24),
                                    const SizedBox(height: 6),
                                    Text('Upload Logo', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              : ClipOval(
                                  child: Image.network(
                                    _logo,
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('JPG, PNG (Recommended 512x512)', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Form Card
                CustomCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Gym Name
                      Text('Gym Name *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _nameController,
                        validator: (value) => value == null || value.trim().isEmpty ? 'Please enter gym name' : null,
                        decoration: const InputDecoration(hintText: 'e.g. GYMOS'),
                      ),
                      const SizedBox(height: 16),

                      // Address
                      Text('Address *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _addressController,
                        validator: (value) => value == null || value.trim().isEmpty ? 'Please enter gym address' : null,
                        maxLines: 2,
                        decoration: const InputDecoration(hintText: 'e.g. 123 Main Road, City, Gujarat'),
                      ),
                      const SizedBox(height: 16),

                      // Phone & Email
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Contact Number *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  validator: (value) => value == null || value.trim().isEmpty ? 'Please enter contact' : null,
                                  decoration: const InputDecoration(hintText: 'e.g. 9876543210'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Email Address', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                const SizedBox(height: 6),
                                TextFormField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: const InputDecoration(hintText: 'e.g. info@fitzone.com'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Timings Picker Row
                      Text('Gym Timing *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _SettingsTimingPicker(
                              label: 'Open Time',
                              value: _openTime,
                              onTap: () => _selectTime(context, true),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text('to', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SettingsTimingPicker(
                              label: 'Close Time',
                              value: _closeTime,
                              onTap: () => _selectTime(context, false),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Weekly Off Dropdown
                      Text('Weekly Off *', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _weeklyOff,
                        items: ['None', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'].map((day) {
                          return DropdownMenuItem(value: day, child: Text(day));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _weeklyOff = val);
                          }
                        },
                      ),
                      const SizedBox(height: 20),

                      // ═══════ OPERATING HOURS SECTION ═══════
                      const Divider(),
                      const SizedBox(height: 10),
                      Text('Operating Hours *', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                      const SizedBox(height: 12),

                      Text('Shift Configuration Mode', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _shiftMode,
                        items: ['Single Shift', 'Two Shifts'].map((mode) {
                          return DropdownMenuItem(value: mode, child: Text(mode));
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _shiftMode = val);
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      if (_shiftMode == 'Single Shift') ...[
                        Text('Shift Timing', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _SettingsTimingPicker(
                                label: 'Start Time',
                                value: _singleStart,
                                onTap: () => _selectShiftTime(context, _singleStart, (val) => setState(() => _singleStart = val)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text('to', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SettingsTimingPicker(
                                label: 'End Time',
                                value: _singleEnd,
                                onTap: () => _selectShiftTime(context, _singleEnd, (val) => setState(() => _singleEnd = val)),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        // Morning Shift Timings
                        Text('Morning Shift Timing', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _SettingsTimingPicker(
                                label: 'Start Time',
                                value: _morningStart,
                                onTap: () => _selectShiftTime(context, _morningStart, (val) => setState(() => _morningStart = val)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text('to', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SettingsTimingPicker(
                                label: 'End Time',
                                value: _morningEnd,
                                onTap: () => _selectShiftTime(context, _morningEnd, (val) => setState(() => _morningEnd = val)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Evening Shift Timings
                        Text('Evening Shift Timing', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _SettingsTimingPicker(
                                label: 'Start Time',
                                value: _eveningStart,
                                onTap: () => _selectShiftTime(context, _eveningStart, (val) => setState(() => _eveningStart = val)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text('to', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textMuted)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _SettingsTimingPicker(
                                label: 'End Time',
                                value: _eveningEnd,
                                onTap: () => _selectShiftTime(context, _eveningEnd, (val) => setState(() => _eveningEnd = val)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                CustomButton(
                  text: 'Save Gym Info',
                  onPressed: () => _save(vm),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
