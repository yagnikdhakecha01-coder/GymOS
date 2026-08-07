-- Staff Custom Shifts & Attendance Migration (Updated for attendance_logs)
-- Adds support for Single vs Both Shift (Double Shift) with custom start/end times and 1-hour late/absent rule

-- 1. Update staff table
ALTER TABLE staff 
ADD COLUMN IF NOT EXISTS shift_type TEXT DEFAULT 'single',
ADD COLUMN IF NOT EXISTS shift1_start TEXT DEFAULT '09:00 AM',
ADD COLUMN IF NOT EXISTS shift1_end TEXT DEFAULT '05:00 PM',
ADD COLUMN IF NOT EXISTS shift2_start TEXT DEFAULT '04:00 PM',
ADD COLUMN IF NOT EXISTS shift2_end TEXT DEFAULT '09:00 PM';

-- Update existing shift column for backward compatibility
UPDATE staff 
SET shift = CASE 
    WHEN shift_type = 'both' THEN COALESCE(shift1_start, '09:00 AM') || ' - ' || COALESCE(shift1_end, '01:00 PM') || ' & ' || COALESCE(shift2_start, '04:00 PM') || ' - ' || COALESCE(shift2_end, '09:00 PM')
    ELSE COALESCE(shift1_start, '09:00 AM') || ' - ' || COALESCE(shift1_end, '05:00 PM')
END
WHERE shift IS NULL OR shift = '';

-- 2. Update attendance_logs table safely
DO $$ 
BEGIN 
    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'attendance_logs') THEN
        ALTER TABLE attendance_logs
        ADD COLUMN IF NOT EXISTS shift_index INT DEFAULT 1,
        ADD COLUMN IF NOT EXISTS shift_type TEXT DEFAULT 'single',
        ADD COLUMN IF NOT EXISTS is_late BOOLEAN DEFAULT false,
        ADD COLUMN IF NOT EXISTS late_minutes INT DEFAULT 0;
    END IF;

    IF EXISTS (SELECT FROM pg_tables WHERE tablename = 'staff_attendance') THEN
        ALTER TABLE staff_attendance
        ADD COLUMN IF NOT EXISTS shift_index INT DEFAULT 1,
        ADD COLUMN IF NOT EXISTS shift_type TEXT DEFAULT 'single',
        ADD COLUMN IF NOT EXISTS is_late BOOLEAN DEFAULT false,
        ADD COLUMN IF NOT EXISTS late_minutes INT DEFAULT 0;
    END IF;
END $$;

-- Enable RLS
ALTER TABLE staff ENABLE ROW LEVEL SECURITY;
