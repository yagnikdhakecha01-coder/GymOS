-- ============================================================================
-- GYMOS BACKEND MIGRATION - UPDATE STARTER PLAN PRICE FROM 499 TO 699
-- ============================================================================

-- 1. Update platform_plans table price for Starter plan if table exists
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'platform_plans') THEN
    UPDATE public.platform_plans
    SET price = 699.00
    WHERE LOWER(id) = 'starter' OR LOWER(name) LIKE '%starter%';
  END IF;
END $$;

-- 2. Update subscription_plans table price for Starter plan if table exists
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'subscription_plans') THEN
    UPDATE public.subscription_plans
    SET price = 699.00
    WHERE LOWER(id) = 'starter' OR LOWER(name) LIKE '%starter%';
  END IF;
END $$;

-- 3. Update platform_settings table using correct 'key' column and JSONB format
DO $$ 
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'platform_settings') THEN
    UPDATE public.platform_settings
    SET value = to_jsonb('699'::text), updated_at = NOW()
    WHERE key = 'starter_plan_price' OR key = 'plan_starter_price';
  END IF;
END $$;
