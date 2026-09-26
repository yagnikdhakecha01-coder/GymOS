-- ==============================================================================
-- GymOS Biometric Access Control & Attendance System (Multi-Tenant & Offline-First)
-- Safe, additive migration: zero data loss, preserves all existing tables and triggers.
-- ==============================================================================

-- 1. Gym Master Table Extensions
ALTER TABLE gyms 
ADD COLUMN IF NOT EXISTS biometric_attendance_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS biometric_device_secret VARCHAR(64);

-- Populate secrets for any gyms that don't have one
UPDATE gyms 
SET biometric_device_secret = encode(gen_random_bytes(24), 'hex') 
WHERE biometric_device_secret IS NULL;

-- 2. Member & Staff Biometric PIN
ALTER TABLE members 
ADD COLUMN IF NOT EXISTS biometric_pin INT,
ADD COLUMN IF NOT EXISTS biometric_sync_status VARCHAR(20) DEFAULT 'synced';

ALTER TABLE staff 
ADD COLUMN IF NOT EXISTS biometric_pin INT,
ADD COLUMN IF NOT EXISTS biometric_sync_status VARCHAR(20) DEFAULT 'synced';

-- Strict Multi-Tenant Isolation: Same PIN cannot be assigned to two members in the SAME gym.
-- Different gyms CAN have the same PIN without any conflict!
CREATE UNIQUE INDEX IF NOT EXISTS idx_gym_member_biometric_pin 
ON members (gym_id, biometric_pin) 
WHERE biometric_pin IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_gym_staff_biometric_pin 
ON staff (gym_id, biometric_pin) 
WHERE biometric_pin IS NOT NULL;

-- 3. Biometric Registered Devices Table
CREATE TABLE IF NOT EXISTS gym_biometric_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
    device_name VARCHAR(100) NOT NULL DEFAULT 'Main Biometric Gate',
    device_serial_number VARCHAR(100),
    device_model VARCHAR(100) DEFAULT 'eSSL / ZKTeco / Realtime',
    device_type VARCHAR(50) DEFAULT 'cloud_adms', -- 'cloud_adms' OR 'lan_bridge'
    ip_address VARCHAR(50),
    port INT DEFAULT 4370,
    status VARCHAR(20) DEFAULT 'offline', -- 'online', 'offline', 'syncing'
    last_heartbeat TIMESTAMPTZ,
    last_punch_at TIMESTAMPTZ,
    total_punches_synced BIGINT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_biometric_devices_gym 
ON gym_biometric_devices(gym_id);

ALTER TABLE gym_biometric_devices ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    DROP POLICY IF EXISTS "gym_biometric_devices_owner_policy" ON gym_biometric_devices;
    CREATE POLICY "gym_biometric_devices_owner_policy" 
    ON gym_biometric_devices FOR ALL 
    USING (
        gym_id IN (
            SELECT id FROM gyms WHERE owner_id = auth.uid()
        )
    );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 4. Biometric Two-Way Sync Queue (Member Expiry & Access Updates)
CREATE TABLE IF NOT EXISTS biometric_sync_queue (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
    member_id UUID REFERENCES members(id) ON DELETE CASCADE,
    staff_id UUID REFERENCES staff(id) ON DELETE CASCADE,
    biometric_pin INT,
    user_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) DEFAULT 'member', -- 'member' or 'staff'
    command_type VARCHAR(30) NOT NULL, -- 'SET_USER', 'DISABLE_USER', 'DELETE_USER'
    expiry_date DATE,                  -- Hardware machine sets this in internal memory
    is_access_allowed BOOLEAN DEFAULT true,
    sync_status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'synced', 'failed'
    attempts INT DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    synced_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_biometric_queue_lookup 
ON biometric_sync_queue(gym_id, sync_status) 
WHERE sync_status = 'pending';

-- 5. Raw Punch Idempotency Table (Prevents double attendance from offline bursts)
CREATE TABLE IF NOT EXISTS biometric_punches_raw (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
    biometric_pin INT NOT NULL,
    punch_time TIMESTAMPTZ NOT NULL,
    punch_type VARCHAR(20) DEFAULT 'auto', -- 'in', 'out', 'auto'
    device_id UUID REFERENCES gym_biometric_devices(id) ON DELETE SET NULL,
    processed_status VARCHAR(30) DEFAULT 'PROCESSED', -- 'PROCESSED', 'DUPLICATE', 'EXPIRED_DENIED', 'UNKNOWN_USER'
    member_id UUID REFERENCES members(id) ON DELETE SET NULL,
    staff_id UUID REFERENCES staff(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_gym_biometric_punch UNIQUE(gym_id, biometric_pin, punch_time)
);

CREATE INDEX IF NOT EXISTS idx_biometric_punches_gym_time 
ON biometric_punches_raw(gym_id, punch_time DESC);

-- 6. Trigger: When Member Membership is Added or Renewed -> Enqueue Biometric Update
CREATE OR REPLACE FUNCTION trg_fn_enqueue_biometric_member_update()
RETURNS TRIGGER AS $$
DECLARE
    v_member RECORD;
    v_latest_end_date DATE;
    v_is_active BOOLEAN;
BEGIN
    -- Get member details
    SELECT id, gym_id, name, biometric_pin, status 
    INTO v_member 
    FROM members 
    WHERE id = NEW.member_id;

    IF v_member.biometric_pin IS NOT NULL THEN
        -- Find latest active end_date for this member
        SELECT MAX(end_date) INTO v_latest_end_date 
        FROM member_memberships 
        WHERE member_id = v_member.id;

        v_is_active := (v_latest_end_date IS NOT NULL AND v_latest_end_date >= CURRENT_DATE);

        INSERT INTO biometric_sync_queue (
            gym_id, member_id, biometric_pin, user_name, role,
            command_type, expiry_date, is_access_allowed, sync_status
        ) VALUES (
            v_member.gym_id,
            v_member.id,
            v_member.biometric_pin,
            v_member.name,
            'member',
            'SET_USER',
            v_latest_end_date,
            v_is_active,
            'pending'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_member_membership_biometric_sync ON member_memberships;
CREATE TRIGGER trg_member_membership_biometric_sync
AFTER INSERT OR UPDATE ON member_memberships
FOR EACH ROW EXECUTE FUNCTION trg_fn_enqueue_biometric_member_update();

-- 7. Trigger: When Member biometric_pin is assigned or updated
CREATE OR REPLACE FUNCTION trg_fn_enqueue_member_pin_change()
RETURNS TRIGGER AS $$
DECLARE
    v_latest_end_date DATE;
    v_is_active BOOLEAN;
BEGIN
    -- Only enqueue if the member has a valid biometric_pin assigned
    IF NEW.biometric_pin IS NOT NULL THEN
        IF (TG_OP = 'INSERT') 
           OR (OLD.biometric_pin IS DISTINCT FROM NEW.biometric_pin) 
           OR (OLD.status IS DISTINCT FROM NEW.status) THEN
           
            SELECT MAX(end_date) INTO v_latest_end_date 
            FROM member_memberships 
            WHERE member_id = NEW.id;

            v_is_active := (lower(COALESCE(NEW.status, '')) = 'active') 
                           AND (v_latest_end_date IS NULL OR v_latest_end_date >= CURRENT_DATE);

            INSERT INTO biometric_sync_queue (
                gym_id, member_id, biometric_pin, user_name, role,
                command_type, expiry_date, is_access_allowed, sync_status
            ) VALUES (
                NEW.gym_id,
                NEW.id,
                NEW.biometric_pin,
                NEW.name,
                'member',
                'SET_USER',
                v_latest_end_date,
                v_is_active,
                'pending'
            );
        END IF;
    ELSIF TG_OP = 'UPDATE' AND OLD.biometric_pin IS NOT NULL AND NEW.biometric_pin IS NULL THEN
        -- If biometric_pin was unassigned/removed, delete the user from the biometric machine
        INSERT INTO biometric_sync_queue (
            gym_id, member_id, biometric_pin, user_name, role,
            command_type, expiry_date, is_access_allowed, sync_status
        ) VALUES (
            OLD.gym_id,
            OLD.id,
            OLD.biometric_pin,
            OLD.name,
            'member',
            'DELETE_USER',
            NULL,
            false,
            'pending'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_members_biometric_pin_sync ON members;
CREATE TRIGGER trg_members_biometric_pin_sync
AFTER INSERT OR UPDATE OF biometric_pin, status ON members
FOR EACH ROW EXECUTE FUNCTION trg_fn_enqueue_member_pin_change();

-- 8. High-Security Core RPC: Process Punches in Batch (Offline Buffer Friendly)
CREATE OR REPLACE FUNCTION process_biometric_punch_batch(
    p_device_secret VARCHAR,
    p_punches JSONB
)
RETURNS JSONB AS $$
DECLARE
    v_gym RECORD;
    v_punch JSONB;
    v_pin INT;
    v_punch_time TIMESTAMPTZ;
    v_member RECORD;
    v_staff RECORD;
    v_results JSONB := '[]'::jsonb;
    v_today_str TEXT;
    v_expiry_date DATE;
    v_is_expired BOOLEAN;
    v_existing_attendance RECORD;
    v_inserted_raw_id UUID;
    v_processed_count INT := 0;
BEGIN
    -- 1. Validate Secret & Fetch Gym
    SELECT id, name, biometric_attendance_enabled 
    INTO v_gym 
    FROM gyms 
    WHERE biometric_device_secret = p_device_secret;

    IF v_gym.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid device secret token');
    END IF;

    IF NOT COALESCE(v_gym.biometric_attendance_enabled, false) THEN
        RETURN jsonb_build_object('success', false, 'error', 'Biometric attendance is disabled for this gym by owner');
    END IF;

    -- Update device last_heartbeat
    UPDATE gym_biometric_devices 
    SET last_heartbeat = NOW(), status = 'online' 
    WHERE gym_id = v_gym.id;

    -- 2. Loop Through Each Punch in Batch
    FOR v_punch IN SELECT * FROM jsonb_array_elements(p_punches)
    LOOP
        v_pin := (v_punch->>'pin')::INT;
        v_punch_time := COALESCE((v_punch->>'punch_time')::TIMESTAMPTZ, NOW());
        v_today_str := to_char(v_punch_time AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD');

        -- A. Check for raw deduplication (if already recorded)
        BEGIN
            INSERT INTO biometric_punches_raw (
                gym_id, biometric_pin, punch_time, punch_type, processed_status
            ) VALUES (
                v_gym.id, v_pin, v_punch_time, COALESCE(v_punch->>'punch_type', 'auto'), 'PENDING'
            ) RETURNING id INTO v_inserted_raw_id;
        EXCEPTION WHEN unique_violation THEN
            -- Duplicate punch received, skip cleanly
            v_results := v_results || jsonb_build_object(
                'pin', v_pin,
                'punch_time', v_punch_time,
                'status', 'DUPLICATE_IGNORED'
            );
            CONTINUE;
        END;

        -- B. Resolve Member
        SELECT id, name, status 
        INTO v_member 
        FROM members 
        WHERE gym_id = v_gym.id AND biometric_pin = v_pin;

        IF v_member.id IS NOT NULL THEN
            -- Check member expiry
            SELECT MAX(end_date) INTO v_expiry_date 
            FROM member_memberships 
            WHERE member_id = v_member.id;

            v_is_expired := (v_expiry_date IS NOT NULL AND v_expiry_date < (v_punch_time AT TIME ZONE 'Asia/Kolkata')::DATE);

            -- Update raw punch log with member reference
            UPDATE biometric_punches_raw 
            SET member_id = v_member.id,
                processed_status = CASE WHEN v_is_expired THEN 'EXPIRED_ATTENDANCE' ELSE 'SUCCESS' END 
            WHERE id = v_inserted_raw_id;

            -- Check if member already checked in today
            SELECT id, check_in, check_out 
            INTO v_existing_attendance 
            FROM attendance_logs 
            WHERE gym_id = v_gym.id 
              AND member_id = v_member.id 
              AND date = v_today_str;

            IF v_existing_attendance.id IS NULL THEN
                -- Insert Check-in
                INSERT INTO attendance_logs (
                    gym_id, user_id, member_id, role, user_type, name, gym_name,
                    date, check_in, status, method, created_at
                ) VALUES (
                    v_gym.id, v_member.id, v_member.id, 'member', 'member', v_member.name, v_gym.name,
                    v_today_str, v_punch_time, 'present', 'biometric', NOW()
                );
            ELSE
                -- Punch out if at least 5 minutes after check_in
                IF v_punch_time > (v_existing_attendance.check_in + INTERVAL '5 minutes') THEN
                    UPDATE attendance_logs 
                    SET check_out = v_punch_time,
                        working_minutes = ROUND(EXTRACT(EPOCH FROM (v_punch_time - v_existing_attendance.check_in)) / 60)
                    WHERE id = v_existing_attendance.id;
                END IF;
            END IF;

            v_processed_count := v_processed_count + 1;
            v_results := v_results || jsonb_build_object(
                'pin', v_pin,
                'name', v_member.name,
                'role', 'member',
                'is_expired', v_is_expired,
                'status', 'SUCCESS'
            );
            CONTINUE;
        END IF;

        -- C. Resolve Staff (if not member)
        SELECT id, name, role 
        INTO v_staff 
        FROM staff 
        WHERE gym_id = v_gym.id AND biometric_pin = v_pin;

        IF v_staff.id IS NOT NULL THEN
            UPDATE biometric_punches_raw 
            SET staff_id = v_staff.id, processed_status = 'SUCCESS' 
            WHERE id = v_inserted_raw_id;

            -- Staff attendance logic
            SELECT id, check_in, check_out 
            INTO v_existing_attendance 
            FROM attendance_logs 
            WHERE gym_id = v_gym.id 
              AND staff_id = v_staff.id 
              AND date = v_today_str;

            IF v_existing_attendance.id IS NULL THEN
                INSERT INTO attendance_logs (
                    gym_id, user_id, staff_id, role, user_type, name, gym_name,
                    date, check_in, status, method, created_at
                ) VALUES (
                    v_gym.id, v_staff.id, v_staff.id, 'staff', 'staff', v_staff.name, v_gym.name,
                    v_today_str, v_punch_time, 'present', 'biometric', NOW()
                );
            ELSE
                IF v_punch_time > (v_existing_attendance.check_in + INTERVAL '5 minutes') THEN
                    UPDATE attendance_logs 
                    SET check_out = v_punch_time,
                        working_minutes = ROUND(EXTRACT(EPOCH FROM (v_punch_time - v_existing_attendance.check_in)) / 60)
                    WHERE id = v_existing_attendance.id;
                END IF;
            END IF;

            v_processed_count := v_processed_count + 1;
            v_results := v_results || jsonb_build_object(
                'pin', v_pin,
                'name', v_staff.name,
                'role', 'staff',
                'status', 'SUCCESS'
            );
            CONTINUE;
        END IF;

        -- Unrecognized PIN
        UPDATE biometric_punches_raw 
        SET processed_status = 'UNKNOWN_USER' 
        WHERE id = v_inserted_raw_id;

        v_results := v_results || jsonb_build_object(
            'pin', v_pin,
            'status', 'UNKNOWN_PIN'
        );
    END LOOP;

    RETURN jsonb_build_object(
        'success', true,
        'processed_count', v_processed_count,
        'results', v_results
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. RPC for Bridge/Device to Poll Pending Member Updates (Two-Way Sync)
CREATE OR REPLACE FUNCTION poll_biometric_commands(p_device_secret VARCHAR)
RETURNS JSONB AS $$
DECLARE
    v_gym_id UUID;
    v_commands JSONB;
BEGIN
    SELECT id INTO v_gym_id FROM gyms WHERE biometric_device_secret = p_device_secret;
    IF v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized device');
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id,
        'pin', biometric_pin,
        'name', user_name,
        'role', role,
        'command', command_type,
        'expiry_date', expiry_date,
        'is_access_allowed', is_access_allowed
    )), '[]'::jsonb)
    INTO v_commands
    FROM biometric_sync_queue
    WHERE gym_id = v_gym_id AND sync_status = 'pending'
    LIMIT 100;

    RETURN jsonb_build_object(
        'success', true,
        'commands', v_commands
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. RPC for Bridge/Device to Acknowledge Synced Commands
CREATE OR REPLACE FUNCTION ack_biometric_commands(
    p_device_secret VARCHAR,
    p_command_ids UUID[]
)
RETURNS JSONB AS $$
DECLARE
    v_gym_id UUID;
BEGIN
    SELECT id INTO v_gym_id FROM gyms WHERE biometric_device_secret = p_device_secret;
    IF v_gym_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized device');
    END IF;

    UPDATE biometric_sync_queue 
    SET sync_status = 'synced', synced_at = NOW() 
    WHERE gym_id = v_gym_id AND id = ANY(p_command_ids);

    RETURN jsonb_build_object('success', true, 'acknowledged_count', array_length(p_command_ids, 1));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 11. RPC for Owner to Regenerate Biometric Secret if Compromised
CREATE OR REPLACE FUNCTION regenerate_gym_biometric_secret(p_gym_id UUID)
RETURNS VARCHAR AS $$
DECLARE
    v_new_secret VARCHAR(64);
BEGIN
    -- Verify ownership
    IF NOT EXISTS (SELECT 1 FROM gyms WHERE id = p_gym_id AND owner_id = auth.uid()) THEN
        RAISE EXCEPTION 'Unauthorized: Only the gym owner can regenerate biometric secret';
    END IF;

    v_new_secret := encode(gen_random_bytes(24), 'hex');

    UPDATE gyms 
    SET biometric_device_secret = v_new_secret 
    WHERE id = p_gym_id;

    RETURN v_new_secret;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
