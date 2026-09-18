-- =========================================================================
-- Insert Weight Loss Diet Plan for Apex Premium GYM
-- =========================================================================

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
    'Weight Loss',
    'Balanced Indian Weight Loss Diet Plan (~1500 kcal)',
    'Weight Loss',
    1500,
    1500,
    70,
    170,
    45,
    'Active',
    '❌ Foods to Avoid:
• Sugar, sweets, chocolate
• Cold drinks, packaged juices
• White bread, bakery items
• Fried food
• Too much rice

💧 Drink at least 3-4 liters of water daily.',
    '[
      {
        "name": "Morning",
        "time": "Empty Stomach",
        "items": "1 glass warm water with lemon OR jeera water (cumin soaked overnight) + 5–6 soaked almonds"
      },
      {
        "name": "Breakfast",
        "time": "8:00 AM – 9:00 AM",
        "items": "Choose one: Vegetable oats / 2 boiled eggs + 1 whole wheat toast / Poha with vegetables / 2 Besan chilla + mint chutney / Vegetable upma. Drink: Green tea or black tea without sugar"
      },
      {
        "name": "Mid-Morning Snack",
        "time": "11:00 AM",
        "items": "Choose one fruit: Apple / Papaya / Guava / Orange (Avoid: banana, mango, grapes if focusing on sugar control)"
      },
      {
        "name": "Lunch",
        "time": "1:00 PM – 2:00 PM",
        "items": "2 multigrain/whole wheat roti OR 1 bowl brown rice + 1 bowl dal or rajma/chana + 1 bowl green vegetables + Salad (cucumber, tomato, carrot) + 1 cup unsweetened curd"
      },
      {
        "name": "Evening Snack",
        "time": "4:00 PM – 5:00 PM",
        "items": "Choose one: Roasted chana / Handful of peanuts / Sprouts salad + Green tea"
      },
      {
        "name": "Dinner",
        "time": "7:00 PM – 8:00 PM",
        "items": "Light dinner: 1–2 roti + Vegetable sabzi + Paneer bhurji OR dal + Salad (Alternative: Vegetable soup + paneer/tofu)"
      }
    ]'::jsonb,
    NOW()
);
