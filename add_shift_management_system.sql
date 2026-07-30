-- ====================================================
-- GYMOS - SHIFT MANAGEMENT SYSTEM MIGRATION
-- ====================================================

-- 1. Create Shift Settings Configuration Table
CREATE TABLE IF NOT EXISTS public.gym_shift_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    mode TEXT NOT NULL DEFAULT 'Single Shift' CHECK (mode IN ('Single Shift', 'Two Shifts')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT uniq_gym_shift_settings UNIQUE (gym_id)
);

-- 2. Create Shift Definition Table
CREATE TABLE IF NOT EXISTS public.gym_shifts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    shift_type TEXT NOT NULL CHECK (shift_type IN ('Single Shift', 'Morning Shift', 'Evening Shift')),
    start_time TEXT NOT NULL, -- e.g. "05:00 AM"
    end_time TEXT NOT NULL, -- e.g. "10:00 PM"
    start_time_24h TIME NOT NULL,
    end_time_24h TIME NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    CONSTRAINT uniq_gym_shift_type UNIQUE (gym_id, shift_type)
);

-- 3. Create Staff Shift Assignments Table (Normalized for historical integrity)
CREATE TABLE IF NOT EXISTS public.staff_shift_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL REFERENCES public.staff(id) ON DELETE CASCADE,
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    shift_id UUID REFERENCES public.gym_shifts(id) ON DELETE CASCADE, -- Null if Both Shifts
    assignment_type TEXT NOT NULL CHECK (assignment_type IN ('Single Shift', 'Morning Shift', 'Evening Shift', 'Both Shifts')),
    effective_from DATE DEFAULT CURRENT_DATE NOT NULL,
    effective_to DATE,
    status TEXT NOT NULL DEFAULT 'Active' CHECK (status IN ('Active', 'Completed', 'Cancelled')),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_gym_shifts_gym ON public.gym_shifts(gym_id);
CREATE INDEX IF NOT EXISTS idx_staff_shift_assignments_staff ON public.staff_shift_assignments(staff_id, status);
CREATE INDEX IF NOT EXISTS idx_staff_shift_assignments_dates ON public.staff_shift_assignments(staff_id, effective_from, effective_to);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.gym_shift_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gym_shifts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.staff_shift_assignments ENABLE ROW LEVEL SECURITY;

-- Define RLS Policies
DROP POLICY IF EXISTS gym_isolation_policy_shift_settings ON public.gym_shift_settings;
CREATE POLICY gym_isolation_policy_shift_settings ON public.gym_shift_settings
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS gym_isolation_policy_shifts ON public.gym_shifts;
CREATE POLICY gym_isolation_policy_shifts ON public.gym_shifts
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS gym_isolation_policy_assignments ON public.staff_shift_assignments;
CREATE POLICY gym_isolation_policy_assignments ON public.staff_shift_assignments
    FOR ALL TO authenticated
    USING (gym_id IN (SELECT gym_id FROM public.user_gym_associations WHERE user_id = auth.uid()));

-- Grant table access
GRANT ALL ON TABLE public.gym_shift_settings TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.gym_shifts TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.staff_shift_assignments TO anon, authenticated, service_role;

-- ====================================================
-- TRIGGERS, VALIDATIONS AND RPC FUNCTIONS
-- ====================================================

-- Trigger function to validate non-overlapping shifts for "Two Shifts" mode
CREATE OR REPLACE FUNCTION public.fn_validate_gym_shifts()
RETURNS TRIGGER AS $$
DECLARE
    v_mode TEXT;
    v_morning_end TIME;
    v_evening_start TIME;
BEGIN
    -- Get gym shift settings mode
    SELECT mode INTO v_mode FROM public.gym_shift_settings WHERE gym_id = NEW.gym_id;
    
    -- If two shifts, make sure Morning End < Evening Start
    IF v_mode = 'Two Shifts' THEN
        -- Get timings
        IF NEW.shift_type = 'Morning Shift' THEN
            v_morning_end := NEW.end_time_24h;
            SELECT start_time_24h INTO v_evening_start FROM public.gym_shifts WHERE gym_id = NEW.gym_id AND shift_type = 'Evening Shift';
        ELSIF NEW.shift_type = 'Evening Shift' THEN
            v_evening_start := NEW.start_time_24h;
            SELECT end_time_24h INTO v_morning_end FROM public.gym_shifts WHERE gym_id = NEW.gym_id AND shift_type = 'Morning Shift';
        END IF;

        IF v_morning_end IS NOT NULL AND v_evening_start IS NOT NULL AND v_morning_end >= v_evening_start THEN
            RAISE EXCEPTION 'Morning shift end time must be before Evening shift start time.';
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_validate_gym_shifts
BEFORE INSERT OR UPDATE ON public.gym_shifts
FOR EACH ROW
EXECUTE FUNCTION public.fn_validate_gym_shifts();


-- Trigger function to manage effective dates and complete old assignments automatically
CREATE OR REPLACE FUNCTION public.fn_manage_staff_shift_assignments()
RETURNS TRIGGER AS $$
BEGIN
    -- Terminate any previous active shift assignments of this staff member
    IF NEW.status = 'Active' THEN
        UPDATE public.staff_shift_assignments
        SET status = 'Completed',
            effective_to = NEW.effective_from - INTERVAL '1 day'
        WHERE staff_id = NEW.staff_id
          AND status = 'Active'
          AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER trg_manage_staff_shift_assignments
BEFORE INSERT OR UPDATE ON public.staff_shift_assignments
FOR EACH ROW
EXECUTE FUNCTION public.fn_manage_staff_shift_assignments();


-- RPC to save or update Operating Hours (Gym Settings)
CREATE OR REPLACE FUNCTION public.save_gym_operating_hours(
    p_gym_id UUID,
    p_mode TEXT,
    p_shifts JSONB -- Array of shifts, e.g. [{"type": "Morning Shift", "start": "05:00 AM", "end": "11:00 AM", "start_24": "05:00:00", "end_24": "11:00:00"}]
)
RETURNS VOID AS $$
DECLARE
    shift_record RECORD;
BEGIN
    -- Insert or update shift settings
    INSERT INTO public.gym_shift_settings (gym_id, mode, updated_at)
    VALUES (p_gym_id, p_mode, now())
    ON CONFLICT (gym_id) DO UPDATE
    SET mode = EXCLUDED.mode,
        updated_at = now();

    -- Delete old shifts of type that are not in the new configuration
    -- (e.g. if switching to Single Shift, delete Morning/Evening shifts)
    IF p_mode = 'Single Shift' THEN
        DELETE FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type IN ('Morning Shift', 'Evening Shift');
    ELSE
        DELETE FROM public.gym_shifts WHERE gym_id = p_gym_id AND shift_type = 'Single Shift';
    END IF;

    -- Upsert shifts
    FOR shift_record IN SELECT * FROM jsonb_to_recordset(p_shifts) AS x(type TEXT, start_t TEXT, end_t TEXT, start_24 TEXT, end_24 TEXT) LOOP
        INSERT INTO public.gym_shifts (gym_id, shift_type, start_time, end_time, start_time_24h, end_time_24h)
        VALUES (p_gym_id, shift_record.type, shift_record.start_t, shift_record.end_t, shift_record.start_24::TIME, shift_record.end_24::TIME)
        ON CONFLICT (gym_id, shift_type) DO UPDATE
        SET start_time = EXCLUDED.start_time,
            end_time = EXCLUDED.end_time,
            start_time_24h = EXCLUDED.start_time_24h,
            end_time_24h = EXCLUDED.end_time_24h;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- RPC to get current shift assignment for a staff member
CREATE OR REPLACE FUNCTION public.get_active_staff_shift(p_staff_id UUID)
RETURNS TABLE (
    assignment_id UUID,
    assignment_type TEXT,
    shift_id UUID,
    shift_type TEXT,
    start_time TEXT,
    end_time TEXT,
    effective_from DATE,
    effective_to DATE,
    status TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.id AS assignment_id,
        a.assignment_type,
        a.shift_id,
        s.shift_type,
        COALESCE(s.start_time, ''),
        COALESCE(s.end_time, ''),
        a.effective_from,
        a.effective_to,
        a.status
    FROM public.staff_shift_assignments a
    LEFT JOIN public.gym_shifts s ON a.shift_id = s.id
    WHERE a.staff_id = p_staff_id AND a.status = 'Active'
    LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
