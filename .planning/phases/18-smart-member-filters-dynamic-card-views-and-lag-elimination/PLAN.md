# Phase 18: Smart Member Filters, Dynamic Card Views, and High-Performance Lag Elimination

## Goal
Implement a fully functional filter system on the Members screen with 4 dynamic view modes (Pending Fees First, Expiring Soon / Expired, Recently Joined, and Alphabetical), dynamically adapting member card badges to match each view mode. Eliminate all scroll and navigation lag for 200+ member gyms by removing per-pixel `setState()` thrashing, GPU offscreen opacity layers, and un-memoized sorting on every frame.

---

## Root Cause Diagnostics

1. **Empty Filter Button Handler**:
   - In `members_screen.dart` (lines 231-234), `IconButton(icon: Icon(Icons.filter_list_rounded), onPressed: () {})` has an empty callback. Tapping it does nothing.
2. **Per-Pixel `ScrollController` Rebuild Thrashing**:
   - `_scrollController.addListener(_onScroll)` calls `setState()` on every micro-pixel scroll delta.
   - On every scroll frame, `build()` is invoked, recalculating all aggregates and re-evaluating 200+ member cards.
3. **GPU `saveLayer` Bottleneck via Dynamic `Opacity`**:
   - `Opacity(opacity: cardsOpacity, ...)` wraps the stats cards header, forcing GPU offscreen rasterization passes 60–120 times per second during scroll.
4. **Catastrophic Un-memoized Filtering & Sorting in `MembersViewModel`**:
   - `filteredMembers` is a getter that runs `.where(...)` and `.sort(...)` over all 200+ members every time it is read (multiple times per scroll frame).
5. **Per-Item String Date Parsing in `itemBuilder`**:
   - Every member card parses date strings (`DateTime.parse(exp)`) and formats them on every build frame.
6. **Card Tap Navigation Jank**:
   - Tapping a member card immediately invokes `_loadInvitation()`, `_loadPtAssignment()`, and `_loadAgreement()` in `MemberProfileScreen.initState()`, triggering state updates and Supabase calls while the push animation is still interpolating frames.

---

## Plan Breakdown

### Wave 1: High-Performance Scroll Decoupling & Navigation Smoothing
- [x] Remove `_scrollController.addListener(_onScroll)` that called `setState()` on every scroll delta in `_MembersScreenState`.
- [x] Remove the dynamic GPU `Opacity(opacity: cardsOpacity, ...)` wrapper; allow the sliver header to scroll naturally without GPU layer thrashing.
- [x] Add `addRepaintBoundaries: true` and `addAutomaticKeepAlives: true` on `SliverChildBuilderDelegate`.
- [x] Wrap member list card in `RepaintBoundary` to isolate rasterization deltas.
- [x] In `MemberProfileScreen`, defer heavy background fetches (`_loadInvitation`, `_loadPtAssignment`, `_loadAgreement`) to `WidgetsBinding.instance.addPostFrameCallback` so route transitions open instantly at 60/120 FPS.

### Wave 2: Memoized Filtering, Sorting Engine & Member Date Helpers
- [x] Add `MemberSortOption` enum in `MembersViewModel`:
  - `pendingFeesFirst` (Default: highest dues on top)
  - `expiringSoon` (Expired first, then expiring in 0-7 days, then 8-30 days, then later)
  - `recentlyJoined` (Newest `joinDate` / `createdAt` first)
  - `alphabetical` (Name A to Z)
- [x] Add helper getters on `Member` model for fast, pre-parsed date access:
  - `DateTime? get parsedExpiryDate`
  - `DateTime? get parsedJoinDate`
  - `bool get isExpired`
  - `int? get daysUntilExpiry`
- [x] Implement memoization in `MembersViewModel`:
  - Keep `_cachedFilteredMembers` and `_activeSortOption`.
  - Only recompute filtered & sorted list when `_repository.getMembers()`, `_searchQuery`, `_selectedFilter`, or `_sortOption` changes.
  - Make `filteredMembers` an O(1) getter returning the cached list.

### Wave 3: Filter UI & Dynamic Member Card Views
- [x] Build `MemberFilterBottomSheet`:
  - Premium modal bottom sheet displaying the 4 view modes with descriptive subtitles and intuitive icons.
  - Active checkmark on the currently selected filter.
- [x] Wire the circled filter button in `members_screen.dart` to open `MemberFilterBottomSheet`:
  - Show a small primary active dot/indicator on the filter icon when a non-default sort is active.
- [x] Update Member Card to dynamically adapt to the active sort view ("fillter ke acording card bhi change ho"):
  - **Pending Fees View (Default)**:
    - Primary badge: `₹X,XXX Fees Pending` (Red) or `Fees Paid` (Green).
    - Subtitle: `Next Due: DD MMM YYYY` or `Fully Paid`.
  - **Expiring Soon View**:
    - Primary badge:
      - If expired: `Expired (X d ago)` (Crimson Red badge with warning icon).
      - If expiring <= 7 days: `Expires in X days` (Amber Warning badge with clock icon).
      - If active: `Expires in X d` (Soft Slate/Green badge).
    - Subtitle: Exact expiry date.
  - **Recently Joined View**:
    - Primary badge: `New Member` or `Joined X days ago` (Indigo badge with calendar icon).
    - Subtitle: `Joined: DD MMM YYYY`.
  - **Alphabetical View**:
    - Primary badge: Payment status badge.
    - Subtitle: Phone & payment status.

### Wave 4: Validation & Quality Gate
- [x] Run `flutter analyze lib` to ensure 0 errors and 0 warnings on modified files.
- [x] Verified instant, lag-free scrolling across 200+ members.
- [x] Verified tapping any member card opens `MemberProfileScreen` with silky smooth transition.
- [x] Verified each of the 4 filter views sorts the list accurately and changes the card badges accordingly.
