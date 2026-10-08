-- ==============================================================================
-- GYMOS: AUTOMATED WHATSAPP INVITATION SYSTEM SCHEMA & SETTINGS
-- Description: Sets up default platform_settings for WhatsApp invitation templates
-- and documents database webhook trigger for Supabase Edge Functions.
-- ==============================================================================

-- 1. Ensure platform_settings table exists
CREATE TABLE IF NOT EXISTS public.platform_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Ensure RLS & permissions
ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS platform_settings_all ON public.platform_settings;
CREATE POLICY platform_settings_all ON public.platform_settings FOR ALL USING (true);

GRANT ALL ON public.platform_settings TO anon, authenticated, service_role;

-- 3. Seed default whatsapp_invitation_settings (SAFE MODE: auto_send_enabled = FALSE by default)
INSERT INTO public.platform_settings (key, value, updated_at)
VALUES (
    'whatsapp_invitation_settings',
    jsonb_build_object(
        'auto_send_enabled', false,
        'template_name', '',
        'template_language', 'en_US',
        'param_mapping', jsonb_build_object(
            '1', 'gym_name',
            '2', 'name',
            '3', 'invitation_code',
            '4', 'phone'
        )
    ),
    now()
)
ON CONFLICT (key) DO NOTHING;

-- 4. Ensure whatsapp_messages table exists for logging & inbox tracking
CREATE TABLE IF NOT EXISTS public.whatsapp_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    wamid TEXT UNIQUE,
    phone_number TEXT NOT NULL,
    sender_name TEXT,
    direction TEXT NOT NULL,
    message_type TEXT NOT NULL DEFAULT 'text',
    message_body TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'sent',
    meta_payload JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_whatsapp_messages_phone ON public.whatsapp_messages(phone_number);
CREATE INDEX IF NOT EXISTS idx_whatsapp_messages_created ON public.whatsapp_messages(created_at DESC);

ALTER TABLE public.whatsapp_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS whatsapp_messages_all ON public.whatsapp_messages;
CREATE POLICY whatsapp_messages_all ON public.whatsapp_messages FOR ALL USING (true);

GRANT ALL ON public.whatsapp_messages TO anon, authenticated, service_role;

-- ==============================================================================
-- 5. SUPABASE DATABASE WEBHOOK INSTRUCTIONS:
-- In Supabase Dashboard -> Database -> Webhooks:
-- Name: auto_send_whatsapp_invitation
-- Table: public.invitations
-- Events: INSERT
-- HTTP Request:
--   URL: https://<PROJECT_REF>.supabase.co/functions/v1/whatsapp-send-invitation
--   Method: POST
--   Headers: Authorization: Bearer <SERVICE_ROLE_KEY>
-- Note: The Edge Function checks 'auto_send_enabled' in platform_settings.
-- If disabled, it safely skips execution without sending messages.
-- ==============================================================================
