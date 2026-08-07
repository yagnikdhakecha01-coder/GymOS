-- Staff Custom Shifts & Attendance Migration
-- Adds support for Single vs Both Shift (Double Shift) with custom start/end times and 1-hour late/absent rule

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

-- Add shift index and late tracking to staff attendance table
ALTER TABLE staff_attendance
ADD COLUMN IF NOT EXISTS shift_index INT DEFAULT 1,
ADD COLUMN IF NOT EXISTS shift_type TEXT DEFAULT 'single',
ADD COLUMN IF NOT EXISTS is_late BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS late_minutes INT DEFAULT 0;

-- Enable RLS & grants
ALTER TABLE staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_attendance ENABLE ROW LEVEL SECURITY;
