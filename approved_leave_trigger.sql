-- =========================================================================
-- DATABASE TRIGGER: AUTOMATIC ATTENDANCE LOG GENERATION ON APPROVED LEAVE
-- Copy and run this script in your Supabase SQL Editor.
-- =========================================================================

-- 1. Create trigger function to handle approved leaves
CREATE OR REPLACE FUNCTION public.fn_process_approved_leave()
RETURNS TRIGGER AS $$
DECLARE
    v_curr_date DATE;
    v_date_str TEXT;
    v_user_id UUID;
    v_check_in TIMESTAMPTZ;
    v_check_out TIMESTAMPTZ;
BEGIN
    -- Only execute when status changes to 'Approved'
    IF NEW.status = 'Approved' AND (TG_OP = 'INSERT' OR OLD.status <> 'Approved') THEN
        -- Get the staff member's user_id
        SELECT user_id INTO v_user_id
        FROM public.staff
        WHERE id = NEW.staff_id;

        -- Loop through dates from start_date to end_date
        v_curr_date := NEW.start_date;
        WHILE v_curr_date <= NEW.end_date LOOP
            v_date_str := to_char(v_curr_date, 'dd-MM-yyyy');
            v_check_in := (v_curr_date::TEXT || ' 09:00:00')::TIMESTAMPTZ;
            v_check_out := (v_curr_date::TEXT || ' 17:00:00')::TIMESTAMPTZ;

            -- Check if attendance log already exists for this staff on this date
            IF EXISTS (
                SELECT 1 FROM public.attendance_logs 
                WHERE staff_id = NEW.staff_id AND date = v_date_str
            ) THEN
                -- Update status to 'Holiday' for the leave day
                UPDATE public.attendance_logs
                SET status = 'Holiday',
                    updated_at = now()
                WHERE staff_id = NEW.staff_id AND date = v_date_str;
            ELSE
                -- Insert a new attendance log
                INSERT INTO public.attendance_logs (
                    gym_id,
                    user_id,
                    staff_id,
                    date,
                    check_in,
                    check_out,
                    status,
                    method
                ) VALUES (
                    NEW.gym_id,
                    v_user_id,
                    NEW.staff_id,
                    v_date_str,
                    v_check_in,
                    v_check_out,
                    'Holiday',
                    'Manual'
                );
            END IF;

            v_curr_date := v_curr_date + INTERVAL '1 day';
        END LOOP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Attach trigger to leave_requests table
DROP TRIGGER IF EXISTS trg_process_approved_leave ON public.leave_requests;
CREATE TRIGGER trg_process_approved_leave
AFTER INSERT OR UPDATE ON public.leave_requests
FOR EACH ROW
EXECUTE FUNCTION public.fn_process_approved_leave();
