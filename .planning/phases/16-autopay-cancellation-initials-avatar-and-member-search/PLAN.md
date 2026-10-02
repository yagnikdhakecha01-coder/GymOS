# Phase 16: AutoPay Cancellation, Initials-Based Avatar Fallback, and Member Search

## Goal
Resolve three critical issues:
1. **AutoPay Cancellation Database Error**: Fix permission denied / missing column errors on `public.subscriptions` and `public.subscription_history` so owners can cancel AutoPay smoothly from the app.
2. **Initials Avatar Fallback (Member & Staff)**: Remove the hardcoded dummy unsplash man photo. When a member or staff has no uploaded photo (or has the default dummy photo), show a clean, modern initials-based avatar using the first letter of their name with a personalized pastel background.
3. **Interactive Member Search**: Implement search functionality on the Members screen to allow searching both active/inactive members and trial members by Name or Mobile Number with real-time filtering.

---

## Root Cause Diagnostics

### 1. AutoPay Cancellation Failure (`PostgrestException: permission denied for table subscriptions, code: 42501`)
* `cancel_autopay_subscription(p_gym_id UUID)` RPC attempted to insert into `subscription_history` with nonexistent columns (`owner_id`, `event`, `details`), while actual columns are `(gym_id, old_plan_id, new_plan_id, action, changed_by, notes)`.
* When the RPC failed, the Dart code caught the error and attempted a direct table update: `from('subscriptions').update(...)`. This failed with PostgreSQL error `42501` because `authenticated` role lacked `UPDATE` privilege on `public.subscriptions` and `INSERT` privilege on `public.subscription_history`.

### 2. Default Photo Reused Everywhere (`photo-1535713875002-d1d0cf377fde`)
* Throughout the codebase (`members_screen.dart`, `add_member_wizard_screen.dart`, `add_old_member_screen.dart`, `add_staff_screen.dart`, `staff.dart`), missing avatars fell back to a hardcoded Unsplash photo of a man in a black shirt.
* Existing database records were populated with this Unsplash URL, causing every member/staff without an uploaded photo to display the same image.

### 3. Inactive Search Button on Members Screen
* In `members_screen.dart`, the search icon button had an empty handler: `IconButton(icon: Icon(Icons.search_rounded), onPressed: () {})`.
* Although `MembersViewModel` and `TrialMembersViewModel` have search logic ready, there was no search bar UI state or input textfield connected.

---

## Plan Breakdown

### Wave 1: Supabase Database Privileges & `cancel_autopay_subscription` RPC Hardening
- [ ] Deploy updated `cancel_autopay_subscription(p_gym_id UUID)` RPC:
  - Correctly update `auto_pay = false`, `cancel_at_period_end = true`, `auto_pay_cancelled_at = now()`, `updated_at = now()`.
  - Insert audit log into `subscription_history` matching exact schema: `(gym_id, old_plan_id, new_plan_id, action, changed_by, notes, created_at)`.
  - Mark function as `SECURITY DEFINER` and grant `EXECUTE` to `authenticated` and `service_role`.
- [ ] Grant table permissions:
  - `GRANT UPDATE ON public.subscriptions TO authenticated;`
  - `GRANT INSERT ON public.subscription_history TO authenticated;`
- [ ] Fix Dart fallback logic in `owner_subscription_screen.dart`:
  - Align `subscription_history` insert columns with schema and handle RPC response correctly.

### Wave 2: Initials Avatar System & Removal of Hardcoded Dummy Photos
- [ ] Enhance `AppCachedAvatar`:
  - Detect dummy URLs (`photo-1535713875002-d1d0cf377fde` or generic placeholders) and treat them as empty.
  - Generate a distinct, harmonious background color and text color based on the person's name hash.
  - Display the uppercase first letter of their name prominently with bold typography.
- [ ] Update `members_screen.dart` and `trial_members_screen.dart`:
  - Replace raw `Image.network(...)` with `AppCachedAvatar`.
- [ ] Update `member_profile_screen.dart` and `staff_profile_screen.dart`:
  - Ensure fallback displays the initials avatar when photo is empty or matches dummy URL.
- [ ] Update member and staff creation wizards (`add_member_wizard_screen.dart`, `add_old_member_screen.dart`, `add_trial_member_screen.dart`, `add_staff_screen.dart`, `staff.dart` model):
  - Save empty string `''` when no image is picked, rather than writing the Unsplash dummy URL to the database.

### Wave 3: Interactive Search on Members Screen (Name & Mobile Number)
- [ ] Implement search mode state (`_isSearching`, `TextEditingController _searchController`) in `members_screen.dart`.
- [ ] Render animated/toggleable search bar in the header:
  - Back/close button to cancel search and reset filters.
  - Modern search input with placeholder: `"Search by name or mobile number..."`.
  - Clear ('X') button when query is non-empty.
- [ ] Connect input changes to:
  - `membersVm.setSearchQuery(text)` (filters active/inactive members by name or mobile).
  - `trialsVm.setSearchQuery(text)` (filters trial members by name or mobile).
- [ ] Update trial tab list in `members_screen.dart` to use `trialsVm.filteredTrials` instead of raw `allTrials`.

### Wave 4: Validation & Quality Gate
- [ ] Execute SQL migration via Supabase tool and verify table grants and RPC execution.
- [ ] Run `flutter analyze lib` to verify 0 errors, warnings, or regressions.
- [ ] Test AutoPay cancellation flow and verify success toast and database record update.
- [ ] Verify members and staff with no photos display initials avatars.
- [ ] Verify searching by name and phone number accurately filters the member list.
