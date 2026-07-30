# Implementation Plan - Production-Ready Backend Salary Advance Ledger & Calculation Redesign

## Goal Description
Redesign the Salary Advance system. Move all calculations (Total Advance Given, Recovered, Remaining, Net Salary) to the backend. Create a dedicated `salary_advance_ledger` table with support for multiple records, partial recovery, and a unified execution transaction on Pay Salary. Ensure the Flutter UI only displays backend calculations.

## User Review Required
> [!IMPORTANT]
> The database schema changes require running the provided SQL script in the Supabase SQL Editor. This script creates the new `salary_advance_ledger` table, registers SQL trigger functions, updates `vw_pending_salary_list` view, and sets up a robust RPC transaction structure `pay_salary_draft` to pay salary, transition ledger items to recovered status, and log audit/financial ledger updates atomically.

## Proposed Changes

### Backend Database Architecture
#### [NEW] [salary_advance_ledger.sql](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/salary_advance_ledger.sql)
A SQL script that defines the production-ready schema:
- Creates enum type `advance_status` with values: `Pending`, `Approved`, `Rejected`, `Given`, `Recovered` (if not exists, or alters table).
- Table `salary_advance_ledger` with primary key, foreign keys to `gyms`, `staff`, `salary_drafts` (specifically `salary_payment_id` referencing a paid draft transaction / salary payment), given_date, status, amounts, notes, reference number.
- Triggers on `salary_adjustments` to automatically update draft `net_salary`.
- Updated trigger `fn_calculate_salary_draft_totals()` to pull advances directly from `salary_advance_ledger` (summing up `remaining_amount` of active approved/given advances).
- Stored Procedure (RPC) `pay_salary_draft` that runs in a single transaction:
  1. Verifies draft state.
  2. Updates draft status to `'Paid'`.
  3. Inserts Expense record to `transactions` or `finance_transactions`.
  4. Marks matching `commission_ledger` entries as `'Paid'`.
  5. Performs partial or full recovery on active `salary_advance_ledger` rows (updating `recovered_amount` and `remaining_amount`, transitioning status to `'Recovered'` when fully paid).
  6. Saves Audit Log event.
  7. If any step fails, performs rollback.

### Flutter Implementation
#### [MODIFY] [salary_draft.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/core/models/salary_draft.dart)
Update `SalaryDraft` class to map additional backend properties if needed (it already maps `baseSalary`, `commissionAmount`, `advanceDeduction`, `netSalary`).

#### [MODIFY] [pay_salary_screen.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/features/staff/pay_salary_screen.dart)
- Replace UI calculation fallback with direct backend-mapped data from `_draft`.
- Add state variable `_advancesExpanded` and `_advancesList` to hold fetched detailed advance items.
- Render a new expandable section `ADVANCE SALARY` displaying:
  - Header badge: `Total Advance: ₹X`, `Recovered: ₹Y`, `Pending Recovery: ₹Z`.
  - Details list showing date, reason, amount, status for each ledger record.
  - Partial recovery support: Allow the user to input a recovery cap amount or let the backend recover up to `net_salary` automatically.

#### [MODIFY] [staff_viewmodel.dart](file:///c:/Users/jigar/OneDrive/Documents/GYMOS%20V1%20UI/lib/features/staff/staff_viewmodel.dart)
- Update `fetchSalaryAdvances` to query `salary_advance_ledger`.
- Ensure VM doesn't perform calculations.

## Verification Plan

### Automated/SQL Checks
- Run the SQL scripts in Supabase SQL editor.
- Insert test staff advances in `salary_advance_ledger`.
- Verify draft creation triggers correct `net_salary`.

### Manual Verification
- Open Pay Salary page, check if the calculated Net Salary equals `Fixed Salary + Commission + Adjustments - Pending Advances`.
- Check if advances list is displayed correctly inside the new expandable card.
- Perform a payment, verify all advances update status to `Recovered` or update `remaining_amount` on partial recovery in Supabase.
