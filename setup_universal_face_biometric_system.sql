-- ==============================================================================
-- GymOS Phase 32: Universal Face & Biometric Terminal Integration
-- Multi-Tenant Isolation (Zero Cross-Gym Collision) & Offline-First Expiry Sync
-- ==============================================================================

-- 1. Upgrade gym_biometric_devices table
ALTER TABLE gym_biometric_devices 
ADD COLUMN IF NOT EXISTS device_brand VARCHAR(50) DEFAULT 'eSSL',
ADD COLUMN IF NOT EXISTS device_category VARCHAR(50) DEFAULT 'face',
ADD COLUMN IF NOT EXISTS connection_mode VARCHAR(50) DEFAULT 'cloud_adms',
ADD COLUMN IF NOT EXISTS pairing_code VARCHAR(30);

-- Strict Global Uniqueness: A physical machine serial can belong to ONLY ONE gym!
-- Prevents any possibility of Gym A's machine leaking or receiving data from Gym B.
CREATE UNIQUE INDEX IF NOT EXISTS uq_biometric_device_serial 
ON gym_biometric_devices (device_serial_number) 
WHERE device_serial_number IS NOT NULL AND trim(device_serial_number) != '';

-- RLS Policy on gym_biometric_devices
ALTER TABLE gym_biometric_devices ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    DROP POLICY IF EXISTS "gym_biometric_devices_gym_isolation_policy" ON gym_biometric_devices;
    CREATE POLICY "gym_biometric_devices_gym_isolation_policy" 
    ON gym_biometric_devices FOR ALL 
    USING (
        gym_id IN (
            SELECT gym_id FROM user_gym_associations 
            WHERE user_id = auth.uid() AND lower(role) IN ('owner', 'admin')
            UNION
            SELECT id FROM gyms WHERE owner_id = auth.uid()
        )
        OR (auth.uid() IS NOT NULL AND is_super_admin(auth.uid()))
    );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 2. Unlinked Biometric Punches Discovery Table
-- When a face punches that isn't mapped to a GymOS member yet (e.g. gym already had enrolled members on machine)
CREATE TABLE IF NOT EXISTS unlinked_biometric_punches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    gym_id UUID NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
    device_id UUID REFERENCES gym_biometric_devices(id) ON DELETE CASCADE,
    biometric_pin INT NOT NULL,
    punch_time TIMESTAMPTZ NOT NULL,
    verify_mode VARCHAR(30) DEFAULT 'face', -- 'face', 'fingerprint', 'card'
    punch_count INT DEFAULT 1,
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT uq_gym_unlinked_pin UNIQUE (gym_id, biometric_pin)
);

CREATE INDEX IF NOT EXISTS idx_unlinked_punches_gym 
ON unlinked_biometric_punches (gym_id);

ALTER TABLE unlinked_biometric_punches ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    DROP POLICY IF EXISTS "unlinked_punches_gym_isolation_policy" ON unlinked_biometric_punches;
    CREATE POLICY "unlinked_punches_gym_isolation_policy" 
    ON unlinked_biometric_punches FOR ALL 
    USING (
        gym_id IN (
            SELECT gym_id FROM user_gym_associations 
            WHERE user_id = auth.uid() AND lower(role) IN ('owner', 'admin')
            UNION
            SELECT id FROM gyms WHERE owner_id = auth.uid()
        )
        OR (auth.uid() IS NOT NULL AND is_super_admin(auth.uid()))
    );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- 3. RPC: Get Gym Biometric Devices (with real-time online/offline and counts)
CREATE OR REPLACE FUNCTION get_gym_biometric_devices(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_devices JSONB;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM user_gym_associations 
            WHERE gym_id = p_gym_id AND user_id = auth.uid() AND lower(role) IN ('owner', 'admin')
        ) AND NOT EXISTS (
            SELECT 1 FROM gyms WHERE id = p_gym_id AND owner_id = auth.uid()
        ) AND NOT is_super_admin(auth.uid()) THEN
            RAISE EXCEPTION 'Unauthorized';
        END IF;
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id,
        'device_name', device_name,
        'device_serial_number', device_serial_number,
        'device_brand', COALESCE(device_brand, 'eSSL'),
        'device_category', COALESCE(device_category, 'face'),
        'connection_mode', COALESCE(connection_mode, 'cloud_adms'),
        'ip_address', ip_address,
        'port', port,
        'status', CASE 
            WHEN last_heartbeat IS NOT NULL AND last_heartbeat > (NOW() - INTERVAL '3 minutes') THEN 'online'
            ELSE 'offline'
        END,
        'last_heartbeat', last_heartbeat,
        'last_punch_at', last_punch_at,
        'total_punches_synced', COALESCE(total_punches_synced, 0),
        'created_at', created_at
    ) ORDER BY created_at ASC), '[]'::jsonb)
    INTO v_devices
    FROM gym_biometric_devices
    WHERE gym_id = p_gym_id;

    RETURN jsonb_build_object('success', true, 'devices', v_devices);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. RPC: Register or Update Biometric Device (Strict Multi-Tenant Verification)
CREATE OR REPLACE FUNCTION register_gym_biometric_device(
    p_gym_id UUID,
    p_device_name TEXT,
    p_serial_number TEXT,
    p_brand TEXT DEFAULT 'eSSL',
    p_category TEXT DEFAULT 'face',
    p_mode TEXT DEFAULT 'cloud_adms',
    p_ip TEXT DEFAULT NULL,
    p_port INT DEFAULT 4370,
    p_device_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_clean_sn TEXT;
    v_existing_other RECORD;
    v_target_id UUID;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM user_gym_associations 
            WHERE gym_id = p_gym_id AND user_id = auth.uid() AND lower(role) IN ('owner', 'admin')
        ) AND NOT EXISTS (
            SELECT 1 FROM gyms WHERE id = p_gym_id AND owner_id = auth.uid()
        ) AND NOT is_super_admin(auth.uid()) THEN
            RAISE EXCEPTION 'Unauthorized';
        END IF;
    END IF;

    v_clean_sn := trim(COALESCE(p_serial_number, ''));

    IF v_clean_sn = '' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Device Serial Number (SN) is required');
    END IF;

    -- Strict multi-gym isolation: ensure this SN is NOT already paired with ANOTHER gym!
    SELECT id, gym_id INTO v_existing_other
    FROM gym_biometric_devices
    WHERE device_serial_number = v_clean_sn
      AND (p_device_id IS NULL OR id != p_device_id);

    IF v_existing_other.id IS NOT NULL THEN
        IF v_existing_other.gym_id != p_gym_id THEN
            RETURN jsonb_build_object(
                'success', false, 
                'error', 'This machine Serial Number is already registered with another gym. Each device can belong to only one gym.'
            );
        END IF;
    END IF;

    IF p_device_id IS NOT NULL THEN
        UPDATE gym_biometric_devices
        SET device_name = COALESCE(p_device_name, device_name),
            device_serial_number = v_clean_sn,
            device_brand = COALESCE(p_brand, device_brand),
            device_category = COALESCE(p_category, device_category),
            connection_mode = COALESCE(p_mode, connection_mode),
            ip_address = p_ip,
            port = COALESCE(p_port, port),
            updated_at = NOW()
        WHERE id = p_device_id AND gym_id = p_gym_id
        RETURNING id INTO v_target_id;
    ELSE
        INSERT INTO gym_biometric_devices (
            gym_id, device_name, device_serial_number, device_brand,
            device_category, connection_mode, ip_address, port, status
        ) VALUES (
            p_gym_id, COALESCE(p_device_name, 'Main Gate Face Terminal'), v_clean_sn,
            COALESCE(p_brand, 'eSSL'), COALESCE(p_category, 'face'),
            COALESCE(p_mode, 'cloud_adms'), p_ip, COALESCE(p_port, 4370), 'offline'
        )
        RETURNING id INTO v_target_id;
    END IF;

    -- Auto-enable biometric attendance for gym if not already enabled
    UPDATE gyms 
    SET biometric_attendance_enabled = true 
    WHERE id = p_gym_id AND biometric_attendance_enabled = false;

    RETURN jsonb_build_object(
        'success', true, 
        'device_id', v_target_id,
        'message', 'Device paired successfully!'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RPC: Delete Biometric Device
CREATE OR REPLACE FUNCTION delete_gym_biometric_device(
    p_gym_id UUID,
    p_device_id UUID
)
RETURNS JSONB AS $$
BEGIN
    IF auth.uid() IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM user_gym_associations 
            WHERE gym_id = p_gym_id AND user_id = auth.uid() AND lower(role) IN ('owner', 'admin')
        ) AND NOT EXISTS (
            SELECT 1 FROM gyms WHERE id = p_gym_id AND owner_id = auth.uid()
        ) AND NOT is_super_admin(auth.uid()) THEN
            RAISE EXCEPTION 'Unauthorized';
        END IF;
    END IF;

    DELETE FROM gym_biometric_devices 
    WHERE id = p_device_id AND gym_id = p_gym_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. RPC: Auto-assign Next Free Biometric / Face PIN (e.g. 101, 102...)
CREATE OR REPLACE FUNCTION get_next_available_biometric_pin(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_max_member_pin INT;
    v_max_staff_pin INT;
    v_next_pin INT;
BEGIN
    SELECT COALESCE(MAX(biometric_pin), 100) INTO v_max_member_pin 
    FROM members 
    WHERE gym_id = p_gym_id;

    SELECT COALESCE(MAX(biometric_pin), 100) INTO v_max_staff_pin 
    FROM staff 
    WHERE gym_id = p_gym_id;

    v_next_pin := GREATEST(v_max_member_pin, v_max_staff_pin) + 1;
    IF v_next_pin < 101 THEN
        v_next_pin := 101;
    END IF;

    RETURN jsonb_build_object('success', true, 'next_pin', v_next_pin);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. RPC: Enqueue Full Gym Member Biometric Sync (1-Tap Machine Pre-provisioning)
CREATE OR REPLACE FUNCTION enqueue_full_gym_member_biometric_sync(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_rec RECORD;
    v_enqueued_count INT := 0;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM user_gym_associations 
            WHERE gym_id = p_gym_id AND user_id = auth.uid() AND lower(role) IN ('owner', 'admin')
        ) AND NOT EXISTS (
            SELECT 1 FROM gyms WHERE id = p_gym_id AND owner_id = auth.uid()
        ) AND NOT is_super_admin(auth.uid()) THEN
            RAISE EXCEPTION 'Unauthorized';
        END IF;
    END IF;

    FOR v_rec IN 
        SELECT m.id, m.name, m.biometric_pin, m.status, MAX(mm.end_date) AS expiry_date
        FROM members m
        LEFT JOIN member_memberships mm ON mm.member_id = m.id
        WHERE m.gym_id = p_gym_id AND m.biometric_pin IS NOT NULL
        GROUP BY m.id, m.name, m.biometric_pin, m.status
    LOOP
        INSERT INTO biometric_sync_queue (
            gym_id, member_id, biometric_pin, user_name, role,
            command_type, expiry_date, is_access_allowed, sync_status
        ) VALUES (
            p_gym_id, v_rec.id, v_rec.biometric_pin, v_rec.name, 'member',
            'SET_USER', v_rec.expiry_date,
            (lower(COALESCE(v_rec.status, '')) = 'active' AND (v_rec.expiry_date IS NULL OR v_rec.expiry_date >= CURRENT_DATE)),
            'pending'
        );
        v_enqueued_count := v_enqueued_count + 1;
    END LOOP;

    RETURN jsonb_build_object('success', true, 'enqueued_count', v_enqueued_count);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. RPC: Get Unlinked Punches for Gym Owner Discovery
CREATE OR REPLACE FUNCTION get_unlinked_biometric_punches(p_gym_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_punches JSONB;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM user_gym_associations 
            WHERE gym_id = p_gym_id AND user_id = auth.uid() AND lower(role) IN ('owner', 'admin')
        ) AND NOT EXISTS (
            SELECT 1 FROM gyms WHERE id = p_gym_id AND owner_id = auth.uid()
        ) AND NOT is_super_admin(auth.uid()) THEN
            RAISE EXCEPTION 'Unauthorized';
        END IF;
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', id,
        'biometric_pin', biometric_pin,
        'punch_time', punch_time,
        'verify_mode', verify_mode,
        'punch_count', punch_count,
        'last_seen_at', last_seen_at
    ) ORDER BY last_seen_at DESC), '[]'::jsonb)
    INTO v_punches
    FROM unlinked_biometric_punches
    WHERE gym_id = p_gym_id;

    RETURN jsonb_build_object('success', true, 'unlinked_punches', v_punches);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. RPC: Link Biometric PIN to Member (1-Tap Association from App)
CREATE OR REPLACE FUNCTION link_biometric_pin_to_member(
    p_gym_id UUID,
    p_member_id UUID,
    p_pin INT
)
RETURNS JSONB AS $$
DECLARE
    v_member RECORD;
    v_latest_end DATE;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM user_gym_associations 
            WHERE gym_id = p_gym_id AND user_id = auth.uid() AND lower(role) IN ('owner', 'admin')
        ) AND NOT EXISTS (
            SELECT 1 FROM gyms WHERE id = p_gym_id AND owner_id = auth.uid()
        ) AND NOT is_super_admin(auth.uid()) THEN
            RAISE EXCEPTION 'Unauthorized';
        END IF;
    END IF;

    -- Update member's PIN
    UPDATE members 
    SET biometric_pin = p_pin, biometric_sync_status = 'synced' 
    WHERE id = p_member_id AND gym_id = p_gym_id
    RETURNING id, name, status INTO v_member;

    IF v_member.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Member not found');
    END IF;

    -- Remove from unlinked discovery table
    DELETE FROM unlinked_biometric_punches 
    WHERE gym_id = p_gym_id AND biometric_pin = p_pin;

    -- Backfill any raw punches that had this PIN
    UPDATE biometric_punches_raw 
    SET member_id = p_member_id, processed_status = 'LINKED_RETROACTIVELY'
    WHERE gym_id = p_gym_id AND biometric_pin = p_pin AND member_id IS NULL;

    -- Get member expiry
    SELECT MAX(end_date) INTO v_latest_end 
    FROM member_memberships 
    WHERE member_id = p_member_id;

    -- Enqueue hardware delta sync
    INSERT INTO biometric_sync_queue (
        gym_id, member_id, biometric_pin, user_name, role,
        command_type, expiry_date, is_access_allowed, sync_status
    ) VALUES (
        p_gym_id, p_member_id, p_pin, v_member.name, 'member',
        'SET_USER', v_latest_end,
        (lower(COALESCE(v_member.status, '')) = 'active' AND (v_latest_end IS NULL OR v_latest_end >= CURRENT_DATE)),
        'pending'
    );

    RETURN jsonb_build_object('success', true, 'message', 'PIN successfully linked to ' || v_member.name);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. RPC: Get Recent Biometric Punches for Live Stream (with Face Scan badges)
CREATE OR REPLACE FUNCTION get_recent_biometric_punches(
    p_gym_id UUID,
    p_limit INT DEFAULT 20
)
RETURNS JSONB AS $$
DECLARE
    v_punches JSONB;
BEGIN
    IF auth.uid() IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM user_gym_associations 
            WHERE gym_id = p_gym_id AND user_id = auth.uid() AND lower(role) IN ('owner', 'admin')
        ) AND NOT EXISTS (
            SELECT 1 FROM gyms WHERE id = p_gym_id AND owner_id = auth.uid()
        ) AND NOT is_super_admin(auth.uid()) THEN
            RAISE EXCEPTION 'Unauthorized';
        END IF;
    END IF;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', b.id,
        'biometric_pin', b.biometric_pin,
        'punch_time', b.punch_time,
        'punch_type', b.punch_type,
        'processed_status', b.processed_status,
        'member_name', COALESCE(m.name, s.name, 'Unlinked User (#' || b.biometric_pin || ')'),
        'role', CASE WHEN m.id IS NOT NULL THEN 'member' WHEN s.id IS NOT NULL THEN 'staff' ELSE 'unlinked' END,
        'is_face_scan', true
    ) ORDER BY b.punch_time DESC), '[]'::jsonb)
    INTO v_punches
    FROM (
        SELECT id, biometric_pin, punch_time, punch_type, processed_status, member_id, staff_id
        FROM biometric_punches_raw
        WHERE gym_id = p_gym_id
        ORDER BY punch_time DESC
        LIMIT LEAST(p_limit, 50)
    ) b
    LEFT JOIN members m ON m.id = b.member_id
    LEFT JOIN staff s ON s.id = b.staff_id;

    RETURN jsonb_build_object('success', true, 'punches', v_punches);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 11. RPC: High-Performance ADMS Direct Punch Ingestion (Zero-Collision Strict Isolation)
CREATE OR REPLACE FUNCTION process_adms_punch(
    p_device_serial VARCHAR,
    p_pin INT,
    p_punch_time TIMESTAMPTZ,
    p_verify_mode VARCHAR DEFAULT 'face'
)
RETURNS JSONB AS $$
DECLARE
    v_device RECORD;
    v_member RECORD;
    v_staff RECORD;
    v_today_str TEXT;
    v_inserted_raw_id UUID;
    v_expiry_date DATE;
    v_is_expired BOOLEAN := false;
    v_existing_attendance RECORD;
BEGIN
    -- 1. Strictly resolve Gym by Device Serial Number
    SELECT id, gym_id, status 
    INTO v_device
    FROM gym_biometric_devices
    WHERE device_serial_number = trim(p_device_serial);

    IF v_device.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unregistered device serial number');
    END IF;

    -- Update device activity
    UPDATE gym_biometric_devices 
    SET last_heartbeat = NOW(), 
        last_punch_at = NOW(), 
        status = 'online',
        total_punches_synced = COALESCE(total_punches_synced, 0) + 1
    WHERE id = v_device.id;

    v_today_str := to_char(p_punch_time AT TIME ZONE 'Asia/Kolkata', 'YYYY-MM-DD');

    -- 2. Insert into raw punches buffer (idempotent)
    BEGIN
        INSERT INTO biometric_punches_raw (
            gym_id, biometric_pin, punch_time, punch_type, device_id, processed_status
        ) VALUES (
            v_device.gym_id, p_pin, p_punch_time, 'auto', v_device.id, 'PENDING'
        ) RETURNING id INTO v_inserted_raw_id;
    EXCEPTION WHEN unique_violation THEN
        RETURN jsonb_build_object('success', true, 'status', 'DUPLICATE_IGNORED');
    END;

    -- 3. Resolve Member in this SPECIFIC gym only (Strict Multi-Tenant Isolation!)
    SELECT id, name, status 
    INTO v_member 
    FROM members 
    WHERE gym_id = v_device.gym_id AND biometric_pin = p_pin;

    IF v_member.id IS NOT NULL THEN
        SELECT MAX(end_date) INTO v_expiry_date 
        FROM member_memberships 
        WHERE member_id = v_member.id;

        v_is_expired := (v_expiry_date IS NOT NULL AND v_expiry_date < (p_punch_time AT TIME ZONE 'Asia/Kolkata')::DATE);

        UPDATE biometric_punches_raw 
        SET member_id = v_member.id,
            processed_status = CASE WHEN v_is_expired THEN 'EXPIRED_ATTENDANCE' ELSE 'SUCCESS' END 
        WHERE id = v_inserted_raw_id;

        -- Record Attendance Log
        SELECT id, check_in, check_out 
        INTO v_existing_attendance 
        FROM attendance_logs 
        WHERE gym_id = v_device.gym_id 
          AND member_id = v_member.id 
          AND date = v_today_str;

        IF v_existing_attendance.id IS NULL THEN
            INSERT INTO attendance_logs (
                gym_id, user_id, member_id, role, user_type, name,
                date, check_in, status, method, created_at
            ) VALUES (
                v_device.gym_id, v_member.id, v_member.id, 'member', 'member', v_member.name,
                v_today_str, p_punch_time, 'present', 'biometric', NOW()
            );
        ELSE
            IF p_punch_time > (v_existing_attendance.check_in + INTERVAL '5 minutes') THEN
                UPDATE attendance_logs 
                SET check_out = p_punch_time,
                    working_minutes = ROUND(EXTRACT(EPOCH FROM (p_punch_time - v_existing_attendance.check_in)) / 60)
                WHERE id = v_existing_attendance.id;
            END IF;
        END IF;

        RETURN jsonb_build_object('success', true, 'name', v_member.name, 'is_expired', v_is_expired);
    END IF;

    -- 4. Check Staff in this gym
    SELECT id, name, role 
    INTO v_staff 
    FROM staff 
    WHERE gym_id = v_device.gym_id AND biometric_pin = p_pin;

    IF v_staff.id IS NOT NULL THEN
        UPDATE biometric_punches_raw 
        SET staff_id = v_staff.id, processed_status = 'SUCCESS' 
        WHERE id = v_inserted_raw_id;

        SELECT id, check_in, check_out 
        INTO v_existing_attendance 
        FROM attendance_logs 
        WHERE gym_id = v_device.gym_id 
          AND staff_id = v_staff.id 
          AND date = v_today_str;

        IF v_existing_attendance.id IS NULL THEN
            INSERT INTO attendance_logs (
                gym_id, user_id, staff_id, role, user_type, name,
                date, check_in, status, method, created_at
            ) VALUES (
                v_device.gym_id, v_staff.id, v_staff.id, 'staff', 'staff', v_staff.name,
                v_today_str, p_punch_time, 'present', 'biometric', NOW()
            );
        ELSE
            IF p_punch_time > (v_existing_attendance.check_in + INTERVAL '5 minutes') THEN
                UPDATE attendance_logs 
                SET check_out = p_punch_time,
                    working_minutes = ROUND(EXTRACT(EPOCH FROM (p_punch_time - v_existing_attendance.check_in)) / 60)
                WHERE id = v_existing_attendance.id;
            END IF;
        END IF;

        RETURN jsonb_build_object('success', true, 'name', v_staff.name, 'role', 'staff');
    END IF;

    -- 5. Unlinked User: Record in Discovery Table for Owner
    INSERT INTO unlinked_biometric_punches (
        gym_id, device_id, biometric_pin, punch_time, verify_mode, punch_count, last_seen_at
    ) VALUES (
        v_device.gym_id, v_device.id, p_pin, p_punch_time, p_verify_mode, 1, NOW()
    )
    ON CONFLICT (gym_id, biometric_pin) 
    DO UPDATE SET 
        punch_count = unlinked_biometric_punches.punch_count + 1,
        last_seen_at = NOW();

    UPDATE biometric_punches_raw 
    SET processed_status = 'UNLINKED_DISCOVERY' 
    WHERE id = v_inserted_raw_id;

    RETURN jsonb_build_object('success', true, 'status', 'UNLINKED_DISCOVERY', 'pin', p_pin);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 12. RPC: Poll Delta Commands for Machine (Device SN Bound)
CREATE OR REPLACE FUNCTION poll_adms_commands(p_device_serial VARCHAR)
RETURNS JSONB AS $$
DECLARE
    v_device RECORD;
    v_commands JSONB;
BEGIN
    SELECT id, gym_id INTO v_device 
    FROM gym_biometric_devices 
    WHERE device_serial_number = trim(p_device_serial);

    IF v_device.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unregistered device');
    END IF;

    -- Update heartbeat
    UPDATE gym_biometric_devices 
    SET last_heartbeat = NOW(), status = 'online' 
    WHERE id = v_device.id;

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
    WHERE gym_id = v_device.gym_id AND sync_status = 'pending'
    LIMIT 50;

    RETURN jsonb_build_object(
        'success', true,
        'gym_id', v_device.gym_id,
        'commands', v_commands
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 13. RPC: Acknowledge Delta Commands
CREATE OR REPLACE FUNCTION ack_adms_commands(
    p_device_serial VARCHAR,
    p_command_ids UUID[]
)
RETURNS JSONB AS $$
DECLARE
    v_device RECORD;
BEGIN
    SELECT id, gym_id INTO v_device 
    FROM gym_biometric_devices 
    WHERE device_serial_number = trim(p_device_serial);

    IF v_device.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unregistered device');
    END IF;

    UPDATE biometric_sync_queue 
    SET sync_status = 'synced', synced_at = NOW() 
    WHERE gym_id = v_device.gym_id AND id = ANY(p_command_ids);

    RETURN jsonb_build_object('success', true, 'acked_count', array_length(p_command_ids, 1));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
