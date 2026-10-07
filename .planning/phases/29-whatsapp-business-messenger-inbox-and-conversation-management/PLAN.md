# Phase 29: WhatsApp Business Messenger & Two-Way Conversation Inbox in GymOS Admin

## Goal
Build a full-featured, two-way WhatsApp Business Messenger inbox inside the GymOS Admin Web Portal (`gymos_admin`). Enable the GymOS administrator to view all WhatsApp conversations, read incoming replies from gym members and inquiries, compose and send direct outbound WhatsApp messages, and monitor real-time delivery statuses (`sent`, `delivered`, `read`) using Meta WhatsApp Cloud API and Supabase.

---

## 🔒 Production Safety & Architecture Principles
1. **Zero Breaking Changes**: Existing 74 production tables (`gyms`, `members`, `attendance`, `finance_transactions`) remain completely untouched.
2. **Isolated Messaging Schema**: All WhatsApp chat data is housed in isolated tables (`whatsapp_messages`).
3. **Secure Credential Access**: Outbound WhatsApp messaging leverages the verified permanent System User Token (`WHATSAPP_ACCESS_TOKEN`) and Phone Number ID securely stored in `platform_settings` and `whatsapp_system_secrets`.
4. **Realtime Reactivity**: Leverages Supabase Realtime / polling for instant message delivery and incoming notifications without page reload.

---

## Architecture Blueprint

```
[Customer / Gym Member]
       │
       │ (1. Sends WhatsApp Message)
       ▼
[Meta WhatsApp Cloud API]
       │
       │ (2. POST Webhook Delivery)
       ▼
[Supabase Edge Function: whatsapp-webhook]
       │
       │ (3. Ingests & Parsers payload)
       ▼
[Supabase Database: whatsapp_messages]
       │
       │ (4. Realtime Stream / Change Listener)
       ▼
[GymOS Admin Panel: WhatsApp Messenger UI]
       │
       │ (5. Admin reads & types reply -> Clicks Send)
       ▼
[Meta Cloud API: POST /{PHONE_NUMBER_ID}/messages]
       │
       ▼
[Customer Receives Reply on WhatsApp]
```

---

## Implementation Waves

### Wave 1: Database Migration & Schema Design (`whatsapp_messages`)
- Create `whatsapp_messages` table:
  - `id`: `uuid PRIMARY KEY DEFAULT gen_random_uuid()`
  - `wamid`: `text UNIQUE` (Meta WhatsApp message ID)
  - `phone_number`: `text NOT NULL` (E.164 formatted recipient/sender phone)
  - `sender_name`: `text` (Profile name from Meta or GymOS member name)
  - `direction`: `text NOT NULL` (`'inbound'` or `'outbound'`)
  - `message_type`: `text NOT NULL DEFAULT 'text'` (`'text'`, `'image'`, `'template'`)
  - `message_body`: `text NOT NULL`
  - `status`: `text NOT NULL DEFAULT 'sent'` (`'sent'`, `'delivered'`, `'read'`, `'failed'`, `'received'`)
  - `meta_payload`: `jsonb`
  - `created_at`: `timestamptz NOT NULL DEFAULT now()`
- Create optimized indexes on `phone_number` and `created_at DESC`.
- Create a performant view or helper function `get_whatsapp_inbox()` to aggregate conversations:
  - Contact phone number, latest message preview, latest timestamp, unread message count.
- Enable RLS policies granting full read/write to `service_role` and authenticated GymOS admin.

### Wave 2: Webhook Ingestion Enhancement (`supabase/functions/whatsapp-webhook`)
- Upgrade `whatsapp-webhook/index.ts` to automatically extract:
  - Incoming text messages: `entry[0].changes[0].value.messages[0]` (`from`, `text.body`, `id`).
  - Contact name: `entry[0].changes[0].value.contacts[0].profile.name`.
  - Delivery status updates: `entry[0].changes[0].value.statuses[0]` (`id`, `status`, `recipient_id`).
- Upsert incoming messages and update status receipts into `whatsapp_messages` in real time.

### Wave 3: WhatsApp Messenger UI in GymOS Admin (`gymos_admin`)
- Create new feature package: `gymos_admin/lib/features/whatsapp/`
  - `whatsapp_messenger_screen.dart`: Main two-pane split layout.
  - `widgets/conversation_list_pane.dart`:
    - Search bar (filter by phone number or contact name).
    - "New Message" action button to start a conversation with any phone number.
    - Conversation tile with avatar, name/phone, last message snippet, timestamp, and unread badge.
  - `widgets/chat_conversation_pane.dart`:
    - Header: Contact avatar, phone number, name, Meta connection status badge.
    - Message history bubble list:
      - Inbound bubbles (left-aligned, neutral card background).
      - Outbound bubbles (right-aligned, primary brand accent).
      - Status checkmarks: `sent` (✓), `delivered` (✓✓), `read` (✓✓ blue).
    - Footer / Input bar:
      - Text input controller with multi-line support.
      - Quick template selector or preset greeting picker.
      - Send button with loading state.
  - `services/whatsapp_chat_service.dart`:
    - Fetch conversation inbox summary.
    - Fetch message thread for a selected phone number.
    - Send outbound message directly via Meta Graph API using stored credentials.
    - Realtime stream listener / periodic auto-sync.

### Wave 4: Navigation Integration & App Shell Registration
- Update `gymos_admin/lib/core/widgets/admin_scaffold.dart`:
  - Add `SidebarMenuItem(icon: Icons.chat_outlined, activeIcon: Icons.chat_rounded, label: 'WhatsApp')`.
- Update `gymos_admin/lib/main.dart`:
  - Register `WhatsAppMessengerScreen` in `AdminScaffold.pages`.
- Ensure responsive behavior on both desktop and tablet screens.

### Wave 5: Verification & Production Testing
- Verify database tables and RLS permissions.
- Test sending an outbound WhatsApp message to a test mobile number.
- Verify message appears in Admin chat window with "sent" status.
- Test receiving an inbound WhatsApp reply and verifying auto-ingestion in the inbox.
- Commit all changes and push to `gymos_admin` repository.

---

## Verification & Acceptance Criteria
- [ ] Admin sidebar contains a dedicated "WhatsApp" navigation tab.
- [ ] Conversations inbox lists all active phone chats with latest message snippet and timestamp.
- [ ] Clicking any conversation opens the full message history in the right pane.
- [ ] Admin can type a message, click Send, and the message delivers to the customer's WhatsApp via Meta Cloud API.
- [ ] Inbound messages sent by customers on WhatsApp automatically appear in the conversation thread.
- [ ] "New Chat" allows starting a message thread with any phone number.
- [ ] Code is formatted, builds without errors, and pushed to git.
