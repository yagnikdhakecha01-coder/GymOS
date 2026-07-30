-- =========================================================================
-- GYMOS MEMBER GAMIFICATION SYSTEM SETUP
-- RUN THIS IN SUPABASE SQL EDITOR TO APPLY ALL SCHEMAS & TRIGGERS
-- =========================================================================

-- 1. CLEAN UP PREVIOUS VERSIONS
DROP TRIGGER IF EXISTS trg_attendance_gamification ON public.attendance_logs;
DROP FUNCTION IF EXISTS public.trg_attendance_gamification();
DROP FUNCTION IF EXISTS public.get_xp_required_for_level(INT);
DROP FUNCTION IF EXISTS public.get_title_for_level(INT, BOOLEAN, BOOLEAN, BOOLEAN);
DROP FUNCTION IF EXISTS public.award_member_xp(UUID, INT, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.initialize_member_badges(UUID);
DROP FUNCTION IF EXISTS public.update_member_badge_progress(UUID, TEXT, INT);
DROP FUNCTION IF EXISTS public.get_member_gamification_profile(UUID);

-- 2. CREATE SCHEMAS

-- Table: public.member_achievements
CREATE TABLE IF NOT EXISTS public.member_achievements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID REFERENCES public.members(id) ON DELETE CASCADE UNIQUE NOT NULL,
    current_xp INT DEFAULT 0 NOT NULL CHECK (current_xp >= 0),
    current_level INT DEFAULT 1 NOT NULL CHECK (current_level >= 1 AND current_level <= 99),
    current_title TEXT DEFAULT '🌱 New Member' NOT NULL,
    total_attendance INT DEFAULT 0 NOT NULL,
    consecutive_attendance INT DEFAULT 0 NOT NULL,
    weekend_attendance INT DEFAULT 0 NOT NULL,
    early_bird_attendance INT DEFAULT 0 NOT NULL,
    monthly_goals_completed INT DEFAULT 0 NOT NULL,
    last_attendance_date DATE,
    never_miss_streak INT DEFAULT 0 NOT NULL,
    last_streak INT DEFAULT 0 NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Table: public.member_badge_status
CREATE TABLE IF NOT EXISTS public.member_badge_status (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID REFERENCES public.members(id) ON DELETE CASCADE NOT NULL,
    badge_key TEXT NOT NULL,
    is_unlocked BOOLEAN DEFAULT FALSE NOT NULL,
    unlocked_at TIMESTAMPTZ,
    current_progress INT DEFAULT 0 NOT NULL,
    target_value INT DEFAULT 1 NOT NULL,
    xp_reward INT DEFAULT 100 NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    UNIQUE(member_id, badge_key)
);

-- Table: public.xp_history
CREATE TABLE IF NOT EXISTS public.xp_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID REFERENCES public.members(id) ON DELETE CASCADE NOT NULL,
    xp_change INT NOT NULL,
    source TEXT NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_member_achievements_member ON public.member_achievements(member_id);
CREATE INDEX IF NOT EXISTS idx_member_badge_status_lookup ON public.member_badge_status(member_id, badge_key);
CREATE INDEX IF NOT EXISTS idx_xp_history_lookup ON public.xp_history(member_id);

-- 3. UTILITY FUNCTIONS

-- Calculate required XP smoothly: floor(100 * power(level, 1.25))
CREATE OR REPLACE FUNCTION public.get_xp_required_for_level(p_level INT)
RETURNS INT AS $$
BEGIN
    RETURN floor(100 * power(p_level, 1.25))::INT;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Milestone titles solver
CREATE OR REPLACE FUNCTION public.get_title_for_level(
    p_level INT,
    p_all_badges_unlocked BOOLEAN,
    p_never_miss_unlocked BOOLEAN,
    p_365_unlocked BOOLEAN
)
RETURNS TEXT AS $$
BEGIN
    IF p_level >= 99 THEN
        IF p_all_badges_unlocked AND p_never_miss_unlocked AND p_365_unlocked THEN
            RETURN '👑 Immortal Titan';
        ELSE
            RETURN '🌟 Hall of Fame';
        END IF;
    ELSIF p_level >= 90 THEN RETURN '🌟 Hall of Fame';
    ELSIF p_level >= 80 THEN RETURN '⚔️ Ultimate Warrior';
    ELSIF p_level >= 70 THEN RETURN '💎 Fitness Legend';
    ELSIF p_level >= 60 THEN RETURN '👑 Gym Champion';
    ELSIF p_level >= 50 THEN RETURN '🏆 Elite Performer';
    ELSIF p_level >= 40 THEN RETURN '🛡️ Discipline Master';
    ELSIF p_level >= 30 THEN RETURN '⚡ Iron Athlete';
    ELSIF p_level >= 20 THEN RETURN '🔥 Fit Warrior';
    ELSIF p_level >= 10 THEN RETURN '💪 Fitness Explorer';
    ELSIF p_level >= 5 THEN  RETURN '🏃 Regular';
    ELSE RETURN '🌱 New Member';
    END IF;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- XP Awarder & Level-up Engine
CREATE OR REPLACE FUNCTION public.award_member_xp(
    p_member_id UUID,
    p_xp_change INT,
    p_source TEXT,
    p_desc TEXT
)
RETURNS VOID AS $$
DECLARE
    v_ach RECORD;
    v_req_xp INT;
    v_unlocked_all BOOLEAN;
    v_never_miss_unlocked BOOLEAN;
    v_365_unlocked BOOLEAN;
    v_new_level INT;
    v_new_xp INT;
    v_new_title TEXT;
BEGIN
    -- Ensure row exists
    INSERT INTO public.member_achievements (member_id)
    VALUES (p_member_id)
    ON CONFLICT (member_id) DO NOTHING;

    -- Fetch status
    SELECT * INTO v_ach FROM public.member_achievements WHERE member_id = p_member_id;

    -- Compute new XP
    v_new_xp := GREATEST(0, v_ach.current_xp + p_xp_change);
    v_new_level := v_ach.current_level;

    -- Log to history
    INSERT INTO public.xp_history (member_id, xp_change, source, description)
    VALUES (p_member_id, p_xp_change, p_source, p_desc);

    -- Level-up loop
    LOOP
        IF v_new_level >= 99 THEN
            v_new_level := 99;
            EXIT;
        END IF;

        v_req_xp := public.get_xp_required_for_level(v_new_level);
        IF v_new_xp >= v_req_xp THEN
            v_new_xp := v_new_xp - v_req_xp;
            v_new_level := v_new_level + 1;
        ELSE
            EXIT;
        END IF;
    END LOOP;

    -- Evaluate milestone qualifications
    IF v_new_level = 99 THEN
        SELECT 
            COALESCE(bool_and(is_unlocked) FILTER (WHERE badge_key NOT IN ('gymos_legend')), FALSE),
            COALESCE(bool_and(is_unlocked) FILTER (WHERE badge_key = 'never_miss_gym'), FALSE),
            COALESCE(bool_and(is_unlocked) FILTER (WHERE badge_key = 'club_365'), FALSE)
        INTO v_unlocked_all, v_never_miss_unlocked, v_365_unlocked
        FROM public.member_badge_status
        WHERE member_id = p_member_id;
    ELSE
        v_unlocked_all := FALSE;
        v_never_miss_unlocked := FALSE;
        v_365_unlocked := FALSE;
    END IF;

    v_new_title := public.get_title_for_level(v_new_level, v_unlocked_all, v_never_miss_unlocked, v_365_unlocked);

    -- Update database record
    UPDATE public.member_achievements
    SET current_xp = v_new_xp,
        current_level = v_new_level,
        current_title = v_new_title,
        updated_at = now()
    WHERE member_id = p_member_id;
END;
$$ LANGUAGE plpgsql;

-- Badge Initializer
CREATE OR REPLACE FUNCTION public.initialize_member_badges(p_member_id UUID)
RETURNS VOID AS $$
BEGIN
    INSERT INTO public.member_badge_status (member_id, badge_key, target_value, xp_reward) VALUES
    (p_member_id, 'first_step', 1, 100),
    (p_member_id, 'week_warrior', 7, 100),
    (p_member_id, 'perfect_month', 30, 100),
    (p_member_id, 'century_club', 100, 100),
    (p_member_id, 'club_365', 365, 500),
    (p_member_id, 'early_bird', 20, 100),
    (p_member_id, 'weekend_warrior', 25, 100),
    (p_member_id, 'monthly_machine', 3, 100),
    (p_member_id, 'half_year_hero', 180, 100),
    (p_member_id, 'loyal_member', 365, 100),
    (p_member_id, 'attendance_master', 500, 200),
    (p_member_id, 'rising_star', 25, 100),
    (p_member_id, 'elite_member', 50, 100),
    (p_member_id, 'never_miss_gym', 365, 500),
    (p_member_id, 'gymos_legend', 1, 1000)
    ON CONFLICT (member_id, badge_key) DO NOTHING;
END;
$$ LANGUAGE plpgsql;

-- Badge Progress Engine
CREATE OR REPLACE FUNCTION public.update_member_badge_progress(
    p_member_id UUID,
    p_badge_key TEXT,
    p_progress INT
)
RETURNS VOID AS $$
DECLARE
    v_badge RECORD;
    v_new_progress INT;
BEGIN
    SELECT * INTO v_badge 
    FROM public.member_badge_status 
    WHERE member_id = p_member_id AND badge_key = p_badge_key;

    IF v_badge IS NULL THEN
        RETURN;
    END IF;

    v_new_progress := LEAST(v_badge.target_value, p_progress);

    IF v_new_progress >= v_badge.target_value AND NOT v_badge.is_unlocked THEN
        -- Unlock Badge!
        UPDATE public.member_badge_status
        SET current_progress = v_new_progress,
            is_unlocked = TRUE,
            unlocked_at = now(),
            updated_at = now()
        WHERE member_id = p_member_id AND badge_key = p_badge_key;

        -- Award Badge XP
        PERFORM public.award_member_xp(
            p_member_id, 
            v_badge.xp_reward, 
            'Badge Unlock', 
            'Unlocked Badge: ' || p_badge_key
        );
    ELSE
        UPDATE public.member_badge_status
        SET current_progress = v_new_progress,
            updated_at = now()
        WHERE member_id = p_member_id AND badge_key = p_badge_key;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- 4. ATTENDANCE LOG TRIGGER (SECURE PROCESSOR)
CREATE OR REPLACE FUNCTION public.trg_attendance_gamification()
RETURNS TRIGGER AS $$
DECLARE
    v_member_id UUID := NEW.member_id;
    v_local_now TIMESTAMPTZ := NEW.check_in AT TIME ZONE 'Asia/Kolkata';
    v_local_time TIME := v_local_now::TIME;
    v_is_weekend BOOLEAN := EXTRACT(ISODOW FROM v_local_now) IN (6, 7);
    v_local_date DATE := v_local_now::DATE;
    
    v_ach RECORD;
    v_consec_att INT := 0;
    v_never_miss_streak INT := 0;
    
    v_week_count INT := 0;
    v_already_weekly BOOLEAN := FALSE;
    
    v_month_count INT := 0;
    v_already_monthly BOOLEAN := FALSE;
    
    v_join_date_str TEXT;
    v_days_active INT := 0;
    v_unlocked_badges_count INT := 0;
BEGIN
    -- Only process members
    IF NEW.user_type <> 'Member' OR v_member_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Ensure member has initialized status and badges
    INSERT INTO public.member_achievements (member_id)
    VALUES (v_member_id)
    ON CONFLICT (member_id) DO NOTHING;

    PERFORM public.initialize_member_badges(v_member_id);

    -- Fetch current achievement status
    SELECT * INTO v_ach FROM public.member_achievements WHERE member_id = v_member_id;

    -- 4.1 PENALTY IF MARKED ABSENT
    IF NEW.status = 'Absent' THEN
        -- Deduct half of Present award (-5 XP)
        PERFORM public.award_member_xp(v_member_id, -5, 'Absent Penalty', 'Missed check-in on expected day');
        
        -- Reset streaks to 0, saving current streak to last_streak
        UPDATE public.member_achievements
        SET last_streak = CASE WHEN consecutive_attendance > 0 THEN consecutive_attendance ELSE last_streak END,
            consecutive_attendance = 0,
            never_miss_streak = 0,
            updated_at = now()
        WHERE member_id = v_member_id;

        -- Update streak badge progress to 0
        PERFORM public.update_member_badge_progress(v_member_id, 'week_warrior', 0);
        PERFORM public.update_member_badge_progress(v_member_id, 'perfect_month', 0);
        PERFORM public.update_member_badge_progress(v_member_id, 'never_miss_gym', 0);

        RETURN NEW;
    END IF;

    -- 4.2 PRESENT FLOW
    IF NEW.status IN ('Present', 'Late', 'Early Exit', 'Overtime') THEN
        -- Award check-in XP (+10 XP)
        PERFORM public.award_member_xp(v_member_id, 10, 'Daily Attendance', 'Attendance check-in for ' || to_char(v_local_now, 'dd-MM-yyyy'));

        -- Calculate Streak Metrics (consecutive days excluding Sundays)
        IF v_ach.last_attendance_date IS NOT NULL THEN
            IF v_local_date = v_ach.last_attendance_date THEN
                -- Same day multiple checks: ignore streak change
                v_consec_att := v_ach.consecutive_attendance;
                v_never_miss_streak := v_ach.never_miss_streak;
            ELSIF v_local_date - v_ach.last_attendance_date = 1 OR 
                  (EXTRACT(ISODOW FROM v_local_date) = 1 AND v_local_date - v_ach.last_attendance_date = 2) THEN
                -- Consecutive day check
                v_consec_att := v_ach.consecutive_attendance + 1;
                v_never_miss_streak := v_ach.never_miss_streak + 1;
            ELSE
                -- Streak Broken
                UPDATE public.member_achievements
                SET last_streak = CASE WHEN consecutive_attendance > 0 THEN consecutive_attendance ELSE last_streak END
                WHERE member_id = v_member_id;

                v_consec_att := 1;
                v_never_miss_streak := 1;
            END IF;
        ELSE
            -- First Attendance
            v_consec_att := 1;
            v_never_miss_streak := 1;
        END IF;

        -- Update achievements metrics
        UPDATE public.member_achievements
        SET total_attendance = total_attendance + 1,
            weekend_attendance = weekend_attendance + CASE WHEN v_is_weekend THEN 1 ELSE 0 END,
            early_bird_attendance = early_bird_attendance + CASE WHEN v_local_time < '07:00:00'::TIME THEN 1 ELSE 0 END,
            consecutive_attendance = v_consec_att,
            never_miss_streak = v_never_miss_streak,
            last_attendance_date = v_local_date,
            updated_at = now()
        WHERE member_id = v_member_id;

        -- 4.3 CHECK WEEKLY ATTENDANCE GOAL (+50 XP)
        -- Count unique check-in days this calendar week
        SELECT COUNT(DISTINCT (check_in AT TIME ZONE 'Asia/Kolkata')::DATE) INTO v_week_count
        FROM public.attendance_logs
        WHERE member_id = v_member_id
          AND check_in >= date_trunc('week', NEW.check_in AT TIME ZONE 'Asia/Kolkata')
          AND status IN ('Present', 'Late', 'Early Exit', 'Overtime');

        IF v_week_count = 5 THEN
            -- Check if already awarded this week
            SELECT EXISTS (
                SELECT 1 FROM public.xp_history
                WHERE member_id = v_member_id
                  AND source = 'Weekly Goal'
                  AND created_at >= date_trunc('week', NEW.check_in AT TIME ZONE 'Asia/Kolkata')
            ) INTO v_already_weekly;

            IF NOT v_already_weekly THEN
                PERFORM public.award_member_xp(v_member_id, 50, 'Weekly Goal', 'Completed 5 attendances this week');
            END IF;
        END IF;

        -- 4.4 CHECK MONTHLY ATTENDANCE GOAL (+150 XP)
        -- Count unique check-in days this calendar month
        SELECT COUNT(DISTINCT (check_in AT TIME ZONE 'Asia/Kolkata')::DATE) INTO v_month_count
        FROM public.attendance_logs
        WHERE member_id = v_member_id
          AND check_in >= date_trunc('month', NEW.check_in AT TIME ZONE 'Asia/Kolkata')
          AND status IN ('Present', 'Late', 'Early Exit', 'Overtime');

        IF v_month_count = 20 THEN
            SELECT EXISTS (
                SELECT 1 FROM public.xp_history
                WHERE member_id = v_member_id
                  AND source = 'Monthly Goal'
                  AND created_at >= date_trunc('month', NEW.check_in AT TIME ZONE 'Asia/Kolkata')
            ) INTO v_already_monthly;

            IF NOT v_already_monthly THEN
                PERFORM public.award_member_xp(v_member_id, 150, 'Monthly Goal', 'Completed 20 attendances this month');
                
                -- Increment monthly goals completed in achievements
                UPDATE public.member_achievements
                SET monthly_goals_completed = monthly_goals_completed + 1
                WHERE member_id = v_member_id;
            END IF;
        END IF;

        -- 4.5 EVALUATE & UPDATE BADGES
        -- Reload updated achievements values
        SELECT * INTO v_ach FROM public.member_achievements WHERE member_id = v_member_id;

        -- Badge 1: First Step
        PERFORM public.update_member_badge_progress(v_member_id, 'first_step', 1);

        -- Badge 2: Week Warrior
        PERFORM public.update_member_badge_progress(v_member_id, 'week_warrior', v_ach.consecutive_attendance);

        -- Badge 3: Perfect Month
        PERFORM public.update_member_badge_progress(v_member_id, 'perfect_month', v_ach.consecutive_attendance);

        -- Badge 4: Century Club
        PERFORM public.update_member_badge_progress(v_member_id, 'century_club', v_ach.total_attendance);

        -- Badge 5: 365 Club
        PERFORM public.update_member_badge_progress(v_member_id, 'club_365', v_ach.total_attendance);

        -- Badge 6: Early Bird
        PERFORM public.update_member_badge_progress(v_member_id, 'early_bird', v_ach.early_bird_attendance);

        -- Badge 7: Weekend Warrior
        PERFORM public.update_member_badge_progress(v_member_id, 'weekend_warrior', v_ach.weekend_attendance);

        -- Badge 8: Monthly Machine
        PERFORM public.update_member_badge_progress(v_member_id, 'monthly_machine', v_ach.monthly_goals_completed);

        -- Badge 9: Half-Year Hero
        PERFORM public.update_member_badge_progress(v_member_id, 'half_year_hero', v_ach.total_attendance);

        -- Badge 10: Loyal Member
        SELECT join_date INTO v_join_date_str FROM public.members WHERE id = v_member_id;
        IF v_join_date_str IS NOT NULL AND v_join_date_str <> '' THEN
            BEGIN
                v_days_active := (now()::DATE - to_date(v_join_date_str, 'dd-MM-yyyy'));
                IF v_days_active < 0 THEN v_days_active := 0; END IF;
            EXCEPTION WHEN OTHERS THEN
                v_days_active := 0;
            END;
        END IF;
        PERFORM public.update_member_badge_progress(v_member_id, 'loyal_member', v_days_active);

        -- Badge 11: Attendance Master
        PERFORM public.update_member_badge_progress(v_member_id, 'attendance_master', v_ach.total_attendance);

        -- Badge 12: Rising Star
        PERFORM public.update_member_badge_progress(v_member_id, 'rising_star', v_ach.current_level);

        -- Badge 13: Elite Member
        PERFORM public.update_member_badge_progress(v_member_id, 'elite_member', v_ach.current_level);

        -- Badge 14: Never Miss Gym
        PERFORM public.update_member_badge_progress(v_member_id, 'never_miss_gym', v_ach.never_miss_streak);

        -- Badge 15: GymOS Legend
        SELECT COUNT(*) INTO v_unlocked_badges_count
        FROM public.member_badge_status
        WHERE member_id = v_member_id AND is_unlocked = TRUE AND badge_key <> 'gymos_legend';

        IF v_unlocked_badges_count = 14 AND v_ach.current_level = 99 THEN
            PERFORM public.update_member_badge_progress(v_member_id, 'gymos_legend', 1);
        END IF;
        
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Hook Trigger onto attendance_logs table
CREATE TRIGGER trg_attendance_gamification
AFTER INSERT OR UPDATE ON public.attendance_logs
FOR EACH ROW
EXECUTE FUNCTION public.trg_attendance_gamification();


-- 5. RPC FUNCTION: get_member_gamification_profile
-- Securely returns current level stats and complete list of all 15 badges
CREATE OR REPLACE FUNCTION public.get_member_gamification_profile(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_member_id UUID;
    v_ach RECORD;
    v_req_xp INT;
    v_badges JSONB;
BEGIN
    -- Resolve member ID
    SELECT id INTO v_member_id FROM public.members WHERE user_id = p_user_id LIMIT 1;
    
    IF v_member_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Ensure record exists
    INSERT INTO public.member_achievements (member_id)
    VALUES (v_member_id)
    ON CONFLICT (member_id) DO NOTHING;

    PERFORM public.initialize_member_badges(v_member_id);

    -- Load achievements row
    SELECT * INTO v_ach FROM public.member_achievements WHERE member_id = v_member_id;
    v_req_xp := public.get_xp_required_for_level(v_ach.current_level);

    -- Load all badges
    SELECT jsonb_agg(
        jsonb_build_object(
            'key', badge_key,
            'is_unlocked', is_unlocked,
            'unlocked_at', unlocked_at,
            'current_progress', current_progress,
            'target_value', target_value,
            'xp_reward', xp_reward
        )
    ) INTO v_badges
    FROM public.member_badge_status
    WHERE member_id = v_member_id;

    RETURN jsonb_build_object(
        'current_level', v_ach.current_level,
        'current_title', v_ach.current_title,
        'current_xp', v_ach.current_xp,
        'required_xp', v_req_xp,
        'total_attendance', v_ach.total_attendance,
        'consecutive_attendance', v_ach.consecutive_attendance,
        'weekend_attendance', v_ach.weekend_attendance,
        'early_bird_attendance', v_ach.early_bird_attendance,
        'badges', v_badges
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.get_member_gamification_profile(UUID) TO anon, authenticated, service_role;
