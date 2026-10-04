# Phase 21: Supabase Egress & Log Ingestion Optimization

## Goal
Eliminate unnecessary network traffic, background polling loops, and redundant database queries that caused 0.46 GB Egress and 0.81 GB Log Ingestion (81% of limit) in 2 days for just 1 active gym.

---

## Root Cause Analysis (Verified with Live ClickHouse Telemetry)

From live Supabase ClickHouse query logs (`query_logs`), over 10,500 requests occurred in the last 24 hours alone (~25,000+ over 2 days):
1. **Super Admin Web Polling (10s)**:
   - `gymos_admin/lib/core/widgets/admin_scaffold.dart`: `Timer.periodic(Duration(seconds: 10))` calls `fetchNotifications(limit: 10)` and `fetchUnreadCount()`. A single open tab produces **17,280 requests/day**.
2. **Mobile App Gym Status Polling (10s)**:
   - `lib/features/dashboard/main_navigation_holder.dart`: `_statusCheckTimer = Timer.periodic(Duration(seconds: 10))` calls `gyms.select('status')` and `fetchSubscriptionStatus()` every 10 seconds.
3. **Biometric Reception PC Bridge Polling (30s)**:
   - `biometric/gymos_biometric_bridge.js`: `setInterval(..., 30000)` hits `/rest/v1/rpc/poll_biometric_commands` 24 hours a day (**2,880 requests/day**), causing PostgREST thread timeouts (`Warp server error: Thread killed by timeout manager`).
4. **Mobile Alerts & Version Engine Polling (30s)**:
   - `lib/core/services/alerts_notification_engine.dart`: `Timer.periodic(Duration(seconds: 30))` queries `app_versions`, `notifications`, and RPC `check_membership_expiring_alerts` every 30 seconds.
5. **GymRepository Reachability Ping (30s)**:
   - `lib/core/repository/gym_repository.dart`: `isSupabaseReachable()` executes `from('gyms').select('id').limit(1)` every 30 seconds (**2,880 requests/day**).
6. **Realtime Wildcard Avalanche**:
   - `gym_repository.dart`: Subscribes to `onPostgresChanges` without `gym_id` filter. On any unhandled table event, falls into `else { syncAllFromSupabase(); }`, which downloads 15+ full tables with `select('*')`.
7. **Storage Logo Re-downloads**:
   - Gym logo was requested 194 times in 24 hours due to `Image.network` re-evaluations during UI rebuilds instead of persistent disk cache.

Each HTTP request generates ~15-20 KB of structured telemetry in Supabase (`edge_logs`, `postgrest_logs`, `postgres_logs`), producing **0.81 GB of Log Ingestion** and draining **0.46 GB Egress**.

---

## Detailed Action Plan

### Task 1: Eliminate Web Super Admin 10-Second Polling
- **File**: `gymos_admin/lib/core/widgets/admin_scaffold.dart`
- **Changes**:
  - Replace `Timer.periodic(Duration(seconds: 10))` with Supabase Realtime subscription on `admin_notifications` table.
  - Add fallback periodic refresh with a relaxed interval (e.g., 5 minutes or on manual bell click / window focus).
  - Reduce initial load to unread count only; load full list only when notification panel is opened.

### Task 2: Eliminate Mobile `main_navigation_holder.dart` 10-Second Status Loop
- **File**: `lib/features/dashboard/main_navigation_holder.dart`
- **Changes**:
  - Remove `_statusCheckTimer = Timer.periodic(const Duration(seconds: 10), ...)`.
  - Check gym status only:
    1. Once on initial login/app startup.
    2. When app resumes from background (`AppLifecycleState.resumed`).
    3. On manual pull-to-refresh or via Realtime update on `gyms` table.

### Task 3: Optimize Mobile Alerts & Version Check Engine
- **File**: `lib/core/services/alerts_notification_engine.dart`
- **Changes**:
  - Move `VersionCheckService.checkVersion()` to run once on app launch and once when resuming from background (never in a 30s periodic timer).
  - Move `check_membership_expiring_alerts` to run once on login / day boundary rather than every 30 seconds.
  - Rely on the existing Realtime listener for new notifications instead of querying `from('notifications').select()` every 30 seconds.

### Task 4: Fix `GymRepository` Polling & Realtime Wildcard Avalanche
- **File**: `lib/core/repository/gym_repository.dart`
- **Changes**:
  - Remove `isSupabaseReachable()` 30-second ping to `gyms`. Use local connectivity state (`Connectivity().checkConnectivity()`) or perform ping only when an unsynced offline operation is waiting in queue.
  - Change `_syncTimer` from 30 seconds to run only when offline queue has pending items or when explicitly triggered.
  - Add strict filter to `_subscribeToRealtime`: `filter: 'gym_id=eq.$gymId'`.
  - Remove wildcard fallback `else { syncAllFromSupabase(); }`. Only sync the specific table affected by the payload.

### Task 5: Optimize Biometric Bridge Polling
- **Files**: `biometric/gymos_biometric_bridge.js`, `biometric/gymos_biometric_bridge.py`, `biometric_bridge/gymos_biometric_bridge.py`
- **Changes**:
  - Increase default `sync_commands_interval_seconds` from 30 seconds to 300 seconds (5 minutes) when idle.
  - Implement adaptive exponential backoff: when no commands are pending, poll every 5 minutes. When commands are found, poll again immediately or at 10 seconds until queue is empty.
  - Avoid unnecessary empty calls and eliminate PostgREST timeouts.

### Task 6: Implement Disk Caching for Storage Images
- **Files**: `lib/core/widgets/app_cached_gym_logo.dart`, `lib/features/dashboard/dashboard_screen.dart`
- **Changes**:
  - Ensure gym logo and avatars use `CachedNetworkImage` with memory & disk cache, preventing repeated storage roundtrips on widget rebuilds.

---

## Verification Criteria
1. Re-query ClickHouse logs (`query_logs`) over a 10-minute window to verify request rate drops from ~20 req/min down to <1 req/min when idle.
2. Confirm zero PostgREST timeout errors (`Warp server error`).
3. Verify that Realtime updates (member added, attendance marked) still propagate instantly without relying on aggressive polling.
4. Verify all tests and code analysis pass without regressions.
