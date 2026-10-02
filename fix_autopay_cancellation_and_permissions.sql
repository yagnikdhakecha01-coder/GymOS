-- =========================================================================
-- FIX AUTOPAY CANCELLATION RPC, PERMISSIONS & SUBSCRIPTION HISTORY SCHEMA
-- =========================================================================

-- 1. Grant table-level permissions to authenticated role
GRANT SELECT, UPDATE ON public.subscriptions TO authenticated;
GRANT SELECT, INSERT ON public.subscription_history TO authenticated;

-- 2. Ensure RLS policies allow owners to update their own subscription
DROP POLICY IF EXISTS "Owners can update their subscription cancel status" ON public.subscriptions;
CREATE POLICY "Owners can update their subscription cancel status" ON public.subscriptions
FOR UPDATE
TO authenticated
USING (
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() AND role = 'owner'
    )
    OR
    owner_id = auth.uid()
)
WITH CHECK (
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() AND role = 'owner'
    )
    OR
    owner_id = auth.uid()
);

-- Allow authenticated owners to insert their subscription history
DROP POLICY IF EXISTS "Owners can insert subscription history" ON public.subscription_history;
CREATE POLICY "Owners can insert subscription history" ON public.subscription_history
FOR INSERT
TO authenticated
WITH CHECK (
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() AND role = 'owner'
    )
    OR
    changed_by = auth.uid()
);

-- 3. Replace cancel_autopay_subscription RPC with accurate schema columns
CREATE OR REPLACE FUNCTION public.cancel_autopay_subscription(p_gym_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_sub RECORD;
BEGIN
    -- Locate existing subscription
    SELECT * INTO v_sub FROM public.subscriptions WHERE gym_id = p_gym_id;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'message', 'Subscription record not found');
    END IF;

    -- Update subscription status
    UPDATE public.subscriptions
    SET 
        auto_pay = false,
        cancel_at_period_end = true,
        auto_pay_cancelled_at = now(),
        updated_at = now()
    WHERE gym_id = p_gym_id;

    -- Record audit log in subscription_history using exact existing columns
    INSERT INTO public.subscription_history (
        gym_id,
        old_plan_id,
        new_plan_id,
        action,
        changed_by,
        notes,
        created_at
    )
    VALUES (
        p_gym_id,
        v_sub.plan_id,
        v_sub.plan_id,
        'Subscription Cancelled',
        COALESCE(auth.uid(), v_sub.owner_id),
        'AutoPay cancelled by gym owner. Plan remains active until period end.',
        now()
    );

    RETURN jsonb_build_object('success', true, 'message', 'AutoPay cancelled successfully');
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'message', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION public.cancel_autopay_subscription(UUID) TO authenticated, service_role, anon;
