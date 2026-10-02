# Phase 15: Staff Tab Scroll Performance & Lag Elimination

## Goal
Eliminate UI lag, stutter, and frame drops ("atak atka ke chal raha hai") in the Owner Staff tab when displaying and scrolling 15+ staff members. Achieve 60/120 FPS buttery-smooth scrolling by eliminating per-pixel parent `setState()` calls, removing O(N² log N) sorting from `itemBuilder`, pre-computing RPC lookup maps, and isolating repaint boundaries.

## Root Cause Diagnostics
1. **Per-pixel ScrollController `setState()` Thrashing**: `_scrollController.addListener(_onScroll)` triggers `setState()` on every micro-pixel scroll, forcing the entire `StaffScreen` and all 15 cards to rebuild 60–120 times per second.
2. **GPU `saveLayer` Bottleneck via Dynamic `Opacity`**: `Opacity(opacity: cardsOpacity, ...)` wraps the header cards, forcing expensive off-screen compositing passes on every scroll frame.
3. **Catastrophic O(N² log N) Computation inside `itemBuilder`**: For every single item being built, `List<Staff>.from(allStaff)` is copied and sorted, executing linear lookups over `_staffCardsRpc` and `staffVm.getDraftsForMonth` inside the comparator. With 15 items * 120 FPS, this executes over 1,800 sorts and tens of thousands of linear searches per second on the UI thread.
4. **Build-Time Aggregate Computations**: `totalSalaryDue` recalculates through nested loops over all staff and RPC results on every single frame.
5. **Missing Repaint Boundaries**: Lack of `RepaintBoundary` on list items forces Flutter to re-rasterize entire card layouts on every scroll delta.

## Plan Breakdown

### Wave 1: Eliminate Parent Scroll Listener & Dynamic Opacity GPU Bottleneck
- [ ] Remove `_scrollController.addListener(_onScroll)` that invokes `setState()` in `_StaffScreenState`.
- [ ] Remove the dynamic GPU `Opacity` wrapper over stats cards that caused GPU offscreen layer thrashing.
- [ ] Implement natural, high-performance sliver scrolling via `SliverToBoxAdapter` / `SliverPersistentHeader` so scrolling executes entirely on the render tree without triggering Flutter widget tree rebuilds.

### Wave 2: Pre-compute Staff View Models & O(1) Indexed Lookups
- [ ] Convert `_staffCardsRpc` into a hash map (`Map<String, Map<String, dynamic>> _staffRpcMap`) keyed by `staff_id` for O(1) instant access.
- [ ] Move staff sorting (pending salary staff at top, then by name) and data transformation out of `itemBuilder` into a dedicated `_recomputeDisplayList()` method that only runs when data or filter query actually changes.
- [ ] Pre-calculate summary statistics (`totalStaff`, `presentToday`, `totalSalaryDue`, `onLeave`) during data load / search updates rather than recomputing them inside `StaffScreen.build()`.
- [ ] Update `SliverChildBuilderDelegate`: make `(context, index)` perform pure O(1) indexed access to `_preparedStaffList[index]`.

### Wave 3: Card Widget Repaint Boundary & Layout Optimization
- [ ] Wrap `OwnerStaffCard` in `RepaintBoundary` to prevent re-rasterization during list scrolling.
- [ ] Configure `SliverChildBuilderDelegate` with `addRepaintBoundaries: true` and `addAutomaticKeepAlives: true`.
- [ ] Review `OwnerStaffCard` and `AppCachedAvatar` to ensure styles, decorations, and fallback avatars use `const` where possible and avoid unnecessary `MediaQuery` overhead.

### Wave 4: Validation & Quality Gate
- [ ] Run `flutter analyze` to ensure zero compilation errors, warnings, or lint issues.
- [ ] Verify scrolling behavior with 15+ staff members: ensure zero stutter ("atak atak ke chalna") during rapid flick, scroll down, and scroll up.
- [ ] Verify that salary pending/paid badges, stats cards, and search filters remain 100% accurate and functional.
