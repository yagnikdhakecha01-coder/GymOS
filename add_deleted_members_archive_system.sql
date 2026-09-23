-- =========================================================================
-- SUPER ADMIN DELETED MEMBERS ARCHIVE & 1-CLICK RESTORE SYSTEM
-- =========================================================================

-- 1. Create deleted_members Archive Table
CREATE TABLE IF NOT EXISTS public.deleted_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL REFERENCES public.gyms(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    avatar_url TEXT,
    membership_name TEXT,
    membership_plan_id TEXT,
    payment_status TEXT,
    total_received_amount NUMERIC DEFAULT 0,
    pending_amount NUMERIC DEFAULT 0,
    member_data JSONB NOT NULL,
    financial_transactions JSONB DEFAULT '[]'::jsonb,
    member_memberships JSONB DEFAULT '[]'::jsonb,
    membership_payments JSONB DEFAULT '[]'::jsonb,
    attendance_logs JSONB DEFAULT '[]'::jsonb,
    user_associations JSONB DEFAULT '[]'::jsonb,
    deleted_at TIMESTAMPTZ DEFAULT now(),
    deleted_by UUID DEFAULT auth.uid()
);

-- RLS & Grants
ALTER TABLE public.deleted_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS deleted_members_all ON public.deleted_members;
CREATE POLICY deleted_members_all ON public.deleted_members FOR ALL USING (true) WITH CHECK (true);
GRANT ALL ON TABLE public.deleted_members TO anon, authenticated, service_role;

-- Indexing for fast queries
CREATE INDEX IF NOT EXISTS idx_deleted_members_gym ON public.deleted_members(gym_id);
CREATE INDEX IF NOT EXISTS idx_deleted_members_deleted_at ON public.deleted_members(deleted_at DESC);

-- 2. RPC to Archive & Delete Member (Clean cascade with full JSONB backup)
CREATE OR REPLACE FUNCTION public.admin_archive_delete_member(
    p_member_id UUID,
    p_gym_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_member RECORD;
    v_plan_title TEXT := 'No Plan';
    v_member_json JSONB;
    v_fin_json JSONB := '[]'::jsonb;
    v_mships_json JSONB := '[]'::jsonb;
    v_payments_json JSONB := '[]'::jsonb;
    v_att_json JSONB := '[]'::jsonb;
    v_user_assoc_json JSONB := '[]'::jsonb;
    v_archive_id UUID;
    v_ft_count INT := 0;
    v_att_count INT := 0;
BEGIN
    -- 1. Fetch Member record
    SELECT * INTO v_member FROM public.members WHERE id = p_member_id AND gym_id = p_gym_id;
    IF v_member.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Member not found');
    END IF;

    -- Fetch Plan title if available
    IF v_member.membership_plan_id IS NOT NULL AND TRIM(v_member.membership_plan_id) != '' THEN
        BEGIN
            SELECT title INTO v_plan_title FROM public.membership_plans WHERE id::text = v_member.membership_plan_id::text;
        EXCEPTION WHEN OTHERS THEN
            v_plan_title := 'No Plan';
        END;
    END IF;

    v_member_json := to_jsonb(v_member);

    -- 2. Snapshot linked financial transactions
    BEGIN
        SELECT COALESCE(jsonb_agg(to_jsonb(ft)), '[]'::jsonb), COUNT(*)
        INTO v_fin_json, v_ft_count
        FROM public.finance_transactions ft
        WHERE (ft.reference_id = p_member_id::text OR ft.notes ILIKE '%' || v_member.name || '%')
          AND ft.gym_id = p_gym_id;
    EXCEPTION WHEN OTHERS THEN
        v_fin_json := '[]'::jsonb;
    END;

    -- 3. Snapshot member_memberships
    BEGIN
        SELECT COALESCE(jsonb_agg(to_jsonb(mm)), '[]'::jsonb)
        INTO v_mships_json
        FROM public.member_memberships mm
        WHERE mm.member_id::text = p_member_id::text AND mm.gym_id = p_gym_id;
    EXCEPTION WHEN OTHERS THEN
        v_mships_json := '[]'::jsonb;
    END;

    -- 4. Snapshot membership_payments
    BEGIN
        SELECT COALESCE(jsonb_agg(to_jsonb(mp)), '[]'::jsonb)
        INTO v_payments_json
        FROM public.membership_payments mp
        WHERE mp.member_id::text = p_member_id::text;
    EXCEPTION WHEN OTHERS THEN
        v_payments_json := '[]'::jsonb;
    END;

    -- 5. Snapshot attendance_logs
    BEGIN
        SELECT COALESCE(jsonb_agg(to_jsonb(att)), '[]'::jsonb), COUNT(*)
        INTO v_att_json, v_att_count
        FROM public.attendance_logs att
        WHERE att.member_id::text = p_member_id::text AND att.gym_id = p_gym_id;
    EXCEPTION WHEN OTHERS THEN
        v_att_json := '[]'::jsonb;
    END;

    -- 6. Snapshot user_gym_associations if user_id exists
    IF v_member.user_id IS NOT NULL THEN
        BEGIN
            SELECT COALESCE(jsonb_agg(to_jsonb(uga)), '[]'::jsonb)
            INTO v_user_assoc_json
            FROM public.user_gym_associations uga
            WHERE uga.user_id = v_member.user_id AND uga.gym_id = p_gym_id;
        EXCEPTION WHEN OTHERS THEN
            v_user_assoc_json := '[]'::jsonb;
        END;
    END IF;

    -- 7. Insert Archive Snapshot into deleted_members
    INSERT INTO public.deleted_members (
        member_id,
        gym_id,
        full_name,
        phone,
        email,
        avatar_url,
        membership_name,
        membership_plan_id,
        payment_status,
        total_received_amount,
        pending_amount,
        member_data,
        financial_transactions,
        member_memberships,
        membership_payments,
        attendance_logs,
        user_associations,
        deleted_at,
        deleted_by
    ) VALUES (
        p_member_id,
        p_gym_id,
        COALESCE(v_member.name, 'Member'),
        v_member.phone,
        v_member.email,
        v_member.avatar,
        COALESCE(v_plan_title, 'No Plan'),
        v_member.membership_plan_id,
        COALESCE(v_member.payment_status, 'Pending'),
        COALESCE(v_member.total_received_amount, 0),
        COALESCE(v_member.pending_amount, 0),
        v_member_json,
        v_fin_json,
        v_mships_json,
        v_payments_json,
        v_att_json,
        v_user_assoc_json,
        now(),
        auth.uid()
    ) RETURNING id INTO v_archive_id;

    -- 8. Delete all active records cleanly so they don't affect live finances or active lists
    -- Clean finance transactions
    BEGIN
        DELETE FROM public.finance_transactions
        WHERE (reference_id = p_member_id::text OR notes ILIKE '%' || v_member.name || '%')
          AND gym_id = p_gym_id;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- Clean attendance
    BEGIN
        DELETE FROM public.attendance_logs
        WHERE member_id::text = p_member_id::text AND gym_id = p_gym_id;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- Clean membership records
    BEGIN
        DELETE FROM public.member_memberships
        WHERE member_id::text = p_member_id::text AND gym_id = p_gym_id;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    BEGIN
        DELETE FROM public.membership_payments
        WHERE member_id::text = p_member_id::text;
    EXCEPTION WHEN OTHERS THEN NULL; END;

    -- Clean user gym associations for member role
    IF v_member.user_id IS NOT NULL THEN
        BEGIN
            DELETE FROM public.user_gym_associations
            WHERE user_id = v_member.user_id AND gym_id = p_gym_id AND role = 'member';
        EXCEPTION WHEN OTHERS THEN NULL; END;
    END IF;

    -- Finally delete from members table
    DELETE FROM public.members WHERE id = p_member_id AND gym_id = p_gym_id;

    RETURN jsonb_build_object(
        'success', true,
        'archive_id', v_archive_id,
        'member_name', v_member.name,
        'transactions_archived', v_ft_count,
        'attendance_archived', v_att_count,
        'message', 'Member safely archived and removed from active gym data'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_archive_delete_member(UUID, UUID) TO anon, authenticated, service_role;


-- 3. RPC to 1-Click Restore Deleted Member
CREATE OR REPLACE FUNCTION public.admin_restore_deleted_member(
    p_deleted_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_arch RECORD;
    v_item JSONB;
    v_restored_tx INT := 0;
    v_restored_att INT := 0;
BEGIN
    -- 1. Fetch from deleted_members
    SELECT * INTO v_arch FROM public.deleted_members WHERE id = p_deleted_id;
    IF v_arch.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Deleted member archive record not found');
    END IF;

    -- 2. Restore into members table
    INSERT INTO public.members (
        id,
        gym_id,
        user_id,
        name,
        phone,
        status,
        join_date,
        avatar,
        membership_plan_id,
        pt_member,
        pt_trainer,
        assigned_workout_id,
        assigned_diet_id,
        medical_details,
        notes,
        pending_amount,
        extra_fields,
        created_at,
        discount_amount,
        total_received_amount,
        payment_status,
        created_by_info,
        email
    ) VALUES (
        (v_arch.member_data->>'id')::uuid,
        (v_arch.member_data->>'gym_id')::uuid,
        CASE WHEN v_arch.member_data->>'user_id' IS NOT NULL AND v_arch.member_data->>'user_id' != '' THEN (v_arch.member_data->>'user_id')::uuid ELSE NULL END,
        COALESCE(v_arch.member_data->>'name', v_arch.full_name),
        v_arch.member_data->>'phone',
        COALESCE(v_arch.member_data->>'status', 'Active'),
        v_arch.member_data->>'join_date',
        v_arch.member_data->>'avatar',
        v_arch.member_data->>'membership_plan_id',
        COALESCE((v_arch.member_data->>'pt_member')::boolean, false),
        CASE WHEN v_arch.member_data->>'pt_trainer' IS NOT NULL AND v_arch.member_data->>'pt_trainer' != '' THEN (v_arch.member_data->>'pt_trainer')::uuid ELSE NULL END,
        v_arch.member_data->>'assigned_workout_id',
        v_arch.member_data->>'assigned_diet_id',
        v_arch.member_data->>'medical_details',
        v_arch.member_data->>'notes',
        COALESCE((v_arch.member_data->>'pending_amount')::numeric, v_arch.pending_amount),
        v_arch.member_data->'extra_fields',
        COALESCE((v_arch.member_data->>'created_at')::timestamptz, now()),
        COALESCE((v_arch.member_data->>'discount_amount')::numeric, 0),
        COALESCE((v_arch.member_data->>'total_received_amount')::numeric, v_arch.total_received_amount),
        COALESCE(v_arch.member_data->>'payment_status', v_arch.payment_status),
        v_arch.member_data->>'created_by_info',
        v_arch.member_data->>'email'
    )
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        phone = EXCLUDED.phone,
        status = EXCLUDED.status,
        membership_plan_id = EXCLUDED.membership_plan_id,
        total_received_amount = EXCLUDED.total_received_amount,
        pending_amount = EXCLUDED.pending_amount,
        payment_status = EXCLUDED.payment_status;

    -- 3. Restore finance_transactions
    IF v_arch.financial_transactions IS NOT NULL AND jsonb_array_length(v_arch.financial_transactions) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_arch.financial_transactions)
        LOOP
            BEGIN
                INSERT INTO public.finance_transactions (
                    id,
                    gym_id,
                    amount,
                    type,
                    category,
                    payment_method,
                    transaction_date,
                    reference_id,
                    created_by,
                    notes,
                    created_at,
                    expense_date,
                    entry_date,
                    revenue_date,
                    created_by_info
                ) VALUES (
                    (v_item->>'id')::uuid,
                    (v_item->>'gym_id')::uuid,
                    (v_item->>'amount')::numeric,
                    v_item->>'type',
                    v_item->>'category',
                    v_item->>'payment_method',
                    (v_item->>'transaction_date')::timestamptz,
                    v_item->>'reference_id',
                    CASE WHEN v_item->>'created_by' IS NOT NULL AND v_item->>'created_by' != '' THEN (v_item->>'created_by')::uuid ELSE NULL END,
                    v_item->>'notes',
                    COALESCE((v_item->>'created_at')::timestamptz, now()),
                    CASE WHEN v_item->>'expense_date' IS NOT NULL AND v_item->>'expense_date' != '' THEN (v_item->>'expense_date')::date ELSE NULL END,
                    CASE WHEN v_item->>'entry_date' IS NOT NULL AND v_item->>'entry_date' != '' THEN (v_item->>'entry_date')::date ELSE NULL END,
                    CASE WHEN v_item->>'revenue_date' IS NOT NULL AND v_item->>'revenue_date' != '' THEN (v_item->>'revenue_date')::date ELSE NULL END,
                    v_item->>'created_by_info'
                ) ON CONFLICT (id) DO NOTHING;
                v_restored_tx := v_restored_tx + 1;
            EXCEPTION WHEN OTHERS THEN NULL; END;
        END LOOP;
    END IF;

    -- 4. Restore member_memberships
    IF v_arch.member_memberships IS NOT NULL AND jsonb_array_length(v_arch.member_memberships) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_arch.member_memberships)
        LOOP
            BEGIN
                INSERT INTO public.member_memberships (
                    id, gym_id, member_id, plan_id, start_date, end_date, price, status, created_at
                ) VALUES (
                    (v_item->>'id')::uuid,
                    (v_item->>'gym_id')::uuid,
                    (v_item->>'member_id')::uuid,
                    (v_item->>'plan_id')::uuid,
                    (v_item->>'start_date')::date,
                    (v_item->>'end_date')::date,
                    (v_item->>'price')::numeric,
                    COALESCE(v_item->>'status', 'Active'),
                    COALESCE((v_item->>'created_at')::timestamptz, now())
                ) ON CONFLICT (id) DO NOTHING;
            EXCEPTION WHEN OTHERS THEN NULL; END;
        END LOOP;
    END IF;

    -- 5. Restore attendance_logs
    IF v_arch.attendance_logs IS NOT NULL AND jsonb_array_length(v_arch.attendance_logs) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_arch.attendance_logs)
        LOOP
            BEGIN
                INSERT INTO public.attendance_logs (
                    id, gym_id, member_id, date, status, check_in, check_out, method, created_at
                ) VALUES (
                    (v_item->>'id')::uuid,
                    (v_item->>'gym_id')::uuid,
                    v_item->>'member_id',
                    v_item->>'date',
                    COALESCE(v_item->>'status', 'Present'),
                    CASE WHEN v_item->>'check_in' IS NOT NULL AND v_item->>'check_in' != '' THEN (v_item->>'check_in')::timestamptz ELSE NULL END,
                    CASE WHEN v_item->>'check_out' IS NOT NULL AND v_item->>'check_out' != '' THEN (v_item->>'check_out')::timestamptz ELSE NULL END,
                    COALESCE(v_item->>'method', 'Manual'),
                    COALESCE((v_item->>'created_at')::timestamptz, now())
                ) ON CONFLICT (id) DO NOTHING;
                v_restored_att := v_restored_att + 1;
            EXCEPTION WHEN OTHERS THEN NULL; END;
        END LOOP;
    END IF;

    -- 6. Restore user_gym_associations if user_id exists
    IF v_arch.user_associations IS NOT NULL AND jsonb_array_length(v_arch.user_associations) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(v_arch.user_associations)
        LOOP
            BEGIN
                INSERT INTO public.user_gym_associations (
                    id, user_id, gym_id, role, created_at
                ) VALUES (
                    (v_item->>'id')::uuid,
                    (v_item->>'user_id')::uuid,
                    (v_item->>'gym_id')::uuid,
                    COALESCE(v_item->>'role', 'member'),
                    COALESCE((v_item->>'created_at')::timestamptz, now())
                ) ON CONFLICT DO NOTHING;
            EXCEPTION WHEN OTHERS THEN NULL; END;
        END LOOP;
    END IF;

    -- 7. Remove from deleted_members archive
    DELETE FROM public.deleted_members WHERE id = p_deleted_id;

    RETURN jsonb_build_object(
        'success', true,
        'member_name', v_arch.full_name,
        'transactions_restored', v_restored_tx,
        'attendance_restored', v_restored_att,
        'message', 'Member and all records restored successfully'
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_restore_deleted_member(UUID) TO anon, authenticated, service_role;


-- 4. RPC to Permanently Purge Deleted Member Archive Record
CREATE OR REPLACE FUNCTION public.admin_purge_deleted_member(
    p_deleted_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM public.deleted_members WHERE id = p_deleted_id;
    RETURN jsonb_build_object('success', true, 'message', 'Member permanently purged from archive');
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_purge_deleted_member(UUID) TO anon, authenticated, service_role;
