-- MIGRATION: FIX DUPLICATE COMMISSION LEDGER ENTRIES
-- 1. Deduplicate existing entries in public.commission_ledger
DELETE FROM public.commission_ledger a
USING public.commission_ledger b
WHERE a.id > b.id 
  AND a.payment_id = b.payment_id;

-- 2. Modify the finance transaction trigger to remove double commission generation.
-- The trigger fn_on_finance_transaction_inserted inserts into public.membership_payments,
-- which already has an AFTER INSERT trigger (fn_generate_commission_entry) that handles
-- inserting into public.commission_ledger. Thus, we remove the redundant direct insert from here.
CREATE OR REPLACE FUNCTION public.fn_on_finance_transaction_inserted()
RETURNS TRIGGER AS $$
DECLARE
    v_member_membership_id UUID;
    v_payment_id UUID;
    v_ref_uuid UUID;
BEGIN
    -- Check if this transaction is revenue for membership and has a valid member reference_id
    IF NEW.type = 'Revenue' AND NEW.category = 'Membership' AND NEW.reference_id IS NOT NULL THEN
        -- Safely cast reference_id to UUID if it matches UUID format
        IF NEW.reference_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' THEN
            v_ref_uuid := NEW.reference_id::UUID;
        ELSE
            RETURN NEW;
        END IF;

        -- Find the active member membership plan
        SELECT id INTO v_member_membership_id 
        FROM public.member_memberships 
        WHERE member_id = v_ref_uuid
        ORDER BY created_at DESC 
        LIMIT 1;

        -- If no active membership plan exists, create a default dummy membership linking record
        IF v_member_membership_id IS NULL THEN
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
                v_ref_uuid,
                (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1),
                CURRENT_DATE,
                CURRENT_DATE + (
                    COALESCE(
                        (SELECT duration_days FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1) LIMIT 1),
                        (SELECT COALESCE(duration_months, 1) * 30 FROM public.membership_plans WHERE id = (SELECT membership_plan_id FROM public.members WHERE id = v_ref_uuid LIMIT 1) LIMIT 1),
                        30
                    ) || ' days'
                )::INTERVAL,
                NEW.amount,
                0.0,
                'Unpaid'
            ) RETURNING id INTO v_member_membership_id;
        END IF;

        -- Insert record into membership_payments to register actual received payment details
        -- This will automatically trigger fn_generate_commission_entry to create the commission_ledger record.
        INSERT INTO public.membership_payments (
            gym_id,
            member_membership_id,
            amount,
            payment_mode,
            transaction_id,
            payment_date
        )
        VALUES (
            NEW.gym_id,
            v_member_membership_id,
            NEW.amount,
            COALESCE(NEW.payment_method::public.payment_mode, 'Cash'::public.payment_mode),
            NEW.id,
            CURRENT_DATE
        ) RETURNING id INTO v_payment_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
