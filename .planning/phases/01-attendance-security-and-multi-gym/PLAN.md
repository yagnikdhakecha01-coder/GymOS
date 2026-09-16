# Phase Plan: Attendance Security, Multi-Gym Isolation & IST Auto-Absent

**Phase:** 01
**Title:** Attendance Module Security, Multi-Gym Isolation & IST Auto-Absent
**Created:** 2026-09-16
**Status:** Planned

## Executive Summary
Fix the critical member attendance bypass where tapping/double-clicking marked attendance without scanning a QR code, eliminate developer bypasses, enforce strict multi-tenant gym isolation on QR validation, and verify Indian Standard Time (IST) auto-absent logic.

## Tasks
1. **Remove Simulate Check-In Bypass in Member App:**
   - Remove `Simulate Check-in` button in `lib/features/member_app/screens/member_scan_qr_screen.dart`.
   - Update `MemberAppViewModel.markCheckIn(String qrToken)` to strictly require a valid, non-empty scanned token and eliminate default fallback.
2. **Multi-Gym QR Token & Branch Verification:**
   - Ensure `process_qr_attendance` verifies that the member belongs to the scanned QR code's `gym_id`.
   - Prevent cross-gym attendance leaks.
3. **Indian Standard Time (IST) Auto-Absent Engine:**
   - Verify and deploy updated `cron_auto_mark_absent` and `process_qr_attendance` functions using `Asia/Kolkata` timezone.
   - Staff: Auto-mark absent 1 hour post-shift end.
   - Member: Auto-mark absent 2 hours post-closing (IST).
4. **Verification & Testing:**
   - Run `flutter analyze` to ensure clean build.
   - Perform full multi-gym testing and verify logs.
