-- =========================================================================
-- DATABASE MIGRATION: add_gross_salary_column.sql
-- Run this script in your Supabase SQL Editor to add gross_salary
-- as an automatic generated column in your public.salary_drafts table.
-- =========================================================================

ALTER TABLE public.salary_drafts 
ADD COLUMN IF NOT EXISTS gross_salary NUMERIC(12, 2) 
GENERATED ALWAYS AS (base_salary + commission_amount + other_additions - other_deductions) STORED;
