import 'package:intl/intl.dart';

class AttendanceRecord {
  final String id;
  final String userId;
  final String userName;
  final String userType; // Member, Staff
  final String checkInTime;
  final String? checkOutTime;
  final String date;
  final String status; // Present, Late, Absent, Half Day, Early Exit, Overtime, Leave, Half Leave, Incomplete Attendance
  final String? method;
  final double? workingHours;
  final String? displayId;
  final int workingMinutes;
  final int lateMinutes;
  final int earlyExitMinutes;
  final int overtimeMinutes;
  final String? shiftStatus;
  final String? qrType;
  final String? qrTokenId;
  final int ruleVersion;
  final String? staffId; // Added to map staff attendance correctly

  AttendanceRecord({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userType,
    required this.checkInTime,
    this.checkOutTime,
    required this.date,
    required this.status,
    this.method,
    this.workingHours,
    this.displayId,
    required this.workingMinutes,
    required this.lateMinutes,
    required this.earlyExitMinutes,
    required this.overtimeMinutes,
    this.shiftStatus,
    this.qrType,
    this.qrTokenId,
    required this.ruleVersion,
    this.staffId,
  });

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    String checkIn = json['checkInTime'] as String? ?? '';
    if (json['check_in'] != null) {
      final parsed = DateTime.parse(json['check_in'] as String).toLocal();
      checkIn = DateFormat('hh:mm a').format(parsed);
    }
    String? checkOut = json['checkOutTime'] as String?;
    if (json['check_out'] != null) {
      final parsed = DateTime.parse(json['check_out'] as String).toLocal();
      checkOut = DateFormat('hh:mm a').format(parsed);
    }
    String dateStr = json['date'] as String? ?? '';
    if (json['check_in'] != null) {
      final parsed = DateTime.parse(json['check_in'] as String).toLocal();
      dateStr = DateFormat('dd-MM-yyyy').format(parsed);
    }

    String uName = 'User';
    if (json['userName'] != null) {
      uName = json['userName'] as String;
    } else if (json['profiles'] != null) {
      final prof = json['profiles'];
      if (prof is Map) {
        uName = (prof['full_name'] ?? prof['name'] ?? 'User').toString();
      }
    }

    return AttendanceRecord(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? json['userId'] as String? ?? '',
      userName: uName,
      userType: json['user_type'] as String? ?? json['userType'] as String? ?? 'Member',
      checkInTime: checkIn,
      checkOutTime: checkOut,
      date: dateStr,
      status: json['status'] as String? ?? 'Present',
      method: json['method'] as String?,
      workingHours: (json['working_hours'] as num?)?.toDouble() ?? (json['workingHours'] as num?)?.toDouble(),
      displayId: json['display_id'] as String?,
      workingMinutes: json['working_minutes'] as int? ?? 0,
      lateMinutes: json['late_minutes'] as int? ?? 0,
      earlyExitMinutes: json['early_exit_minutes'] as int? ?? 0,
      overtimeMinutes: json['overtime_minutes'] as int? ?? 0,
      shiftStatus: json['shift_status'] as String?,
      qrType: json['qr_type'] as String?,
      qrTokenId: json['qr_token_id'] as String?,
      ruleVersion: json['rule_version'] as int? ?? 1,
      staffId: json['staff_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'userType': userType,
      'checkInTime': checkInTime,
      'checkOutTime': checkOutTime,
      'date': date,
      'status': status,
      'method': method,
      'workingHours': workingHours,
      'displayId': displayId,
      'workingMinutes': workingMinutes,
      'lateMinutes': lateMinutes,
      'earlyExitMinutes': earlyExitMinutes,
      'overtimeMinutes': overtimeMinutes,
      'shiftStatus': shiftStatus,
      'qrType': qrType,
      'qrTokenId': qrTokenId,
      'ruleVersion': ruleVersion,
      'staffId': staffId,
    };
  }

  AttendanceRecord copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userType,
    String? checkInTime,
    String? checkOutTime,
    String? date,
    String? status,
    String? method,
    double? workingHours,
    String? displayId,
    int? workingMinutes,
    int? lateMinutes,
    int? earlyExitMinutes,
    int? overtimeMinutes,
    String? shiftStatus,
    String? qrType,
    String? qrTokenId,
    int? ruleVersion,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userType: userType ?? this.userType,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      date: date ?? this.date,
      status: status ?? this.status,
      method: method ?? this.method,
      workingHours: workingHours ?? this.workingHours,
      displayId: displayId ?? this.displayId,
      workingMinutes: workingMinutes ?? this.workingMinutes,
      lateMinutes: lateMinutes ?? this.lateMinutes,
      earlyExitMinutes: earlyExitMinutes ?? this.earlyExitMinutes,
      overtimeMinutes: overtimeMinutes ?? this.overtimeMinutes,
      shiftStatus: shiftStatus ?? this.shiftStatus,
      qrType: qrType ?? this.qrType,
      qrTokenId: qrTokenId ?? this.qrTokenId,
      ruleVersion: ruleVersion ?? this.ruleVersion,
    );
  }
}
