-- ============================================================
-- GYMOS Member Features Migration — openGym Inspired
-- SAFE: Only ADD new tables. No existing tables are altered.
-- All tables use IF NOT EXISTS to be idempotent.
-- ============================================================

-- 1. Exercises Library (global + gym-custom)
CREATE TABLE IF NOT EXISTS exercises (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id        UUID REFERENCES gyms(id) ON DELETE CASCADE,  -- NULL = global built-in
  name          TEXT NOT NULL,
  muscle_group  TEXT NOT NULL,
  secondary_muscles TEXT[],
  equipment     TEXT DEFAULT 'Bodyweight',
  category      TEXT DEFAULT 'Strength',  -- Strength | Cardio | Stretching | Plyometric
  description   TEXT,
  tips          TEXT,
  is_timed      BOOLEAN DEFAULT false,   -- true = planks, wall-sits (log duration, not reps)
  is_bodyweight BOOLEAN DEFAULT false,
  created_at    TIMESTAMPTZ DEFAULT now()
);

-- RLS for exercises: owner/admin of gym can manage; anyone in gym can read
ALTER TABLE exercises ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "exercises_select" ON exercises;
CREATE POLICY "exercises_select" ON exercises
  FOR SELECT USING (
    gym_id IS NULL OR
    gym_id IN (
      SELECT id FROM gyms WHERE owner_id = auth.uid()
      UNION
      SELECT gym_id FROM staff WHERE user_id = auth.uid()
      UNION
      SELECT gym_id FROM members WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "exercises_manage" ON exercises;
CREATE POLICY "exercises_manage" ON exercises
  FOR ALL USING (
    gym_id IN (SELECT id FROM gyms WHERE owner_id = auth.uid())
  );

-- 2. Member Body Logs (weight, measurements)
CREATE TABLE IF NOT EXISTS member_body_logs (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id        UUID NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  member_id     TEXT NOT NULL,
  logged_date   DATE NOT NULL DEFAULT CURRENT_DATE,
  weight_kg     NUMERIC(5,2),
  body_fat_pct  NUMERIC(4,1),
  chest_cm      NUMERIC(5,1),
  waist_cm      NUMERIC(5,1),
  hips_cm       NUMERIC(5,1),
  arms_cm       NUMERIC(5,1),
  thighs_cm     NUMERIC(5,1),
  notes         TEXT,
  created_at    TIMESTAMPTZ DEFAULT now(),
  UNIQUE (member_id, logged_date)
);

ALTER TABLE member_body_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "body_logs_member_rw" ON member_body_logs;
CREATE POLICY "body_logs_member_rw" ON member_body_logs
  FOR ALL USING (
    member_id IN (
      SELECT id FROM members WHERE user_id = auth.uid()
    )
    OR gym_id IN (
      SELECT id FROM gyms WHERE owner_id = auth.uid()
      UNION
      SELECT gym_id FROM staff WHERE user_id = auth.uid()
    )
  );

-- Index for fast chart queries
CREATE INDEX IF NOT EXISTS idx_body_logs_member_date
  ON member_body_logs(member_id, logged_date DESC);

-- 3. Workout Goal Weight (target body weight per member)
CREATE TABLE IF NOT EXISTS member_fitness_goals (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id          UUID NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  member_id       TEXT NOT NULL UNIQUE,
  goal_type       TEXT DEFAULT 'Weight Loss',
  goal_weight_kg  NUMERIC(5,2),
  goal_body_fat   NUMERIC(4,1),
  weekly_gym_days INT DEFAULT 5,
  updated_at      TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE member_fitness_goals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "fitness_goals_rw" ON member_fitness_goals;
CREATE POLICY "fitness_goals_rw" ON member_fitness_goals
  FOR ALL USING (
    member_id IN (SELECT id FROM members WHERE user_id = auth.uid())
    OR gym_id IN (
      SELECT id FROM gyms WHERE owner_id = auth.uid()
      UNION
      SELECT gym_id FROM staff WHERE user_id = auth.uid()
    )
  )
  WITH CHECK (
    member_id IN (SELECT id FROM members WHERE user_id = auth.uid())
    OR gym_id IN (
      SELECT id FROM gyms WHERE owner_id = auth.uid()
      UNION
      SELECT gym_id FROM staff WHERE user_id = auth.uid()
    )
  );

-- 4. Guided Workout Sets Log (per-set tracking)
CREATE TABLE IF NOT EXISTS member_workout_sets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id          UUID NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  member_id       TEXT NOT NULL,
  session_date    DATE NOT NULL DEFAULT CURRENT_DATE,
  exercise_id     UUID REFERENCES exercises(id),
  exercise_name   TEXT NOT NULL,   -- denormalized so records survive exercise delete
  muscle_group    TEXT NOT NULL,
  set_number      INT NOT NULL DEFAULT 1,
  reps            INT,
  weight_kg       NUMERIC(6,2),
  duration_secs   INT,             -- for timed exercises
  rir             INT,             -- Reps In Reserve (optional effort metric)
  is_pr           BOOLEAN DEFAULT false,
  superset_group  TEXT,            -- non-null = belongs to a superset pair (e.g. 'A')
  created_at      TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE member_workout_sets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "workout_sets_member_rw" ON member_workout_sets;
CREATE POLICY "workout_sets_member_rw" ON member_workout_sets
  FOR ALL USING (
    member_id IN (SELECT id FROM members WHERE user_id = auth.uid())
    OR gym_id IN (
      SELECT id FROM gyms WHERE owner_id = auth.uid()
      UNION
      SELECT gym_id FROM staff WHERE user_id = auth.uid()
    )
  );

CREATE INDEX IF NOT EXISTS idx_workout_sets_member_date
  ON member_workout_sets(member_id, session_date DESC);
CREATE INDEX IF NOT EXISTS idx_workout_sets_exercise
  ON member_workout_sets(member_id, exercise_name, session_date DESC);

-- 5. Personal Records (PRs) — materialized best lifts per exercise
CREATE TABLE IF NOT EXISTS member_personal_records (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id          UUID NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  member_id       TEXT NOT NULL,
  exercise_name   TEXT NOT NULL,
  best_weight_kg  NUMERIC(6,2),
  best_reps       INT,
  best_duration   INT,             -- for timed exercises
  estimated_1rm   NUMERIC(6,2),   -- Epley formula: w * (1 + reps/30)
  achieved_date   DATE NOT NULL,
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE (member_id, exercise_name)
);

ALTER TABLE member_personal_records ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "prs_member_rw" ON member_personal_records;
CREATE POLICY "prs_member_rw" ON member_personal_records
  FOR ALL USING (
    member_id IN (SELECT id FROM members WHERE user_id = auth.uid())
    OR gym_id IN (
      SELECT id FROM gyms WHERE owner_id = auth.uid()
      UNION
      SELECT gym_id FROM staff WHERE user_id = auth.uid()
    )
  );

-- 6. Weekly Workout Schedule (per-member, per-day)
CREATE TABLE IF NOT EXISTS member_weekly_schedule (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gym_id          UUID NOT NULL REFERENCES gyms(id) ON DELETE CASCADE,
  member_id       TEXT NOT NULL,
  day_of_week     INT NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),  -- 1=Mon, 7=Sun
  muscle_group    TEXT,           -- e.g. 'Chest', 'Back', 'Legs'
  exercises       JSONB DEFAULT '[]'::jsonb,
  is_rest_day     BOOLEAN DEFAULT false,
  notes           TEXT,
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE (member_id, day_of_week)
);

ALTER TABLE member_weekly_schedule ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "weekly_schedule_rw" ON member_weekly_schedule;
CREATE POLICY "weekly_schedule_rw" ON member_weekly_schedule
  FOR ALL USING (
    member_id IN (SELECT id FROM members WHERE user_id = auth.uid())
    OR gym_id IN (
      SELECT id FROM gyms WHERE owner_id = auth.uid()
      UNION
      SELECT gym_id FROM staff WHERE user_id = auth.uid()
    )
  )
  WITH CHECK (
    member_id IN (SELECT id FROM members WHERE user_id = auth.uid())
    OR gym_id IN (
      SELECT id FROM gyms WHERE owner_id = auth.uid()
      UNION
      SELECT gym_id FROM staff WHERE user_id = auth.uid()
    )
  );

-- ============================================================
-- FUNCTION: Auto-calculate Estimated 1RM on set insert/update
-- Epley formula: 1RM = weight × (1 + reps/30), valid up to 12 reps
-- ============================================================
CREATE OR REPLACE FUNCTION fn_update_member_pr()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_1rm NUMERIC;
BEGIN
  -- Calculate 1RM (only for ≤12 reps, as per convention)
  IF NEW.reps IS NOT NULL AND NEW.weight_kg IS NOT NULL AND NEW.reps <= 12 AND NEW.reps > 0 THEN
    v_1rm := ROUND((NEW.weight_kg * (1.0 + NEW.reps::NUMERIC / 30.0))::NUMERIC, 1);
  END IF;

  -- Upsert PR record
  INSERT INTO member_personal_records (
    gym_id, member_id, exercise_name,
    best_weight_kg, best_reps, best_duration,
    estimated_1rm, achieved_date
  )
  VALUES (
    NEW.gym_id, NEW.member_id, NEW.exercise_name,
    NEW.weight_kg, NEW.reps, NEW.duration_secs,
    v_1rm, NEW.session_date
  )
  ON CONFLICT (member_id, exercise_name)
  DO UPDATE SET
    best_weight_kg  = GREATEST(EXCLUDED.best_weight_kg, member_personal_records.best_weight_kg),
    best_reps       = GREATEST(EXCLUDED.best_reps, member_personal_records.best_reps),
    best_duration   = GREATEST(EXCLUDED.best_duration, member_personal_records.best_duration),
    estimated_1rm   = GREATEST(EXCLUDED.estimated_1rm, member_personal_records.estimated_1rm),
    achieved_date   = CASE
                        WHEN EXCLUDED.best_weight_kg > member_personal_records.best_weight_kg
                        THEN EXCLUDED.achieved_date
                        ELSE member_personal_records.achieved_date
                      END,
    updated_at      = now();

  -- Mark the set as PR if weight beats previous best
  UPDATE member_workout_sets SET is_pr = true
  WHERE id = NEW.id
    AND NEW.weight_kg IS NOT NULL
    AND NEW.weight_kg >= (
      SELECT COALESCE(MAX(weight_kg), 0)
      FROM member_workout_sets
      WHERE member_id = NEW.member_id
        AND exercise_name = NEW.exercise_name
        AND id != NEW.id
    );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_pr ON member_workout_sets;
CREATE TRIGGER trg_member_pr
  AFTER INSERT ON member_workout_sets
  FOR EACH ROW EXECUTE FUNCTION fn_update_member_pr();

-- ============================================================
-- SEED: 40 Essential Exercises (global, gym_id = NULL)
-- ============================================================
INSERT INTO exercises (name, muscle_group, secondary_muscles, equipment, category, description, is_bodyweight, is_timed)
SELECT * FROM (VALUES
  ('Barbell Bench Press','Chest',ARRAY['Triceps','Front Delts'],'Barbell','Strength','Classic chest compound lift.', false, false),
  ('Dumbbell Fly','Chest',ARRAY['Front Delts'],'Dumbbells','Strength','Isolation movement for chest.', false, false),
  ('Push-Up','Chest',ARRAY['Triceps','Front Delts'],'Bodyweight','Strength','Classic bodyweight chest exercise.', true, false),
  ('Incline Barbell Press','Chest',ARRAY['Front Delts','Triceps'],'Barbell','Strength','Upper chest focused press.', false, false),
  ('Cable Crossover','Chest',ARRAY['Front Delts'],'Cable Machine','Strength','Cable fly variation for chest squeeze.', false, false),

  ('Pull-Up','Back',ARRAY['Biceps','Rear Delts'],'Bodyweight','Strength','Upper back compound pull.', true, false),
  ('Barbell Row','Back',ARRAY['Biceps','Rear Delts'],'Barbell','Strength','Horizontal pull for back thickness.', false, false),
  ('Lat Pulldown','Back',ARRAY['Biceps'],'Cable Machine','Strength','Cable lat pulldown for width.', false, false),
  ('Seated Cable Row','Back',ARRAY['Biceps','Traps'],'Cable Machine','Strength','Horizontal cable row for back.', false, false),
  ('Deadlift','Back',ARRAY['Glutes','Hamstrings','Traps'],'Barbell','Strength','Full body posterior chain compound.', false, false),

  ('Barbell Squat','Legs',ARRAY['Hamstrings','Glutes','Calves'],'Barbell','Strength','King of leg exercises.', false, false),
  ('Leg Press','Legs',ARRAY['Hamstrings','Glutes'],'Machine','Strength','Machine quad and glute press.', false, false),
  ('Romanian Deadlift','Legs',ARRAY['Glutes','Lower Back'],'Barbell','Strength','Hip hinge for hamstrings.', false, false),
  ('Walking Lunge','Legs',ARRAY['Glutes','Hamstrings'],'Bodyweight','Strength','Unilateral leg strength.', true, false),
  ('Leg Curl','Legs',ARRAY[],'Machine','Strength','Hamstring isolation machine.', false, false),
  ('Calf Raise','Legs',ARRAY[],'Machine','Strength','Calf isolation movement.', false, false),
  ('Leg Extension','Legs',ARRAY[],'Machine','Strength','Quad isolation machine.', false, false),

  ('Overhead Press','Shoulders',ARRAY['Triceps','Upper Traps'],'Barbell','Strength','Shoulder vertical press.', false, false),
  ('Dumbbell Lateral Raise','Shoulders',ARRAY[],'Dumbbells','Strength','Side delt isolation raise.', false, false),
  ('Face Pull','Shoulders',ARRAY['Rear Delts','External Rotators'],'Cable Machine','Strength','Rear delt and rotator cuff health.', false, false),
  ('Arnold Press','Shoulders',ARRAY['Triceps'],'Dumbbells','Strength','Full delt range dumbbell press.', false, false),
  ('Front Raise','Shoulders',ARRAY['Upper Chest'],'Dumbbells','Strength','Anterior delt isolation.', false, false),

  ('Barbell Curl','Arms',ARRAY['Brachialis'],'Barbell','Strength','Classic bicep mass builder.', false, false),
  ('Dumbbell Hammer Curl','Arms',ARRAY['Brachialis','Forearms'],'Dumbbells','Strength','Neutral grip bicep curl.', false, false),
  ('Tricep Pushdown','Arms',ARRAY[],'Cable Machine','Strength','Cable tricep isolation.', false, false),
  ('Skull Crusher','Arms',ARRAY[],'Barbell','Strength','Barbell tricep extension.', false, false),
  ('Concentration Curl','Arms',ARRAY[],'Dumbbells','Strength','Isolation curl on bench.', false, false),

  ('Plank','Core',ARRAY['Shoulders','Glutes'],'Bodyweight','Strength','Core stability isometric hold.', true, true),
  ('Crunch','Core',ARRAY[],'Bodyweight','Strength','Basic ab flexion exercise.', true, false),
  ('Hanging Leg Raise','Core',ARRAY[],'Bodyweight','Strength','Lower ab and hip flexor movement.', true, false),
  ('Russian Twist','Core',ARRAY[],'Bodyweight','Strength','Oblique rotational exercise.', true, false),
  ('Ab Wheel Rollout','Core',ARRAY['Lats','Shoulders'],'Ab Wheel','Strength','Full core anti-extension.', false, false),

  ('Treadmill Run','Cardio',ARRAY[],'Cardio','Cardio','Steady state cardio.', false, true),
  ('Jump Rope','Cardio',ARRAY['Calves','Shoulders'],'Jump Rope','Cardio','High intensity cardio.', false, true),
  ('Cycling','Cardio',ARRAY['Quads','Hamstrings'],'Cardio','Cardio','Low impact cardio.', false, true),
  ('Burpee','Cardio',ARRAY['Full Body'],'Bodyweight','Plyometric','Full body plyometric.', true, false),
  ('Box Jump','Legs',ARRAY['Glutes','Calves'],'Box','Plyometric','Explosive leg power.', true, false),

  ('Hip Thrust','Legs',ARRAY['Hamstrings'],'Barbell','Strength','Glute dominant hip extension.', false, false),
  ('Dumbbell Row','Back',ARRAY['Biceps'],'Dumbbells','Strength','One arm dumbbell row.', false, false),
  ('Chest Dip','Chest',ARRAY['Triceps','Front Delts'],'Bodyweight','Strength','Forward-leaning dip for chest.', true, false)
) AS t(name, muscle_group, secondary_muscles, equipment, category, description, is_bodyweight, is_timed)
WHERE NOT EXISTS (SELECT 1 FROM exercises WHERE gym_id IS NULL LIMIT 1);

-- ============================================================
-- VIEW: Member Workout Summary (muscle group volume by week)
-- ============================================================
CREATE OR REPLACE VIEW v_member_weekly_volume AS
SELECT
  member_id,
  gym_id,
  muscle_group,
  session_date,
  COUNT(*) AS total_sets,
  SUM(COALESCE(reps, 0)) AS total_reps,
  SUM(COALESCE(weight_kg * reps, duration_secs, 0)) AS volume_load
FROM member_workout_sets
GROUP BY member_id, gym_id, muscle_group, session_date;

-- ============================================================
-- RPC: Get member body log history (chart data)
-- ============================================================
CREATE OR REPLACE FUNCTION get_member_body_logs(
  p_member_id TEXT,
  p_gym_id UUID,
  p_days INT DEFAULT 90
)
RETURNS TABLE(
  logged_date DATE,
  weight_kg NUMERIC,
  body_fat_pct NUMERIC,
  chest_cm NUMERIC,
  waist_cm NUMERIC,
  arms_cm NUMERIC
)
LANGUAGE SQL
SECURITY DEFINER
STABLE
AS $$
  SELECT logged_date, weight_kg, body_fat_pct, chest_cm, waist_cm, arms_cm
  FROM member_body_logs
  WHERE member_id = p_member_id
    AND gym_id = p_gym_id
    AND logged_date >= CURRENT_DATE - p_days
  ORDER BY logged_date ASC;
$$;

-- ============================================================
-- RPC: Get member muscle activity heatmap (last N days)
-- ============================================================
CREATE OR REPLACE FUNCTION get_member_muscle_activity(
  p_member_id TEXT,
  p_days INT DEFAULT 30
)
RETURNS TABLE(
  muscle_group TEXT,
  total_sets INT,
  last_trained DATE
)
LANGUAGE SQL
SECURITY DEFINER
STABLE
AS $$
  SELECT
    muscle_group,
    COUNT(*)::INT AS total_sets,
    MAX(session_date) AS last_trained
  FROM member_workout_sets
  WHERE member_id = p_member_id
    AND session_date >= CURRENT_DATE - p_days
  GROUP BY muscle_group
  ORDER BY total_sets DESC;
$$;

-- ============================================================
-- RPC: Get activity heatmap data (attendance count per date)
-- ============================================================
CREATE OR REPLACE FUNCTION get_member_activity_heatmap(
  p_member_id TEXT,
  p_gym_id UUID,
  p_year INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INT
)
RETURNS TABLE(
  activity_date DATE,
  attendance_count INT,
  workout_completed BOOLEAN
)
LANGUAGE SQL
SECURITY DEFINER
STABLE
AS $$
  SELECT
    DATE(al.check_in) AS activity_date,
    COUNT(al.id)::INT AS attendance_count,
    BOOL_OR(COALESCE(wl.status = 'Completed', false)) AS workout_completed
  FROM attendance_logs al
  LEFT JOIN member_workout_logs wl
    ON wl.member_id = p_member_id
    AND DATE(wl.date) = DATE(al.check_in)
  WHERE al.gym_id = p_gym_id
    AND al.member_id = p_member_id
    AND EXTRACT(YEAR FROM al.check_in) = p_year
  GROUP BY DATE(al.check_in)
  ORDER BY activity_date;
$$;

-- Done!
SELECT 'GYMOS Member Features Migration completed successfully' AS status;
