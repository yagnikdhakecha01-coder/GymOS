-- =========================================================================
-- FIX UNLINK RLS POLICY: fix_unlink_rls_policy.sql
-- Run this script in your Supabase SQL Editor to allow gym owners
-- to successfully unlink staff and members by deleting user associations.
-- =========================================================================

-- Enable delete policy on user_gym_associations table
DROP POLICY IF EXISTS delete_associations ON public.user_gym_associations;

CREATE POLICY delete_associations ON public.user_gym_associations
    FOR DELETE TO authenticated
    USING (
        user_id = auth.uid()
        OR
        gym_id IN (
            SELECT gym_id 
            FROM public.user_gym_associations 
            WHERE user_id = auth.uid() AND role = 'owner'
        )
    );
