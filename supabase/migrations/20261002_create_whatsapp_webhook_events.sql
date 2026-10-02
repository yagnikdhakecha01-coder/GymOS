-- Migration: 20261002_create_whatsapp_webhook_events.sql
-- Description: Isolated tables for WhatsApp Cloud API webhook intake, deduplication, and server-side secret fallback
-- Safety: Completely isolated tables; zero impact on existing tables, RLS policies, or production data.

CREATE TABLE IF NOT EXISTS public.whatsapp_webhook_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    provider TEXT NOT NULL DEFAULT 'meta',
    event_type TEXT,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processing_status TEXT NOT NULL DEFAULT 'received',
    payload_hash TEXT,
    meta_message_id TEXT UNIQUE,
    error_message TEXT
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.whatsapp_webhook_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.whatsapp_webhook_events FROM anon, authenticated;
GRANT ALL ON public.whatsapp_webhook_events TO service_role;

-- Secure isolated secrets store for Edge Functions
CREATE TABLE IF NOT EXISTS public.whatsapp_system_secrets (
    secret_name TEXT PRIMARY KEY,
    secret_value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.whatsapp_system_secrets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.whatsapp_system_secrets FROM anon, authenticated;
GRANT ALL ON public.whatsapp_system_secrets TO service_role;
