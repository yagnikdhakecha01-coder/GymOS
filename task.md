# Phase 15: Staff Tab Scroll Performance & Lag Elimination

- [ ] 1. Eliminate Parent Scroll Listener & Dynamic Opacity GPU Bottleneck <!-- id: 0 -->
  - [ ] Remove `_scrollController.addListener(_onScroll)` that invokes `setState()` <!-- id: 1 -->
  - [ ] Remove dynamic `Opacity` widget triggering expensive `saveLayer` GPU passes <!-- id: 2 -->
  - [ ] Implement zero-rebuild sliver scrolling for stats header & search bar <!-- id: 3 -->
- [ ] 2. Pre-compute Staff View Models & O(1) Indexed Lookups <!-- id: 4 -->
  - [ ] Convert `_staffCardsRpc` into O(1) `Map<String, Map<String, dynamic>>` hash lookup <!-- id: 5 -->
  - [ ] Move sorting and draft matching out of `itemBuilder` into memoized data model <!-- id: 6 -->
  - [ ] Pre-calculate summary stats (`totalSalaryDue`, `presentToday`, `onLeave`) on data update only <!-- id: 7 -->
  - [ ] Update `SliverChildBuilderDelegate` to pure O(1) indexed access <!-- id: 8 -->
- [ ] 3. Card Widget Repaint Boundary & Layout Optimization <!-- id: 9 -->
  - [ ] Wrap `OwnerStaffCard` in `RepaintBoundary` with `addRepaintBoundaries: true` <!-- id: 10 -->
  - [ ] Optimize `OwnerStaffCard` & `AppCachedAvatar` to eliminate layout thrashing <!-- id: 11 -->
- [ ] 4. Validation & Quality Gate <!-- id: 12 -->
  - [ ] Run `flutter analyze` to ensure 0 errors <!-- id: 13 -->
  - [ ] Verify 60/120 FPS buttery-smooth scroll up and down with 15+ staff <!-- id: 14 -->
