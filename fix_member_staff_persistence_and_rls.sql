-- Migration: Fix Member & Staff update persistence, triggers, and RLS policies

-- 1. Patch trigger function fn_on_member_plan_changed
-- Avoid foreign key constraint violations when membership_plan_id is empty, invalid, or doesn't exist in membership_plans
CREATE OR REPLACE FUNCTION public.fn_on_member_plan_changed()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_plan_price NUMERIC(12,2);
    v_duration_days INT;
    v_net_total NUMERIC(12,2);
    v_latest_mm_id UUID;
    v_plan_exists BOOLEAN := FALSE;
BEGIN
    IF NEW.membership_plan_id IS NOT NULL AND NEW.membership_plan_id <> '' AND NEW.membership_plan_id <> 'null' THEN
        SELECT 
            TRUE,
            COALESCE(price, 0.0),
            COALESCE(duration_days, COALESCE(duration_months, 1) * 30, 30)::INTEGER
        INTO v_plan_exists, v_plan_price, v_duration_days
        FROM public.membership_plans 
        WHERE id = NEW.membership_plan_id 
        LIMIT 1;

        IF v_plan_exists THEN
            -- True net total is plan price minus discount
            v_net_total := GREATEST(0.0, COALESCE(v_plan_price, 0.0) - COALESCE(NEW.discount_amount, 0.0));

            -- Case 1: Plan changed or new plan assigned
            IF (OLD IS NULL OR NEW.membership_plan_id IS DISTINCT FROM OLD.membership_plan_id) THEN
                INSERT INTO public.member_memberships (
                    gym_id,
                    member_id,
                    plan_id,
                    start_date,
                    end_date,
                    total_amount,
                    paid_amount,
                    payment_status
                )
                VALUES (
                    NEW.gym_id,
                    NEW.id,
                    NEW.membership_plan_id,
                    CURRENT_DATE,
                    CURRENT_DATE + v_duration_days,
                    v_net_total,
                    COALESCE(NEW.total_received_amount, 0.0),
                    CASE 
                        WHEN COALESCE(NEW.total_received_amount, 0.0) >= v_net_total THEN 'Fully Paid'
                        WHEN COALESCE(NEW.total_received_amount, 0.0) > 0 THEN 'Partial'
                        ELSE 'Unpaid'
                    END
                );
            -- Case 2: Discount amount was updated for current plan
            ELSIF (OLD IS NOT NULL AND NEW.discount_amount IS DISTINCT FROM OLD.discount_amount) THEN
                SELECT id INTO v_latest_mm_id
                FROM public.member_memberships
                WHERE member_id = NEW.id
                ORDER BY created_at DESC
                LIMIT 1;

                IF v_latest_mm_id IS NOT NULL THEN
                    UPDATE public.member_memberships
                    SET total_amount = v_net_total,
                        updated_at = NOW()
                    WHERE id = v_latest_mm_id;
                END IF;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$function$;

-- 2. Update RLS policies on members to support Owners, Staff, and Members
DROP POLICY IF EXISTS "member_isolation_policy" ON public.members;
CREATE POLICY "member_isolation_policy" ON public.members
FOR ALL
TO authenticated
USING (
  is_admin(auth.uid()) 
  OR (gym_id IN (SELECT user_gym_associations.gym_id FROM user_gym_associations WHERE user_gym_associations.user_id = auth.uid()))
  OR (gym_id IN (SELECT staff.gym_id FROM staff WHERE staff.user_id = auth.uid()))
  OR (user_id = auth.uid())
)
WITH CHECK (
  is_admin(auth.uid()) 
  OR (gym_id IN (SELECT user_gym_associations.gym_id FROM user_gym_associations WHERE user_gym_associations.user_id = auth.uid()))
  OR (gym_id IN (SELECT staff.gym_id FROM staff WHERE staff.user_id = auth.uid()))
  OR (user_id = auth.uid())
);

-- 3. Update RLS policies on staff to support Owners, Staff, and Super Admins
DROP POLICY IF EXISTS "staff_isolation_policy" ON public.staff;
CREATE POLICY "staff_isolation_policy" ON public.staff
FOR ALL
TO authenticated
USING (
  is_admin(auth.uid()) 
  OR (gym_id IN (SELECT user_gym_associations.gym_id FROM user_gym_associations WHERE user_gym_associations.user_id = auth.uid()))
  OR (gym_id IN (SELECT staff_alias.gym_id FROM staff staff_alias WHERE staff_alias.user_id = auth.uid()))
  OR (user_id = auth.uid())
)
WITH CHECK (
  is_admin(auth.uid()) 
  OR (gym_id IN (SELECT user_gym_associations.gym_id FROM user_gym_associations WHERE user_gym_associations.user_id = auth.uid()))
  OR (gym_id IN (SELECT staff_alias.gym_id FROM staff staff_alias WHERE staff_alias.user_id = auth.uid()))
  OR (user_id = auth.uid())
);
