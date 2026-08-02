-- ===================================================================
-- EMERGENCY ATTENDANCE RECOVERY SYSTEM - DATABASE SCHEMA
-- ===================================================================

-- 1. Create Audit Logs Table for tracking all manual actions & corrections
CREATE TABLE IF NOT EXISTS public.attendance_audit_log (
    id UUID PRIMARY KEY,
    gym_id UUID NOT NULL,
    action_type TEXT NOT NULL CHECK (action_type IN ('manual_attendance', 'attendance_correction')),
    performed_by TEXT NOT NULL,
    performed_by_role TEXT NOT NULL,
    target_user_name TEXT NOT NULL,
    target_user_type TEXT NOT NULL CHECK (target_user_type IN ('Member', 'Staff')),
    target_user_id UUID NOT NULL,
    date TEXT NOT NULL, -- Format: 'dd-MM-yyyy'
    old_status TEXT,
    new_status TEXT,
    old_check_in TEXT,
    new_check_in TEXT,
    old_check_out TEXT,
    new_check_out TEXT,
    old_shift TEXT,
    new_shift TEXT,
    reason TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable RLS on audit logs
ALTER TABLE public.attendance_audit_log ENABLE ROW LEVEL SECURITY;

-- Create policies for attendance_audit_log
CREATE POLICY "Enable read access for authenticated users"
    ON public.attendance_audit_log
    FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Enable insert access for authenticated users"
    ON public.attendance_audit_log
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- 2. Optimize search performance on attendance logs
CREATE INDEX IF NOT EXISTS idx_attendance_logs_gym_user_date 
    ON public.attendance_logs(gym_id, user_id, date);

-- 3. Trigger / Backend logic helper: Resolve absent conflicts automatically
-- This removes any auto-absent record when a manual check-in or present record is synced
CREATE OR REPLACE FUNCTION public.resolve_absent_conflict(
    p_gym_id UUID,
    p_user_id UUID,
    p_date TEXT
)
RETURNS VOID AS $$
BEGIN
    DELETE FROM public.attendance_logs
    WHERE gym_id = p_gym_id
      AND user_id = p_user_id
      AND date = p_date
      AND status = 'Absent';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
