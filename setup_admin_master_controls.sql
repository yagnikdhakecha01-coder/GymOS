-- =========================================================================
-- GYMOS ADMIN MASTER CONTROLS & DIAGNOSTIC SYSTEM
-- Safe, transactional functions for Super Admin management
-- =========================================================================

-- 1. ADMIN UPDATE MEMBER GAMIFICATION
CREATE OR REPLACE FUNCTION public.admin_update_member_gamification(
    p_member_id UUID,
    p_level INT,
    p_xp INT,
    p_unlocked_badges TEXT[]
)
RETURNS JSONB AS $$
DECLARE
    v_new_title TEXT;
    v_unlocked_all BOOLEAN;
    v_never_miss BOOLEAN;
    v_365 BOOLEAN;
    v_badge TEXT;
    v_badge_count INT;
BEGIN
    -- Ensure achievements record exists
    INSERT INTO public.member_achievements (member_id)
    VALUES (p_member_id)
    ON CONFLICT (member_id) DO NOTHING;

    -- Ensure all badges are initialized
    PERFORM public.initialize_member_badges(p_member_id);

    -- 1. Update badges lock/unlock status
    UPDATE public.member_badge_status
    SET is_unlocked = (badge_key = ANY(p_unlocked_badges)),
        unlocked_at = CASE 
            WHEN badge_key = ANY(p_unlocked_badges) THEN COALESCE(unlocked_at, now())
            ELSE NULL 
        END,
        current_progress = CASE 
            WHEN badge_key = ANY(p_unlocked_badges) THEN target_value
            ELSE 0 
        END,
        updated_at = now()
    WHERE member_id = p_member_id;

    -- Check qualifications for title
    v_unlocked_all := ('first_step' = ANY(p_unlocked_badges) AND
                       'week_warrior' = ANY(p_unlocked_badges) AND
                       'perfect_month' = ANY(p_unlocked_badges) AND
                       'century_club' = ANY(p_unlocked_badges) AND
                       'club_365' = ANY(p_unlocked_badges) AND
                       'early_bird' = ANY(p_unlocked_badges) AND
                       'weekend_warrior' = ANY(p_unlocked_badges) AND
                       'monthly_machine' = ANY(p_unlocked_badges) AND
                       'half_year_hero' = ANY(p_unlocked_badges) AND
                       'loyal_member' = ANY(p_unlocked_badges) AND
                       'attendance_master' = ANY(p_unlocked_badges) AND
                       'rising_star' = ANY(p_unlocked_badges) AND
                       'elite_member' = ANY(p_unlocked_badges) AND
                       'never_miss_gym' = ANY(p_unlocked_badges));
    v_never_miss := 'never_miss_gym' = ANY(p_unlocked_badges);
    v_365 := 'club_365' = ANY(p_unlocked_badges);

    v_new_title := public.get_title_for_level(p_level, v_unlocked_all, v_never_miss, v_365);

    -- 2. Update achievements record
    UPDATE public.member_achievements
    SET current_level = GREATEST(1, LEAST(99, p_level)),
        current_xp = GREATEST(0, p_xp),
        current_title = v_new_title,
        updated_at = now()
    WHERE member_id = p_member_id;

    -- 3. Log to history
    INSERT INTO public.xp_history (member_id, xp_change, source, description)
    VALUES (p_member_id, p_xp, 'Admin Override', format('Admin set Level %s (%s XP, Title: %s)', p_level, p_xp, v_new_title));

    RETURN jsonb_build_object(
        'success', true,
        'level', p_level,
        'xp', p_xp,
        'title', v_new_title,
        'badges_unlocked', array_length(p_unlocked_badges, 1)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.admin_update_member_gamification(UUID, INT, INT, TEXT[]) TO authenticated, service_role;


-- 2. ADMIN UPDATE MEMBER MEMBERSHIP & FINANCIALS
CREATE OR REPLACE FUNCTION public.admin_update_member_membership_and_finance(
    p_member_id UUID,
    p_plan_id TEXT,
    p_start_date DATE,
    p_end_date DATE,
    p_total NUMERIC,
    p_paid NUMERIC,
    p_pending NUMERIC,
    p_discount NUMERIC,
    p_status TEXT
)
RETURNS JSONB AS $$
DECLARE
    v_gym_id UUID;
    v_membership_id UUID;
    v_pay_status TEXT;
BEGIN
    SELECT gym_id INTO v_gym_id FROM public.members WHERE id = p_member_id;
    IF v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Member not found');
    END IF;

    -- Determine payment status
    IF p_pending <= 0 AND p_paid > 0 THEN
        v_pay_status := 'Paid';
    ELSIF p_paid > 0 AND p_pending > 0 THEN
        v_pay_status := 'Partial';
    ELSE
        v_pay_status := 'Pending';
    END IF;

    -- 1. Update members table
    UPDATE public.members
    SET membership_plan_id = p_plan_id,
        total_received_amount = p_paid,
        pending_amount = p_pending,
        discount_amount = p_discount,
        payment_status = v_pay_status,
        status = p_status
    WHERE id = p_member_id;

    -- 2. Update or insert into member_memberships
    SELECT id INTO v_membership_id
    FROM public.member_memberships
    WHERE member_id = p_member_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_membership_id IS NOT NULL THEN
        UPDATE public.member_memberships
        SET plan_id = p_plan_id,
            start_date = p_start_date,
            end_date = p_end_date,
            total_amount = p_total,
            paid_amount = p_paid,
            pending_amount = p_pending,
            payment_status = v_pay_status,
            updated_at = now()
        WHERE id = v_membership_id;
    ELSE
        INSERT INTO public.member_memberships (
            gym_id, member_id, plan_id, start_date, end_date, total_amount, paid_amount, pending_amount, payment_status, created_at, updated_at
        ) VALUES (
            v_gym_id, p_member_id, p_plan_id, p_start_date, p_end_date, p_total, p_paid, p_pending, v_pay_status, now(), now()
        );
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'member_id', p_member_id,
        'payment_status', v_pay_status,
        'start_date', p_start_date,
        'end_date', p_end_date
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.admin_update_member_membership_and_finance(UUID, TEXT, DATE, DATE, NUMERIC, NUMERIC, NUMERIC, NUMERIC, TEXT) TO authenticated, service_role;


-- 3. ADMIN UPSERT ATTENDANCE (MEMBER OR STAFF)
CREATE OR REPLACE FUNCTION public.admin_upsert_attendance(
    p_gym_id UUID,
    p_user_type TEXT,
    p_target_id UUID,
    p_date DATE,
    p_status TEXT,
    p_check_in TIMESTAMPTZ,
    p_check_out TIMESTAMPTZ,
    p_log_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID;
    v_name TEXT;
    v_work_hours NUMERIC := 0;
    v_final_id UUID := p_log_id;
BEGIN
    IF p_user_type = 'Member' THEN
        SELECT user_id, name INTO v_user_id, v_name FROM public.members WHERE id = p_target_id;
    ELSE
        SELECT user_id, name INTO v_user_id, v_name FROM public.staff WHERE id = p_target_id;
    END IF;

    IF v_name IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Target record not found');
    END IF;

    IF p_check_in IS NOT NULL AND p_check_out IS NOT NULL THEN
        v_work_hours := ROUND((EXTRACT(EPOCH FROM (p_check_out - p_check_in)) / 3600.0)::NUMERIC, 2);
    END IF;

    IF v_final_id IS NOT NULL THEN
        UPDATE public.attendance_logs
        SET status = p_status,
            check_in = p_check_in,
            check_out = p_check_out,
            working_hours = v_work_hours,
            date = p_date::text,
            updated_at = now()
        WHERE id = v_final_id;
    ELSE
        -- Insert new record
        INSERT INTO public.attendance_logs (
            gym_id,
            user_id,
            user_type,
            member_id,
            staff_id,
            name,
            date,
            status,
            check_in,
            check_out,
            working_hours,
            method,
            created_at,
            updated_at
        ) VALUES (
            p_gym_id,
            v_user_id,
            p_user_type,
            CASE WHEN p_user_type = 'Member' THEN p_target_id ELSE NULL END,
            CASE WHEN p_user_type = 'Staff' THEN p_target_id ELSE NULL END,
            v_name,
            p_date::text,
            p_status,
            p_check_in,
            p_check_out,
            v_work_hours,
            'Admin Override',
            now(),
            now()
        )
        RETURNING id INTO v_final_id;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'log_id', v_final_id,
        'user_type', p_user_type,
        'date', p_date,
        'status', p_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.admin_upsert_attendance(UUID, TEXT, UUID, DATE, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, UUID) TO authenticated, service_role;


-- 4. ADMIN DELETE ATTENDANCE LOG
CREATE OR REPLACE FUNCTION public.admin_delete_attendance(p_log_id UUID)
RETURNS JSONB AS $$
BEGIN
    DELETE FROM public.attendance_logs WHERE id = p_log_id;
    RETURN jsonb_build_object('success', true, 'deleted_id', p_log_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.admin_delete_attendance(UUID) TO authenticated, service_role;


-- 5. ADMIN DIAGNOSE GYM HEALTH ("KYA SCENE HAI" ERROR INSPECTOR)
CREATE OR REPLACE FUNCTION public.admin_diagnose_gym_health(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_issues JSONB := '[]'::JSONB;
    v_rec RECORD;
BEGIN
    -- 1. Expired Members marked Active
    FOR v_rec IN 
        SELECT m.id, m.name, m.status, mm.end_date
        FROM public.members m
        JOIN public.member_memberships mm ON mm.member_id = m.id
        WHERE m.gym_id = p_gym_id 
          AND m.status = 'Active' 
          AND mm.end_date < CURRENT_DATE
    LOOP
        v_issues := v_issues || jsonb_build_object(
            'category', 'membership_expired',
            'severity', 'warning',
            'target_id', v_rec.id,
            'name', v_rec.name,
            'description', format('Membership expired on %s, but status is still marked "Active".', v_rec.end_date),
            'action_type', 'mark_expired'
        );
    END LOOP;

    -- 2. Members with Unlinked / Null User ID (Mobile App Login Blocked)
    FOR v_rec IN 
        SELECT id, name, phone, email
        FROM public.members
        WHERE gym_id = p_gym_id AND (user_id IS NULL OR user_id = '00000000-0000-0000-0000-000000000000'::UUID)
    LOOP
        v_issues := v_issues || jsonb_build_object(
            'category', 'unlinked_user_account',
            'severity', 'info',
            'target_id', v_rec.id,
            'name', v_rec.name,
            'description', format('Member has not logged into the GymOS mobile app yet (user_id unlinked, Phone: %s).', v_rec.phone),
            'action_type', 'none'
        );
    END LOOP;

    -- 3. Members with Missing Gamification Records
    FOR v_rec IN 
        SELECT m.id, m.name
        FROM public.members m
        LEFT JOIN public.member_achievements ma ON ma.member_id = m.id
        WHERE m.gym_id = p_gym_id AND ma.id IS NULL
    LOOP
        v_issues := v_issues || jsonb_build_object(
            'category', 'missing_gamification',
            'severity', 'warning',
            'target_id', v_rec.id,
            'name', v_rec.name,
            'description', 'Member has no gamification/badge profile initialized in database.',
            'action_type', 'initialize_gamification'
        );
    END LOOP;

    -- 4. Date Inversion (Start Date > End Date)
    FOR v_rec IN 
        SELECT m.id, m.name, mm.start_date, mm.end_date
        FROM public.members m
        JOIN public.member_memberships mm ON mm.member_id = m.id
        WHERE m.gym_id = p_gym_id AND mm.start_date > mm.end_date
    LOOP
        v_issues := v_issues || jsonb_build_object(
            'category', 'invalid_dates',
            'severity', 'danger',
            'target_id', v_rec.id,
            'name', v_rec.name,
            'description', format('Invalid dates: Start date (%s) is after End date (%s).', v_rec.start_date, v_rec.end_date),
            'action_type', 'fix_date_inversion'
        );
    END LOOP;

    -- 5. Staff with Null User ID
    FOR v_rec IN 
        SELECT id, name, role, phone
        FROM public.staff
        WHERE gym_id = p_gym_id AND (user_id IS NULL OR user_id = '00000000-0000-0000-0000-000000000000'::UUID)
    LOOP
        v_issues := v_issues || jsonb_build_object(
            'category', 'unlinked_staff_account',
            'severity', 'info',
            'target_id', v_rec.id,
            'name', v_rec.name,
            'description', format('Staff "%s" (%s) has no mobile login account linked.', v_rec.name, v_rec.role),
            'action_type', 'none'
        );
    END LOOP;

    RETURN jsonb_build_object(
        'gym_id', p_gym_id,
        'scanned_at', now(),
        'total_issues', jsonb_array_length(v_issues),
        'issues', v_issues
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.admin_diagnose_gym_health(UUID) TO authenticated, service_role;


-- 6. ADMIN AUTO REPAIR ANOMALY
CREATE OR REPLACE FUNCTION public.admin_auto_repair_anomaly(
    p_gym_id UUID,
    p_action_type TEXT,
    p_target_id UUID
)
RETURNS JSONB AS $$
BEGIN
    IF p_action_type = 'mark_expired' THEN
        UPDATE public.members SET status = 'Expired' WHERE id = p_target_id AND gym_id = p_gym_id;
        RETURN jsonb_build_object('success', true, 'message', 'Status updated to Expired');

    ELSIF p_action_type = 'initialize_gamification' THEN
        INSERT INTO public.member_achievements (member_id) VALUES (p_target_id) ON CONFLICT DO NOTHING;
        PERFORM public.initialize_member_badges(p_target_id);
        RETURN jsonb_build_object('success', true, 'message', 'Gamification profile and badges initialized');

    ELSIF p_action_type = 'fix_date_inversion' THEN
        -- Swap start_date and end_date if inverted
        UPDATE public.member_memberships
        SET start_date = end_date,
            end_date = start_date,
            updated_at = now()
        WHERE member_id = p_target_id AND gym_id = p_gym_id AND start_date > end_date;
        RETURN jsonb_build_object('success', true, 'message', 'Start and End dates corrected');

    ELSE
        RETURN jsonb_build_object('success', false, 'error', 'Unknown repair action');
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.admin_auto_repair_anomaly(UUID, TEXT, UUID) TO authenticated, service_role;
