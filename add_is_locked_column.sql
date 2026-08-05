-- =========================================================================
-- DATABASE MIGRATION: add_is_locked_column.sql
-- Run this script in your Supabase SQL Editor to add is_locked to gyms table
-- =========================================================================

ALTER TABLE public.gyms 
ADD COLUMN IF NOT EXISTS is_locked BOOLEAN DEFAULT false;
