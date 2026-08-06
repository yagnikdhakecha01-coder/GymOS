-- ============================================================================
-- GYMOS BACKEND SYSTEM - OWNER BROADCAST ANNOUNCEMENTS & NOTIFICATIONS TRIGGER
-- ============================================================================

-- 1. Ensure target_role, audience, and gym_id columns exist in announcements & notifications
ALTER TABLE public.announcements 
  ADD COLUMN IF NOT EXISTS target_role VARCHAR(50) DEFAULT 'Both',
  ADD COLUMN IF NOT EXISTS audience VARCHAR(100) DEFAULT 'Both (Staff & Members)';

ALTER TABLE public.notifications 
  ADD COLUMN IF NOT EXISTS user_id UUID,
  ADD COLUMN IF NOT EXISTS target_role VARCHAR(50) DEFAULT 'Both',
  ADD COLUMN IF NOT EXISTS type VARCHAR(50) DEFAULT 'announcement',
  ADD COLUMN IF NOT EXISTS is_read BOOLEAN DEFAULT false;

-- 2. Create Trigger Function for Automatic Broadcast Notification Fan-Out
CREATE OR REPLACE FUNCTION public.fn_on_announcement_broadcast()
RETURNS TRIGGER AS $$
DECLARE
  v_aud TEXT;
  v_gym_id UUID;
  v_title TEXT;
  v_body TEXT;
BEGIN
  v_gym_id := NEW.gym_id;
  v_title  := COALESCE(NEW.title, '📢 New Announcement');
  v_body   := COALESCE(NEW.message, NEW.title, '');
  v_aud    := LOWER(COALESCE(NEW.audience, NEW.target_role, 'both'));

  -- A. Target Members if audience is 'Members' or 'Both'
  IF v_aud LIKE '%member%' OR v_aud LIKE '%both%' OR v_aud = 'all' THEN
    BEGIN
      INSERT INTO public.notifications (gym_id, user_id, target_role, title, body, type, is_read)
      SELECT 
        v_gym_id,
        m.user_id,
        'Member',
        '📢 ' || v_title,
        v_body,
        'announcement',
        false
      FROM public.members m
      WHERE m.gym_id = v_gym_id AND m.user_id IS NOT NULL;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Error fanning out member broadcast notifications: %', SQLERRM;
    END;
  END IF;

  -- B. Target Staff if audience is 'Staff' or 'Both'
  IF v_aud LIKE '%staff%' OR v_aud LIKE '%both%' OR v_aud = 'all' THEN
    BEGIN
      INSERT INTO public.notifications (gym_id, user_id, target_role, title, body, type, is_read)
      SELECT 
        v_gym_id,
        s.user_id,
        'Staff',
        '📢 ' || v_title,
        v_body,
        'announcement',
        false
      FROM public.staff s
      WHERE s.gym_id = v_gym_id AND s.user_id IS NOT NULL;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Error fanning out staff broadcast notifications: %', SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3. Drop existing trigger if present and re-attach
DROP TRIGGER IF EXISTS trg_on_announcement_broadcast ON public.announcements;

CREATE TRIGGER trg_on_announcement_broadcast
  AFTER INSERT ON public.announcements
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_on_announcement_broadcast();
