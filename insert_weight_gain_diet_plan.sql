-- =========================================================================
-- Insert Weight Gain Diet Plan for Apex Premium GYM
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
    'Weight Gain',
    'Healthy Sugar-Free Calorie Surplus Diet Plan (~2600 kcal)',
    'Weight Gain',
    2600,
    2600,
    110,
    350,
    80,
    'Active',
    '🍀 Foods You SHOULD Eat (Sugar-Free Weight Gain):
• Milk, paneer, curd
• Nuts & dry fruits (almonds, walnuts, dates)
• Rice, roti, oats
• Dal, chana, rajma
• Banana, mango
• Pure ghee (small amount)

❌ Avoid:
• Sugar, sweets (mithai), bakery items
• Cold drinks, packaged juices',
    '[
      {
        "name": "Morning",
        "time": "Empty Stomach",
        "items": "1 glass warm water + 5 soaked almonds + 2 walnuts + 1 banana"
      },
      {
        "name": "Breakfast",
        "time": "8:00 AM – 9:00 AM",
        "items": "Choose one: Vegetable poha with peanuts / 2–3 eggs + brown bread / Oats with milk + dry fruits. Plus: 1 glass milk (no sugar)"
      },
      {
        "name": "Mid-Morning Snack",
        "time": "11:00 AM",
        "items": "Fruit (apple / banana / papaya) OR fresh coconut water"
      },
      {
        "name": "Lunch",
        "time": "1:00 PM – 2:00 PM",
        "items": "2–3 roti with ghee + Dal or rajma/chana + Paneer / Chicken + Salad + Curd"
      },
      {
        "name": "Evening Snack",
        "time": "4:00 PM – 5:00 PM",
        "items": "Choose one: Peanut butter sandwich / Roasted chana / Banana shake (no sugar, use dates if needed)"
      },
      {
        "name": "Dinner",
        "time": "8:00 PM – 9:00 PM",
        "items": "2–3 roti or rice + Dal + Sabzi + Paneer / Chicken"
      },
      {
        "name": "Before Sleep",
        "time": "10:00 PM",
        "items": "1 glass warm milk + 2 dates"
      }
    ]'::jsonb,
    NOW()
);
