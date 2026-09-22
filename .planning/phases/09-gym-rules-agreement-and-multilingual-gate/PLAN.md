# Phase 09: Gym Rules & Multilingual Agreement Gate (English, Hindi, Gujarati), Owner Customization, and Audit History

## Goal
Implement a mandatory Gym Rules & Agreement popup/screen for gym members with:
1. **Mandatory Agreement Gate**: Member cannot access or use the app without agreeing to the gym rules.
2. **Detailed Rules & Sub-rules**: High-clarity, formatted rules covering injury liability, strict no-refund policy, non-transferable membership, equipment etiquette, gym timings, and decorum.
3. **3 Languages Support**: Dropdown selector supporting English (default), Hindi (हिंदी), and Gujarati (ગુજરાતી).
4. **Owner Customization**: Gym owners can customize rules for their gym from Gym Settings.
5. **Audit Trail & History**: Complete tracking of which user/member agreed to which gym's rules, when (timestamp), and in what language. Accessible to Member, Owner/Staff, and Super Admin.
6. **Cross-Device Responsive UI**: Responsive design looking sharp on mobile, tablet, and desktop web. Run on web for user inspection.

## Proposed Architecture & Changes

### 1. Database Layer (`add_gym_rules_and_agreements.sql`)
- Create `gym_rules` table for gym-specific custom rules and versions.
- Create `member_rule_agreements` table for audit log of accepted agreements with unique constraint on `(gym_id, member_id, rules_version)`.
- Configure RLS policies allowing members to record their agreements and gym owners/staff to query their gym's records.

### 2. Models & Built-in Multilingual Rules (`lib/core/models/gym_rules_model.dart`)
- Define `GymRuleItem`, `GymRulesData`, `MemberAgreementRecord`.
- Provide default translations for English, Hindi, and Gujarati for all default gym rules.

### 3. Member App Agreement Gate (`lib/features/member_app/`)
- `MemberRulesAgreementDialog`: Non-dismissible dialog/screen with language switcher, rule cards, checkboxes, and "Accept & Continue" button.
- `MemberAppViewModel`: Check agreement status on launch; save agreement record to Supabase and local cache.
- `MemberProfileScreen`: Show "Gym Rules & Agreement" view with acceptance timestamp badge.

### 4. Owner & Staff Management (`lib/features/gym_settings/` & `lib/features/members/`)
- `GymRulesSettingsScreen`: Multi-tab interface in Gym Settings to edit rules and view the agreement audit log.
- `MemberProfileScreen`: Display member's agreement status badge ("Rules Agreed" or "Pending").

### 5. Web & Device Verification
- Launch app on Chrome (`flutter run -d chrome`).
- Validate responsive layout across mobile and desktop widths.
