# Phase 30: Automated WhatsApp Invitation System, Bulk Dispatch for Pending Members/Staff, & Admin Navigation/Theme Persistence

## Goal
Build an automated and configurable WhatsApp invitation messaging system using Meta WhatsApp Cloud API. Allow GymOS Super Admin to configure invitation templates with dynamic parameters (Gym Name, Member/Staff Name, Invitation Code, Registered Mobile Number), control automated dispatch with an ON/OFF master toggle (default: OFF), and trigger bulk invitation messaging for existing pending members and staff directly from the Admin Gym Dashboard. Fix website state persistence so page reload preserves dark/light mode and keeps the user on their active page. Push all completed code to GitHub.

---

## 🔒 Production Safety & Architecture Principles
1. **Zero Breaking Changes to Existing Tables**: The existing 74 production tables (`gyms`, `members`, `staff`, `invitations`, `whatsapp_messages`) remain fully backwards-compatible.
2. **Master Kill-Switch (Default: Disabled)**: In accordance with explicit requirement, automated WhatsApp messaging upon database record insertion will be **strictly disabled by default** (`auto_send_enabled: false`) until explicitly toggled ON by the Super Admin in the Admin Panel.
3. **Template Parameter Safety**: Validates all dynamic variables (`{{1}}`, `{{2}}`, `{{3}}`, `{{4}}`) against the configured Meta template structure before dispatch, preventing Meta Graph API rejection.
4. **Resilient Local Persistence**: Uses robust browser `localStorage` and URL hash routing synchronization to ensure theme (`ThemeMode.dark` / `ThemeMode.light`) and active navigation tab (`_selectedIndex`) are preserved across browser refreshes.
5. **Rate-Limit & Batch Safety**: Bulk dispatch incorporates pacing (delays between messages) to comply with Meta Cloud API rate limits and avoid spam flags.

---

## Architecture Blueprint

```
                     ┌─────────────────────────────────────────────────────────┐
                     │          GymOS Admin Web Portal (gymos_admin)           │
                     └───────┬─────────────────────────────────┬───────────────┘
                             │                                 │
           1. Configure Template & Toggle       2. Manual Bulk Send Button
           (Saved to platform_settings)         (Selected Gym -> Pending Members)
                             │                                 │
                             ▼                                 ▼
                     ┌────────────────┐               ┌────────────────┐
                     │platform_settings│               │  Bulk Dispatch │
                     │(whatsapp_config│               │    Executor    │
                     └───────┬────────┘               └────────┬───────┘
                             │                                 │
          ┌──────────────────┴──────────────────┐              │
          │ (When auto_send_enabled == true)     │              │
          ▼                                     ▼              ▼
┌──────────────────┐                  ┌────────────────────────────────────────┐
│ Owner/Reception  │                  │       Meta WhatsApp Cloud API          │
│ Adds Member/Staff│                  │   POST /v20.0/{PHONE_ID}/messages      │
└─────────┬────────┘                  └──────────────────┬─────────────────────┘
          │                                              │
          ▼ (Inserts into invitations)                   ▼
┌──────────────────┐                  ┌────────────────────────────────────────┐
│Supabase DB Trigger│                  │ Customer Receives Official WhatsApp    │
│/ Edge Function   │──(Dispatches)───►│ Template with Gym Name, Code & Phone   │
└──────────────────┘                  └────────────────────────────────────────┘
```

---

## Implementation Waves

### Wave 1: Admin Web Portal Navigation & Dark Mode State Persistence (`gymos_admin`)
- **Theme Mode Persistence (`core/providers/theme_provider.dart`)**:
  - Implement web `localStorage` key `'gymos_admin_theme_mode'`.
  - On app startup, read `'gymos_admin_theme_mode'`. If `'dark'`, initialize with `ThemeMode.dark`.
  - When `toggle()` or `setTheme()` is called, immediately persist the choice to `localStorage`.
  - Ensure reloads preserve dark mode without flashing light mode.
- **Navigation & Active Page Persistence (`core/providers/navigation_provider.dart`)**:
  - Implement web `localStorage` key `'gymos_admin_active_tab_index'`.
  - Map each route/tab to a unique URL hash (e.g., `#dashboard`, `#gyms`, `#subscriptions`, `#whatsapp`, `#whatsapp-templates`, `#settings`).
  - On startup, read the initial index from URL hash or `localStorage`.
  - When `setIndex()` is called, sync both `localStorage` and `window.location.hash`.
  - On page refresh, the user remains exactly on the active screen.

### Wave 2: Platform Settings Schema & WhatsApp Invitation Template Configuration UI
- **Settings Data Contract (`platform_settings`)**:
  - Key: `whatsapp_invitation_settings`
  - Value structure:
    ```json
    {
      "auto_send_enabled": false,
      "template_name": "gym_invitation_code",
      "template_language": "en_US",
      "parameter_mapping": {
        "1": "gym_name",
        "2": "member_name",
        "3": "invitation_code",
        "4": "phone"
      },
      "updated_at": "ISO_TIMESTAMP"
    }
    ```
- **Admin Configuration UI (`features/whatsapp_templates/` or dedicated settings section)**:
  - Add **"Invitation Template Configuration"** card/tab:
    - **Master Auto-Send Switch**: "Auto-send WhatsApp invitation on new member/staff registration" (Default: OFF). Clear warning badge: *Currently Inactive until enabled*.
    - **Template Selector**: Live dropdown populated from Meta WhatsApp Cloud API via `WhatsAppTemplateService.fetchTemplates()`, filtering by `APPROVED` templates.
    - **Parameter Mapping Editor**: Interactive fields for `{{1}}`, `{{2}}`, `{{3}}`, `{{4}}`, letting admin assign `Gym Name`, `Member/Staff Name`, `Invitation Code`, or `Registered Mobile Number`.
    - **Test Send Button**: Quick modal to send a live test invitation message with sample data to the admin's phone number.
    - **Save Changes Button**: Updates `platform_settings` in Supabase with toast feedback.

### Wave 3: Automated Database / Edge Event for New Member & Staff
- **Edge Function / Database Trigger Strategy**:
  - Create Supabase Edge Function `whatsapp-send-invitation` (or database trigger with pg_net):
    - Reads `whatsapp_invitation_settings` from `platform_settings`.
    - If `auto_send_enabled` is `false`, gracefully exit immediately with log `Auto-send disabled by admin. Skipping.`.
    - If `auto_send_enabled` is `true`:
      - Resolves recipient phone, invitation code, recipient name, and gym name.
      - Assembles Meta template payload with mapped variables.
      - Dispatches to Meta Graph API.
      - Logs outbound template entry into `whatsapp_messages` table for real-time visibility in the WhatsApp Messenger inbox.

### Wave 4: Manual Bulk Invitation Dispatcher in Admin Gym Dashboard
- **Gym Dashboard Integration (`features/gyms/admin_gym_dashboard_screen.dart`)**:
  - Add primary action button in header / Quick Actions:
    **"Send Invitation to Pending Members & Staff"** (with WhatsApp icon).
  - Open an interactive dialog:
    - Queries `invitations` table for `gym_id = widget.gym['id']` where `status = 'Pending'` and `code_used = false`.
    - Displays total count of pending members and pending staff.
    - Displays the active template configured by admin.
    - Preview of message format with sample variables.
    - Action: **"Send to X Pending Recipients"**.
  - **Batch Execution Engine**:
    - Progressive loop iterating through pending records.
    - Sends template message via `WhatsAppTemplateService.instance.sendTemplateMessage()`.
    - Provides real-time progress bar (`Sent X of Y...`).
    - Handles invalid phone numbers or Meta rate limits gracefully without stopping the batch.
    - Shows final summary modal: Total sent, skipped, failed.

### Wave 5: End-to-End Verification, Production Build & Git Push
- Verify `ThemeProvider` and `NavigationProvider` state persistence across hard browser refreshes (`F5`).
- Verify template configuration saves and loads accurately from `platform_settings`.
- Verify bulk dispatcher identifies pending members/staff and dispatches messages with correct variables.
- Verify `auto_send_enabled` master switch stays disabled by default.
- Run `flutter analyze` or build verification to ensure no compilation errors.
- Stage, commit, and push all changes to the remote GitHub repository.

---

## Verification & Acceptance Criteria
- [ ] Reloading `gymos_admin` portal does NOT reset theme; dark mode remains dark mode.
- [ ] Reloading `gymos_admin` portal stays on the current active tab / screen instead of resetting to Dashboard.
- [ ] Admin can configure the WhatsApp invitation template and map variables (`{{gym_name}}`, `{{name}}`, `{{invitation_code}}`, `{{phone}}`).
- [ ] Auto-send on new registration is **DISABLED by default** and only triggers when admin toggles it ON.
- [ ] In Admin Gym Dashboard, admin can click "Send Invitation to Pending Members & Staff" to send template messages to all pending members/staff of that gym.
- [ ] Sent messages appear in `whatsapp_messages` and the WhatsApp Messenger inbox.
- [ ] All code changes are committed and pushed to GitHub.
