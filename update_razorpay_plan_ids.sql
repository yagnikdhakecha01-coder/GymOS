-- ============================================================================
-- GYMOS BACKEND MIGRATION - UPDATE RAZORPAY PLAN IDS
-- ============================================================================

-- 1. Ensure razorpay_plan_id column exists in platform_plans
ALTER TABLE public.platform_plans 
  ADD COLUMN IF NOT EXISTS razorpay_plan_id VARCHAR(100);

-- 2. Ensure razorpay_plan_id column exists in subscription_plans
ALTER TABLE public.subscription_plans 
  ADD COLUMN IF NOT EXISTS razorpay_plan_id VARCHAR(100);

-- 3. Update Starter Plan Razorpay Plan ID (plan_TMW2eKLvuIqViB)
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'platform_plans') THEN
    UPDATE public.platform_plans
    SET razorpay_plan_id = 'plan_TMW2eKLvuIqViB'
    WHERE LOWER(id) = 'starter' OR LOWER(name) LIKE '%starter%';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'subscription_plans') THEN
    UPDATE public.subscription_plans
    SET razorpay_plan_id = 'plan_TMW2eKLvuIqViB'
    WHERE LOWER(id) = 'starter' OR LOWER(name) LIKE '%starter%';
  END IF;
END $$;

-- 4. Update Pro Plan Razorpay Plan ID (plan_TMW3EjESnsxvEq)
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'platform_plans') THEN
    UPDATE public.platform_plans
    SET razorpay_plan_id = 'plan_TMW3EjESnsxvEq'
    WHERE LOWER(id) = 'pro' OR LOWER(name) LIKE '%pro%';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'subscription_plans') THEN
    UPDATE public.subscription_plans
    SET razorpay_plan_id = 'plan_TMW3EjESnsxvEq'
    WHERE LOWER(id) = 'pro' OR LOWER(name) LIKE '%pro%';
  END IF;
END $$;

-- 5. Update Business Plan Razorpay Plan ID (plan_TMW3ZHfWH8vXb4)
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'platform_plans') THEN
    UPDATE public.platform_plans
    SET razorpay_plan_id = 'plan_TMW3ZHfWH8vXb4'
    WHERE LOWER(id) = 'business' OR LOWER(name) LIKE '%business%';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'subscription_plans') THEN
    UPDATE public.subscription_plans
    SET razorpay_plan_id = 'plan_TMW3ZHfWH8vXb4'
    WHERE LOWER(id) = 'business' OR LOWER(name) LIKE '%business%';
  END IF;
END $$;

-- 6. Store in platform_settings if table exists (safely casting value to JSONB)
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'platform_settings') THEN
    INSERT INTO public.platform_settings (key, value, updated_at)
    VALUES 
      ('razorpay_plan_starter', to_jsonb('plan_TMW2eKLvuIqViB'::text), NOW()),
      ('razorpay_plan_pro', to_jsonb('plan_TMW3EjESnsxvEq'::text), NOW()),
      ('razorpay_plan_business', to_jsonb('plan_TMW3ZHfWH8vXb4'::text), NOW())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
  END IF;
END $$;
