# Phase 33: Member & Staff Detail Update Persistence Across iOS, Android & Database

**Phase:** 33  
**Milestone:** GymOS v1.3  
**Status:** 🟢 Completed  
**Mode:** tracer-first  

---

## 1. Problem Statement & Root Cause Analysis

### The Problem:
Jab gym owner ya authorized staff iOS ya Android app se member ya staff ki details (jaise Name, Phone, Email, DOB, Gender, Address, Shift, Salary, Biometric PIN, Goals, Notes) update karte hain, to app me update success dialog dikh jata hai lekin **database (Supabase) me actual record update nahi hota**, aur app reload/sync hone par purani details wapas revert ho jati hain.

### Root Causes Discovered:
1. **Silent Swallowing & Return-Minimal Update (`gym_repository.dart`):**
   - `saveMember()` aur `saveStaff()` me `SupabaseService.client.from(...).update(updatePayload).eq('id', id)` bina `.select()` ke run hota hai. PostgREST me bina `.select()` ke agar RLS ya filter mismatch se **0 rows update** hoti hain, to bhi PostgREST `204 No Content` bhejta hai aur Flutter client koi exception throw nahi karta. Isse app samajhti hai ki update ho gaya, halanki database me 0 rows update hui hoti hain.
   - Agar koi exception aati bhi hai (jaise network, permission, column constraint), to `catch (e)` use console print karke `_crudQueue` me daal deta hai aur silently swallow kar leta hai. UI ko kabhi pata nahi chalta ki save fail hua hai.
   - `_processCrudQueue()` ko `saveMember`/`saveStaff` ke baad trigger nahi kiya jata; wo sirf periodic background sync par chalta hai.

2. **Race Condition & Immediate Cache Overwrite (`members_viewmodel.dart`):**
   - `members_viewmodel.dart` me `saveMember(member)` method:
     ```dart
     await _repository.saveMember(member);
     await fetchMembers(); // <-- ROOT CAUSE REVERT
     ```
   - Jaise hi `saveMember` swallow hota hai ya 0 rows update hoti hain, agle hi millisecond me `fetchMembers()` server se purana un-updated data fetch karta hai.
   - `_mergeMembersList()` us un-updated server data ko local cache me overwrite kar deta hai, jisse screen par member ki updated details gayab ho jati hain aur purani value wapas dikhne lagti hai.

3. **Missing Columns in Data Payloads:**
   - `saveMember()` ke `data` map me `biometric_pin` column miss tha, jabki Supabase `public.members` table me `biometric_pin integer` column maujood hai aur `MemberProfileScreen` me user PIN daalta hai.
   - `saveStaff()` ke `data` map me bhi `biometric_pin` column miss tha, aur `Staff` model me `biometricPin` field hi nahi thi.
   - `staff_profile_screen.dart` ke `_showEditStaffDialog` me important fields (Aadhaar, Emergency Contact, Notes, Qualification) missing thi.

4. **Trigger Inconsistency on `public.members`:**
   - `trg_check_members_permission` trigger on `members` checks `check_staff_action_permissions()`.
   - Function me `IF TG_TABLE_NAME = 'members' THEN v_action_needed := 'add_member';` check hota hai. Jab staff/receptionist existing member update karte hain, tab bhi 'add_member' permission check hoti hai, jisse `403 Forbidden` raise ho sakta hai agar 'add_member' disable ho.

---

## 2. Architecture & Fix Strategy

### Step 1: Fix Repository Direct Update with `.select()` & Verification
In [lib/core/repository/gym_repository.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/core/repository/gym_repository.dart):
- In `saveMember()`:
  - Add `'biometric_pin': member.biometricPin` to `data` map.
  - Execute update with `.select()`:
    ```dart
    final List res = await SupabaseService.client
        .from('members')
        .update(updatePayload)
        .eq('id', member.id)
        .eq('gym_id', gymId)
        .select('id');
    if (res.isEmpty) {
      throw Exception('Update failed: Member row was not found or permission denied by RLS.');
    }
    ```
  - Agar network fail ho ya queue me jaye, to queue item insert hone ke turant baad background process trigger karein: `unawaited(_processCrudQueue());`.
  - Exception ko silently swallow karne ke bajaye error throw karein agar offline queue fallback bhi ready na ho.

- In `saveStaff()`:
  - Add `'biometric_pin': staff.biometricPin` to `data` map.
  - Execute update with `.select()`:
    ```dart
    final List res = await SupabaseService.client
        .from('staff')
        .update(updatePayload)
        .eq('id', staff.id)
        .eq('gym_id', gymId)
        .select('id');
    if (res.isEmpty) {
      throw Exception('Update failed: Staff row was not found or permission denied by RLS.');
    }
    ```

### Step 2: Prevent Destructive Cache Revert in ViewModels
- In [lib/features/members/members_viewmodel.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/features/members/members_viewmodel.dart):
  - In `saveMember(Member member)`:
    - Do NOT immediately overwrite local state with a stale fetch if the server is still processing.
    - Update the local `_cachedFilteredMembers` and `_members` list directly with the updated object first.
    - If `fetchMembers()` is called, ensure `_mergeMembersList` prioritizes the latest local timestamp/update.
- In [lib/features/staff/staff_viewmodel.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/features/staff/staff_viewmodel.dart):
  - Ensure `updateStaff(Staff staff)` updates the cached staff list and calls `fetchStaffFromSupabase()` safely without overwriting updated fields.

### Step 3: Model & UI Synchronization
- In [lib/core/models/staff.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/core/models/staff.dart):
  - Add `final int? biometricPin;` to `Staff` model.
  - Update `fromJson()`, `toJson()`, and `copyWith()`.
- In [lib/features/staff/staff_profile_screen.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/features/staff/staff_profile_screen.dart):
  - Add missing fields in `_showEditStaffDialog` (Emergency Name, Emergency Phone, Aadhaar, Qualification, Notes, Biometric PIN).
  - Ensure updated values correctly populate `updatedStaff`.
- In [lib/features/members/member_profile_screen.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/features/members/member_profile_screen.dart):
  - Ensure `biometricPinController` value is saved and persisted cleanly to database.

### Step 4: Database Permissions & Triggers Hardening
- Audit `check_staff_action_permissions()`:
  - If `TG_OP = 'UPDATE'` on `members`, check for `'edit_member'` or allow owner/admin and staff with valid permissions.
- Ensure `gyms.owner_id` is synced for all gyms so RLS `fn_user_accessible_gym_ids()` always resolves correctly for gym owners.

---

## 3. Tasks Breakdown

- [ ] **Task 33.1 (Tracer Slice):** Update `saveMember()` and `saveStaff()` in `gym_repository.dart` with `.select()`, include `biometric_pin`, and verify 1 row is affected.
- [ ] **Task 33.2 (Model Expansion):** Update `Staff` model with `biometricPin` field and serialization.
- [ ] **Task 33.3 (UI Form Audit):** Update `staff_profile_screen.dart` and `member_profile_screen.dart` to bind and save all profile fields including biometric PIN and emergency details.
- [ ] **Task 33.4 (Cache Desync Elimination):** Fix `members_viewmodel.dart` and `staff_viewmodel.dart` to prevent stale `fetchMembers` from rolling back the update.
- [ ] **Task 33.5 (Verification):** Test update member and staff detail persistence via Supabase SQL and live client checks.
