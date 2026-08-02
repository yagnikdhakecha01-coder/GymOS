-- ====================================================
-- MIGRATION: offline_first_setup.sql
-- Description: Adapts attendance_logs to support nullable user_id (for pending profiles)
-- ====================================================

-- 1. Drop the NOT NULL constraint on user_id to allow check-in for members/staff pending activation
ALTER TABLE public.attendance_logs ALTER COLUMN user_id DROP NOT NULL;

-- 2. Add performance index optimizations for faster verification queries
CREATE INDEX IF NOT EXISTS idx_attendance_logs_member_id ON public.attendance_logs(member_id);
CREATE INDEX IF NOT EXISTS idx_attendance_logs_staff_id ON public.attendance_logs(staff_id);
CREATE INDEX IF NOT EXISTS idx_attendance_logs_uuid ON public.attendance_logs(id);
