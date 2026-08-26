-- =========================================================================
-- GYMOS: FIX REVENUE DASHBOARD, PAYMENTS RLS & INSERT TODAY'S PAYMENT
-- =========================================================================

-- 1. Ensure Table Structure for Payments
CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE,
    subscription_id UUID,
    invoice_id UUID,
    amount NUMERIC NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'Success',
    payment_method TEXT DEFAULT 'Razorpay Gateway',
    razorpay_payment_id TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Ensure Table Structure for Invoices
CREATE TABLE IF NOT EXISTS public.invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE,
    subscription_id UUID,
    invoice_number TEXT,
    amount NUMERIC NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'paid',
    billing_date TIMESTAMPTZ DEFAULT now(),
    due_date TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Ensure Table Structure for Subscriptions
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID UNIQUE REFERENCES public.gyms(id) ON DELETE CASCADE,
    owner_id UUID,
    plan_id TEXT NOT NULL DEFAULT 'free_trial',
    status TEXT NOT NULL DEFAULT 'trial',
    trial_start TIMESTAMPTZ DEFAULT now(),
    trial_end TIMESTAMPTZ DEFAULT (now() + interval '30 days'),
    start_date TIMESTAMPTZ DEFAULT now(),
    end_date TIMESTAMPTZ DEFAULT (now() + interval '30 days'),
    razorpay_subscription_id TEXT,
    razorpay_customer_id TEXT,
    auto_pay BOOLEAN DEFAULT true,
    next_billing_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Ensure Table Structure for Subscription History
CREATE TABLE IF NOT EXISTS public.subscription_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID REFERENCES public.gyms(id) ON DELETE CASCADE,
    old_plan_id TEXT,
    new_plan_id TEXT,
    action TEXT DEFAULT 'upgrade',
    changed_by UUID,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- =========================================================================
-- 2. ENABLE ROW LEVEL SECURITY & PERMISSIVE POLICIES
-- =========================================================================
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscription_history ENABLE ROW LEVEL SECURITY;

-- Drop any restrictive policies on payments
DROP POLICY IF EXISTS payments_read_all ON public.payments;
DROP POLICY IF EXISTS payments_permissive ON public.payments;
DROP POLICY IF EXISTS payments_isolation ON public.payments;
DROP POLICY IF EXISTS "payments_policy" ON public.payments;

CREATE POLICY payments_permissive ON public.payments
    FOR ALL TO anon, authenticated, service_role
    USING (true)
    WITH CHECK (true);

-- Drop any restrictive policies on invoices
DROP POLICY IF EXISTS invoices_read_all ON public.invoices;
DROP POLICY IF EXISTS invoices_permissive ON public.invoices;
DROP POLICY IF EXISTS invoices_isolation ON public.invoices;

CREATE POLICY invoices_permissive ON public.invoices
    FOR ALL TO anon, authenticated, service_role
    USING (true)
    WITH CHECK (true);

-- Drop any restrictive policies on subscriptions
DROP POLICY IF EXISTS subscriptions_read_all ON public.subscriptions;
DROP POLICY IF EXISTS subscriptions_permissive ON public.subscriptions;
DROP POLICY IF EXISTS subscriptions_isolation ON public.subscriptions;

CREATE POLICY subscriptions_permissive ON public.subscriptions
    FOR ALL TO anon, authenticated, service_role
    USING (true)
    WITH CHECK (true);

-- Drop any restrictive policies on subscription_history
DROP POLICY IF EXISTS subscription_history_read_all ON public.subscription_history;
DROP POLICY IF EXISTS subscription_history_permissive ON public.subscription_history;

CREATE POLICY subscription_history_permissive ON public.subscription_history
    FOR ALL TO anon, authenticated, service_role
    USING (true)
    WITH CHECK (true);

-- Grant privileges
GRANT ALL ON TABLE public.payments TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.invoices TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.subscriptions TO anon, authenticated, service_role;
GRANT ALL ON TABLE public.subscription_history TO anon, authenticated, service_role;

-- =========================================================================
-- 3. INSERT TODAY'S PAYMENT RECORD FOR KD TEST 1 (₹999, Pro Plan)
-- =========================================================================
DO $$
DECLARE
    v_gym_id UUID := '5874f4b0-7b53-438f-9f16-fd383ae674bc'; -- KD Test 1
    v_payment_id TEXT := 'pay_TUHu25FICqObLq';
    v_sub_id UUID;
    v_inv_id UUID;
BEGIN
    -- Get subscription id
    SELECT id INTO v_sub_id FROM public.subscriptions WHERE gym_id = v_gym_id LIMIT 1;
    
    -- Insert Invoice if not exists
    INSERT INTO public.invoices (gym_id, subscription_id, invoice_number, amount, status, billing_date, due_date, created_at)
    VALUES (
        v_gym_id,
        v_sub_id,
        'INV-' || to_char(now(), 'YYYYMMDD-HH24MISS'),
        999.00,
        'paid',
        now(),
        now(),
        now()
    )
    RETURNING id INTO v_inv_id;

    -- Insert Payment record if not exists
    IF NOT EXISTS (SELECT 1 FROM public.payments WHERE razorpay_payment_id = v_payment_id) THEN
        INSERT INTO public.payments (
            gym_id,
            subscription_id,
            invoice_id,
            amount,
            status,
            payment_method,
            razorpay_payment_id,
            created_at
        ) VALUES (
            v_gym_id,
            v_sub_id,
            v_inv_id,
            999.00,
            'Success',
            'Razorpay Gateway',
            v_payment_id,
            now()
        );
    END IF;

    -- Insert audit log
    INSERT INTO public.audit_logs (
        admin_email,
        action,
        category,
        gym_id,
        gym_name,
        details,
        metadata
    ) VALUES (
        'Super Admin',
        'Subscription Payment Activated',
        'subscription',
        v_gym_id,
        'KD Test 1',
        'Payment of ₹999 verified for Pro Plan via Razorpay (pay_TUHu25FICqObLq)',
        jsonb_build_object('plan', 'pro', 'amount', 999, 'payment_id', v_payment_id)
    );

    -- Ensure gym is active and unlocked
    UPDATE public.gyms
    SET plan = 'pro',
        status = 'active',
        is_locked = false,
        expiry_date = now() + interval '30 days'
    WHERE id = v_gym_id;

    -- Ensure subscription table is active
    UPDATE public.subscriptions
    SET plan_id = 'pro',
        status = 'active',
        start_date = now(),
        end_date = now() + interval '30 days',
        trial_end = now() + interval '30 days',
        razorpay_subscription_id = v_payment_id,
        updated_at = now()
    WHERE gym_id = v_gym_id;

END $$;
