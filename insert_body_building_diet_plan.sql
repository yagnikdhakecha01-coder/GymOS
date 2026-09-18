-- =========================================================================
-- Insert Body Building Diet Plan for Apex Premium GYM
-- =========================================================================

INSERT INTO public.fitness_goals (
    id,
    gym_id,
    name,
    icon,
    color,
    description,
    created_at
)
VALUES (
    'g_5_f896e071-c136-458a-842c-5e171b746f96',
    'f896e071-c136-458a-842c-5e171b746f96',
    'Body Building',
    '🏋️',
    '0xFFF59E0B',
    'Build maximum muscle mass and strength',
    NOW()
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.diet_plans (
    id,
    gym_id,
    title,
    description,
    goal,
    calories,
    calories_goal,
    protein_goal,
    carbs_goal,
    fat_goal,
    status,
    notes,
    meals,
    created_at
)
VALUES (
    gen_random_uuid(),
    'f896e071-c136-458a-842c-5e171b746f96',
    'Body Building',
    'High-Protein Muscle Building Diet Plan (~2500 kcal, ~125g Protein)',
    'Body Building',
    2500,
    2500,
    125,
    310,
    72,
    'Active',
    '💪 Best Vegetarian Protein Sources:
• Soya chunks (very high protein: ~52g per 100g)
• Paneer & Tofu
• Milk & curd
• Dal, rajma, chana
• Roasted chana
• Peanut butter, nuts & seeds

💧 Water: Drink 3.5 to 4 liters daily.
😴 Sleep: 7–8 hours of sound sleep is required for muscle hypertrophy.',
    '[
      {
        "name": "Early Morning",
        "time": "6:00 AM – 7:00 AM",
        "items": "1 glass warm water + 5–6 soaked almonds + 2 walnuts + 1 banana (if morning training)"
      },
      {
        "name": "Breakfast",
        "time": "8:00 AM – 9:00 AM",
        "items": "Choose one: Oats + milk + peanut butter + seeds / Vegetable upma + curd / Paneer paratha (light oil) + curd (Protein: ~20–25g)"
      },
      {
        "name": "Mid-Morning",
        "time": "11:00 AM",
        "items": "1 fruit (banana / apple / papaya) + 1 glass buttermilk or milk"
      },
      {
        "name": "Lunch",
        "time": "1:00 PM – 2:00 PM",
        "items": "2–3 chapati or rice + 1 bowl dal / rajma / chana + 1 bowl sabzi + Salad + Curd (Protein: ~20–25g)"
      },
      {
        "name": "Pre-Workout Snack",
        "time": "4:30 PM – 5:00 PM",
        "items": "Banana with peanut butter OR boiled corn / sweet potato (Energy for workout)"
      },
      {
        "name": "Post-Workout",
        "time": "Within 30 mins after workout",
        "items": "Choose one: 1 glass milk OR Paneer (50–100g) OR Roasted chana + Curd (Protein: ~15–25g)"
      },
      {
        "name": "Dinner",
        "time": "8:00 PM – 8:30 PM",
        "items": "2 chapati + Paneer / Soya chunks (soya) / Dal + Vegetables (Protein: ~20–25g)"
      },
      {
        "name": "Before Bed",
        "time": "10:00 PM",
        "items": "1 glass warm milk (slow-digesting casein protein for overnight muscle repair)"
      }
    ]'::jsonb,
    NOW()
);
