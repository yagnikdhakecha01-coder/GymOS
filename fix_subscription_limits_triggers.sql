-- ============================================================================
-- FIX SUBSCRIPTION LIMITS: Treat -1, NULL, and <= 0 as Unlimited
-- ============================================================================

-- 1. Member Limit Trigger Fix
CREATE OR REPLACE FUNCTION public.enforce_gym_member_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_id TEXT;
    v_status TEXT;
    v_max_members INT;
    v_current_members INT;
BEGIN
    -- Get subscription details for the gym
    SELECT plan_id, status INTO v_plan_id, v_status
    FROM public.subscriptions
    WHERE gym_id = NEW.gym_id;
    
    -- If no subscription found, allow or prompt
    IF v_plan_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- If subscription is expired, block additions
    IF v_status IN ('expired', 'cancelled', 'failed_payment') THEN
        RAISE EXCEPTION 'limit_reached:Your subscription status is % and has expired. Please renew or upgrade to add members.', v_status;
    END IF;

    -- Get plan limits
    SELECT max_members INTO v_max_members
    FROM public.subscription_plans
    WHERE id = v_plan_id;

    -- Enforce limits ONLY if max_members is set and > 0 (treating -1, NULL, <= 0 as unlimited)
    IF v_max_members IS NOT NULL AND v_max_members > 0 THEN
        -- Get current members count
        SELECT count(*) INTO v_current_members
        FROM public.members
        WHERE gym_id = NEW.gym_id;

        IF v_current_members >= v_max_members THEN
            RAISE EXCEPTION 'limit_reached:You have reached your % Plan limit (% Members). Upgrade your subscription to continue.', v_plan_id, v_max_members;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 2. Staff Limit Trigger Fix
CREATE OR REPLACE FUNCTION public.enforce_gym_staff_limit()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_id TEXT;
    v_status TEXT;
    v_max_staff INT;
    v_current_staff INT;
BEGIN
    -- Get subscription details for the gym
    SELECT plan_id, status INTO v_plan_id, v_status
    FROM public.subscriptions
    WHERE gym_id = NEW.gym_id;
    
    -- If no subscription found, allow
    IF v_plan_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- If subscription is expired, block additions
    IF v_status IN ('expired', 'cancelled', 'failed_payment') THEN
        RAISE EXCEPTION 'limit_reached:Your subscription status is % and has expired. Please renew or upgrade to add staff.', v_status;
    END IF;

    -- Get plan limits
    SELECT max_staff INTO v_max_staff
    FROM public.subscription_plans
    WHERE id = v_plan_id;

    -- Enforce limits ONLY if max_staff is set and > 0 (treating -1, NULL, <= 0 as unlimited)
    IF v_max_staff IS NOT NULL AND v_max_staff > 0 THEN
        -- Get current staff count
        SELECT count(*) INTO v_current_staff
        FROM public.staff
        WHERE gym_id = NEW.gym_id;

        IF v_current_staff >= v_max_staff THEN
            RAISE EXCEPTION 'limit_reached:You have reached your % Plan limit (% Staff). Upgrade your subscription to continue.', v_plan_id, v_max_staff;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
