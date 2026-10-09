-- ============================================================
-- Phase 31: App Review Analytics Table
-- Migration: add_app_review_analytics.sql
--
-- Purpose: Log in-app review events (stars + role) for
-- understanding review funnel. No PII stored.
-- Run once in: Supabase Dashboard → SQL Editor → Run
-- ============================================================

CREATE TABLE IF NOT EXISTS app_review_events (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  gym_id      uuid,                          -- nullable (member may not have gym_id)
  role        text,                          -- 'owner' | 'staff' | 'member'
  stars       int CHECK (stars BETWEEN 1 AND 5),
  submitted   boolean DEFAULT false,         -- true = Play Store opened
  created_at  timestamptz DEFAULT now()
);

-- RLS: allow any authenticated user to INSERT their own event
ALTER TABLE app_review_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "auth_insert_review_events" ON app_review_events;
CREATE POLICY "auth_insert_review_events"
  ON app_review_events
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- No SELECT/UPDATE/DELETE policy needed — internal analytics only
