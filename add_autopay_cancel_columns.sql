-- GYMOS: ADD AUTOPAY CANCEL COLUMNS TO SUBSCRIPTIONS TABLE
ALTER TABLE IF EXISTS public.subscriptions 
ADD COLUMN IF NOT EXISTS auto_pay BOOLEAN DEFAULT true,
ADD COLUMN IF NOT EXISTS cancel_at_period_end BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS auto_pay_cancelled_at TIMESTAMPTZ;

-- Ensure RLS allows owner to update their subscription cancel status
DROP POLICY IF EXISTS "Owners can update their subscription cancel status" ON public.subscriptions;
CREATE POLICY "Owners can update their subscription cancel status" ON public.subscriptions
FOR UPDATE
USING (
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() AND role = 'owner'
    )
)
WITH CHECK (
    gym_id IN (
        SELECT gym_id FROM public.user_gym_associations 
        WHERE user_id = auth.uid() AND role = 'owner'
    )
);
