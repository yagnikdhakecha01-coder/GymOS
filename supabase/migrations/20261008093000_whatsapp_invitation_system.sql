-- Migration: 20261008093000_whatsapp_invitation_system.sql
-- Description: Sets up default platform_settings for WhatsApp invitation templates

CREATE TABLE IF NOT EXISTS public.platform_settings (
    key TEXT PRIMARY KEY,
    value JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS platform_settings_all ON public.platform_settings;
CREATE POLICY platform_settings_all ON public.platform_settings FOR ALL USING (true);

GRANT ALL ON public.platform_settings TO anon, authenticated, service_role;

-- Seed default settings (SAFE MODE: auto_send_enabled = FALSE by default)
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
