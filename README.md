# PipPulse – Gold Signals App
## Project Reference, Database Baseline & Migration Roadmap

**Purpose:** Preserve a detailed record of the work completed, the database state inspected, decisions made, known compatibility issues, and the planned direction for PipPulse.

**Status:** Frontend rebuilt (v2) and restyled (v2.1). Step 1 database migration revised (rev 1.1) after an independent review, but **not yet confirmed executed**. Payments, admin dashboard and private images still to build.  
**Last updated:** 1 November 2026  
**Frontend file:** `index.html` inspected on 1 November 2026, replaced with a Supabase-connected v2, then restyled as v2.1 the same day (see Sections 14 and 16).

---

# 1. Project overview

PipPulse is a gold-trading signals application focused on **XAUUSD**. The intended product includes user accounts, signal publishing, free and premium access, payment submissions, administrator approval, and protected signal/chart content.

The application is hosted on Cloudflare Pages and uses Supabase for backend services.

## 1.1 Deployment details

| Item | Current value |
|---|---|
| Application | PipPulse – Gold Signals App |
| Cloudflare Pages URL | https://pippulse.pages.dev/ |
| GitHub repository | https://github.com/Pkay-Ent/pippulse |
| Main frontend file | `index.html` at repository root |
| Supabase project | `pippulse` |
| Supabase URL | `https://okuotuehtvsxtibjgjsi.supabase.co` |
| Supabase plan | Free |
| Compute | Nano |
| Region | Europe |
| Last reported health | Healthy |

Cloudflare Pages is configured to deploy from GitHub. Current build configuration: framework preset None, no build command, output directory `/`.

The correct frontend filename is lowercase `index.html`. An earlier uppercase `Index.html` caused a 404 because filename casing matters.

### Frontend deployment workflow

1. Edit `index.html` locally.
2. Commit and push changes to GitHub, or upload/replace files through GitHub's browser interface.
3. Cloudflare Pages detects the repository update and deploys.
4. Check the live site at `https://pippulse.pages.dev/`.

Do not remove or rename database fields until the current frontend has been inspected for dependencies.

---

# 2. Product goals and intended features

## 2.1 Authentication and profiles

- Email registration and login through Supabase Auth.
- Email confirmation enabled.
- A profile associated with each authenticated account.
- Intended profile information: display name, email, phone number, country.
- Roles distinguishing normal users and administrators.

## 2.2 Gold signal management

Administrators should be able to publish XAUUSD signals with:

- Symbol (currently expected to be `XAUUSD`).
- Direction (`BUY` or `SELL`).
- Entry price or entry zone.
- Stop loss.
- One or multiple take-profit levels.
- Confidence score.
- Notes or analysis.
- Optional chart/signal image.
- Status such as draft, published, closed, or cancelled.
- Creation and publication timestamps.

## 2.3 Free and premium access

The planned access model includes:

- A limited number of free signal unlocks per user. Section 3 implementation uses three free unique unlocks.
- Premium access while a valid subscription is active.
- Administrators have full access.
- Unlocks recorded per user and signal so the same signal is not counted repeatedly.
- Access enforced by the database, not merely by hiding content in the frontend.

## 2.4 Payments and subscriptions

The intended workflow includes:

- Monthly, five-month, and lifetime plans.
- Mobile Money and USDT payment methods.
- Users submit payment details and a transaction reference.
- Payments initially remain pending.
- An administrator reviews and approves or rejects each payment.
- Approval activates or extends the user's subscription.
- Rejected payment references may be reused; non-rejected references must be unique.

Plan prices were confirmed by the owner on 1 November 2026 (see Section 14.6). Payment instructions (Mobile Money numbers, account name, USDT wallet addresses) have **not** been entered yet; they will be stored in `app_settings` and entered by the administrator. Do not invent them.

## 2.5 Administrator functionality

The intended admin dashboard should support:

- Publishing and managing signals.
- Reviewing submitted payments.
- Approving or rejecting payments.
- Managing user access and subscriptions.
- Viewing relevant audit information.

---

# 3. Supabase project and authentication configuration

## 3.1 Supabase project

- Project name: `pippulse`
- Project URL: `https://okuotuehtvsxtibjgjsi.supabase.co`
- Plan: Free
- Compute: Nano
- Region: Europe
- Health: Healthy at last inspection

A publishable frontend key was previously supplied in the conversation. It is intentionally not reproduced here. Never put a Supabase `service_role` key, database password, or other secret in frontend code, GitHub, or this README.

## 3.2 Authentication settings inspected

| Setting | Observed configuration |
|---|---|
| Email provider | Enabled |
| New signups | Enabled |
| Email confirmation | Enabled |
| Manual account linking | Disabled |
| Anonymous sign-ins | Disabled |
| Site URL | `https://pippulse.pages.dev` |
| Redirect URL | `https://pippulse.pages.dev/**` |

It has not yet been confirmed whether the owner has registered a PipPulse account or whether an administrator role has been assigned.

---

# 4. Work completed so far

Database work was performed through **Supabase Dashboard → SQL Editor**, not through the Kali terminal.

The work proceeded in three SQL sections:

- **Section 1:** Extend the existing signals table.
- **Section 2:** Create subscriptions and payments tables.
- **Section 3:** Create signal unlock and access functions.

Sections 1 and 2 were confirmed successful by inspecting the resulting database. Section 3 was confirmed by inspecting routine names.

## 4.1 Section 1 — Signals table extension

The existing `public.signals` table was extended with:

| Column | Type | Purpose |
|---|---|---|
| `entry_low` | `NUMERIC` | Lower boundary of entry zone |
| `entry_high` | `NUMERIC` | Upper boundary of entry zone |
| `take_profits` | `NUMERIC[]` | Multiple take-profit levels |
| `confidence` | `INTEGER` | Signal confidence score |
| `image_path` | `TEXT` | Storage path for signal/chart image |
| `updated_at` | `TIMESTAMPTZ` | Last update timestamp |

Additional constraints created:

- `signals_confidence_range`
- `signals_entry_zone_valid`
- `signals_take_profits_valid`

The take-profit array validation checks that the array is non-null when required, has between 1 and 10 elements, is one-dimensional, contains no null values, and contains only positive values.

Indexes created:

- `signals_published_feed_idx`
- `signals_created_by_idx`
- `signals_status_updated_idx`

A data migration populated the new fields from original values where needed:

- `entry_low = entry_price`
- `entry_high = entry_price`
- `take_profits = ARRAY[take_profit]`
- `updated_at` initialized from `created_at` where needed.

The user inspected the table and confirmed all six added columns existed.

**Compatibility warning:** Original `entry_price` and `take_profit` columns still exist. Do not drop them until the frontend has been inspected, updated, and tested.

## 4.2 Section 2 — Subscriptions and payments tables

Two tables were created and verified.

### `public.subscriptions`

| Column | Type | Nullability/default |
|---|---|---|
| `id` | `UUID` | Primary key, default `gen_random_uuid()` |
| `user_id` | `UUID` | NOT NULL, references `auth.users(id)` |
| `plan` | `TEXT` | NOT NULL |
| `status` | `TEXT` | NOT NULL, default `'active'` |
| `starts_at` | `TIMESTAMPTZ` | NOT NULL, default `NOW()` |
| `expires_at` | `TIMESTAMPTZ` | Nullable |
| `created_at` | `TIMESTAMPTZ` | NOT NULL, default `NOW()` |
| `updated_at` | `TIMESTAMPTZ` | NOT NULL, default `NOW()` |

Known checks:

- `plan` is restricted to `monthly`, `five_month`, or `lifetime`.
- `status` is restricted to `active`, `expired`, or `cancelled`.

The existing Section 2 table does **not** have a unique constraint on `user_id`; multiple subscription rows per user are structurally possible.

### `public.payments`

| Column | Type | Nullability/default |
|---|---|---|
| `id` | `UUID` | Primary key, default `gen_random_uuid()` |
| `user_id` | `UUID` | NOT NULL, references `auth.users(id)` |
| `plan` | `TEXT` | NOT NULL |
| `amount` | `NUMERIC(12,2)` | NOT NULL, must be positive |
| `currency` | `TEXT` | NOT NULL |
| `payment_method` | `TEXT` | NOT NULL |
| `reference` | `TEXT` | NOT NULL |
| `status` | `TEXT` | NOT NULL, default `'pending'` |
| `admin_note` | `TEXT` | Nullable |
| `reviewed_by` | `UUID` | Nullable, references `profiles(id)` |
| `reviewed_at` | `TIMESTAMPTZ` | Nullable |
| `created_at` | `TIMESTAMPTZ` | NOT NULL, default `NOW()` |
| `updated_at` | `TIMESTAMPTZ` | NOT NULL, default `NOW()` |

Known checks:

- `plan`: `monthly`, `five_month`, or `lifetime`.
- `currency`: `GHS` or `USD`.
- `payment_method`: `momo` or `usdt`.
- `status`: `pending`, `activated`, or `rejected`.
- `amount` must be greater than zero.
- `reference` length must be between 3 and 150 characters.
- `admin_note` length is limited to 1000 characters.

Indexes:

- `payments_reference_unique_idx`: unique on `lower(trim(reference))` for rows whose status is not `rejected`.
- `payments_user_created_idx`
- `payments_status_created_idx`

**Compatibility warning:** Current payments table uses `admin_note`, `created_at`, and `updated_at`. It does not have the alternative script's `submitted_at` or `review_note` columns. It also requires `amount` and `payment_method` on inserts. New payment code must respect these columns or migrate them deliberately.

## 4.3 Section 3 — Signal unlock and access functions

Section 3 was confirmed by a routine inspection. These five functions exist:

| Function | Existence confirmed |
|---|---|
| `can_access_signal` | Yes |
| `get_signal_feed` | Yes |
| `has_active_subscription` | Yes |
| `is_admin` | Yes |
| `unlock_signal` | Yes |

Section 3 also created `public.signal_unlocks` to record a user's unlock of a particular signal.

The Section 3 access design includes:

- Admin access.
- Active subscription access.
- A limited free allowance of three unique signal unlocks.
- Per-user/per-signal unlock tracking.
- A feed function that reports whether the user has unlocked a signal.

**Function signature detail:** Section 3's `unlock_signal(UUID)` returns `JSONB`. The alternative V3.0 migration defines `unlock_signal(UUID)` as returning `VOID`. PostgreSQL does not allow changing a function's return type through `CREATE OR REPLACE FUNCTION` alone. A deliberate drop/recreate or compatible function design is required if changing this signature. The frontend must match the final function contract.

The existing zero-argument `get_signal_feed()` returns columns including `id`, `symbol`, `status`, `published_at`, and `unlocked`.

The alternative migration uses a different parameterized feed signature. Inspect frontend expectations before replacing it.

**Verification limitation:** The function-name inspection confirms the routines exist; it does not by itself prove every RLS policy, table grant, or access edge case is correct.

---

# 5. Database schema inspected

The following structures were directly inspected using `information_schema.columns`.

## 5.1 Current `public.profiles` columns

| Column | Type | Nullable |
|---|---|---|
| `id` | `UUID` | No |
| `display_name` | `TEXT` | Yes |
| `role` | `TEXT` | No |
| `created_at` | `TIMESTAMPTZ` | No |

Known original structure:

- `id` is the primary key and references `auth.users(id)` with `ON DELETE CASCADE`.
- `display_name` is optional and limited to 60 characters.
- `role` defaults to `user`.
- Allowed roles: `user`, `admin`.
- `created_at` defaults to `now()`.

The alternative V3 design proposes adding profile metadata such as email, phone, and country. Those fields have **not** yet been added.

## 5.2 Current `public.signals` columns

| Column | Type | Nullable |
|---|---|---|
| `id` | `UUID` | No |
| `symbol` | `TEXT` | No |
| `direction` | `TEXT` | No |
| `entry_price` | `NUMERIC` | No |
| `stop_loss` | `NUMERIC` | No |
| `take_profit` | `NUMERIC` | No |
| `status` | `TEXT` | No |
| `notes` | `TEXT` | Yes |
| `created_by` | `UUID` | Yes |
| `created_at` | `TIMESTAMPTZ` | No |
| `published_at` | `TIMESTAMPTZ` | Yes |
| `entry_low` | `NUMERIC` | Yes |
| `entry_high` | `NUMERIC` | Yes |
| `take_profits` | `ARRAY` | Yes |
| `confidence` | `INTEGER` | Yes |
| `image_path` | `TEXT` | Yes |
| `updated_at` | `TIMESTAMPTZ` | No |

Known original structure and constraints:

- `id` is a UUID primary key defaulting to `gen_random_uuid()`.
- `symbol` defaults to `XAUUSD`.
- `direction` is restricted to `BUY` or `SELL`.
- `entry_price`, `stop_loss`, and `take_profit` must be positive.
- `status` defaults to `draft` and allows `draft`, `published`, `closed`, or `cancelled`.
- `notes` is limited to 2000 characters.
- `created_by` defaults to `auth.uid()` and references `profiles(id)` with `ON DELETE SET NULL`.
- `created_at` defaults to `now()`.
- `published_at` is nullable.
- BUY/SELL price logic checks that take profit is on the profitable side of entry and stop loss.

**Migration warning:** Existing `entry_price` and `take_profit` columns are still NOT NULL. A frontend that inserts only `entry_low`/`entry_high`/`take_profits` will fail unless database defaults, insert logic, or a compatibility mechanism is provided.

---

# 6. Existing Row Level Security (RLS) policies

Policies were inspected with:

```sql
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname IN ('public', 'storage')
ORDER BY schemaname, tablename, policyname;
```

The query returned these policies.

## 6.1 `profiles`

### `Users can update their own profile`

- Command: `UPDATE`
- Role: `authenticated`
- USING: `id = auth.uid()`
- WITH CHECK: `id = auth.uid()`

### `Users can view their own profile`

- Command: `SELECT`
- Role: `authenticated`
- USING: user can view their own profile or `is_admin()` returns true.

## 6.2 `signals`

### `Admins can create signals`

- Command: `INSERT`
- Role: `authenticated`
- WITH CHECK: `is_admin()` and `created_by = auth.uid()`.

### `Admins can delete draft signals`

- Command: `DELETE`
- Role: `authenticated`
- USING: `is_admin()`, `status = 'draft'`, and `published_at IS NULL`.

### `Admins can update signals`

- Command: `UPDATE`
- Role: `authenticated`
- USING and WITH CHECK: `is_admin()`.

### `Users can view published signals`

- Command: `SELECT`
- Role: `authenticated`
- USING: published timestamp is not null and status is `published` or `closed`, OR `is_admin()`.

## 6.3 Important security finding

The existing `Users can view published signals` policy allows every authenticated user to select all published and closed signal rows. Since PostgreSQL combines permissive policies with OR logic, adding a narrower policy without removing or replacing this broad policy will not secure premium signal details.

This is a **known issue to fix** before launch.

The final access model must enforce free/premium rules at the database level, not only by hiding content in the frontend.

The migration must also inspect and rebuild policies carefully. Existing permissive policies can combine in ways that unintentionally grant access.

---

# 7. Supabase Storage inspection

Storage buckets were inspected with:

```sql
SELECT
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
FROM storage.buckets
ORDER BY name;
```

Result: **Success. No rows returned.**

This means no Supabase Storage buckets existed at the time of inspection.

The intended direction is to create a **private** bucket for signal/chart images, with controlled access. Storage object policies must ensure premium chart images cannot be retrieved by users who do not have access to the corresponding signal.

The policy inspection returned no rows for the `storage` schema. Since no buckets currently exist, storage access policies still need to be created and verified. Before changing storage policies later, inspect all existing `storage.objects` policies again so no unreviewed permissive policy remains.

---

# 8. Alternative V3.0 migration script reviewed but NOT executed

A more comprehensive V3.0 migration script was supplied for review. It was **not run** because it has compatibility issues with the database already created by Sections 1–3.

Its proposed features included:

- One transaction and a data-loss tripwire.
- A backup schema named `pippulse_backup` with snapshots of profiles and signals.
- Additional profile fields, including email, phone, and country.
- Auth-user triggers and profile backfill.
- A `signal_levels_valid()` validator.
- Migration from legacy `entry_price`/`take_profit` fields to entry-zone and multi-target fields.
- Removal of legacy signal columns.
- Signal immutability and delete-protection triggers.
- One subscription row per user.
- `signal_unlocks`.
- A parameterized `get_signal_feed`.
- Payment approval/rejection workflows.
- A pending-payment limit.
- Payment protection triggers.
- `app_settings`.
- `audit_log`.
- Storage bucket and object policies.
- Comprehensive RLS and grants.

The architecture is a useful foundation, but the script must be adapted to the actual current schema before execution.

## 8.1 Critical incompatibilities identified

### A. Subscriptions table mismatch

The current Section 2 table:

- Has an `id` primary key.
- Allows multiple rows per `user_id`.
- Uses `five_month` (underscore).
- Has `status`, `starts_at`, `expires_at`, `created_at`, and `updated_at`.

The alternative script expects one row per user and uses `five-month` (hyphen) in places. Its `ON CONFLICT(user_id)` logic cannot work until a unique constraint or index on `user_id` exists.

A data-preserving migration must decide whether to consolidate historical rows and how to represent active/expired subscriptions before enforcing one row per user. Plan naming must be standardized across database constraints, functions, and frontend.

### B. Payments table mismatch

The current payments table already has:

- `amount`
- `payment_method`
- `admin_note`
- `created_at`
- `updated_at`

It does not have:

- `submitted_at`
- `review_note`

The alternative script references columns that do not exist. Its payment insert grants also omit the currently required `amount` and `payment_method` columns, which would cause inserts to fail unless the design changes.

The final script should preserve current payment data and either use existing column names or explicitly migrate/rename/add columns in a compatible way.

### C. `unlock_signal` return type mismatch

Current Section 3: `unlock_signal(UUID) RETURNS JSONB`.

Alternative V3: `unlock_signal(UUID) RETURNS VOID`.

A return type change cannot be applied with `CREATE OR REPLACE FUNCTION` alone. The migration and frontend response handling must agree on one final signature.

### D. `get_signal_feed` signature mismatch

Current Section 3: zero-argument `get_signal_feed()`.

Alternative V3: parameterized feed function.

The existing function may need to be dropped and recreated, but only after confirming dependencies and frontend expectations.

### E. Signal legacy columns and frontend compatibility

The alternative script drops `entry_price` and `take_profit`. These fields still exist and are NOT NULL.

Dropping them before updating the frontend could break signal reads, inserts, updates, or older app code. Keep them during the compatibility phase. Remove them only after the frontend is updated and tested, or retain them as compatibility fields.

### F. Confidence type mismatch

Section 1 created `confidence INTEGER`. The alternative script attempts to add `confidence SMALLINT` with `IF NOT EXISTS`. Since the column already exists, it remains `INTEGER`. This is not inherently fatal, but the final design should intentionally accept the existing type or migrate it explicitly.

### G. Existing signal constraints

Section 1 created `signals_entry_zone_valid` and `signals_take_profits_valid`. The alternative script drops one of these but not necessarily the other. The final script should inspect and rationalize constraints rather than leave accidental duplicates or contradictory checks.

### H. Storage policy safety

The alternative script drops only selected storage policies. Any other permissive policies could remain and combine with new policies using OR logic. Inspect and deliberately replace or retain every relevant storage policy.

## 8.2 Other logic and security considerations

- The proposed `signal_levels_valid()` checks entry zone, stop loss, take-profit positivity, and target ordering. Its BUY/SELL rules should be reviewed against the intended trading convention.
- The proposed signal immutability trigger freezes key trade-plan fields after publication and restricts later status transitions. Confirm the intended edit policy for published signals and whether admins may correct a live signal.
- The proposed delete-protection trigger protects published signals. Confirm whether this should also apply to service-role operations.
- Payment approval should lock the payment row, verify the administrator, and safely activate or extend the subscription.
- The proposed monthly and five-month periods were 30 and 150 days respectively. Confirm those durations and plan naming before implementation.
- Payment references should remain unique after normalization for all non-rejected submissions.
- A pending-payment limit should be enforced server-side, not only in the UI.
- `app_settings` may contain payment instructions. Decide which settings are safe for all authenticated users to read and keep secrets out of client-readable settings.
- Audit logging is useful for administrator actions, payment review, subscription changes, and signal edits.
- Rebuilding all public-table policies will remove existing custom policies on those tables. This should be deliberate and documented.
- SECURITY DEFINER functions should use a safe fixed `search_path`, have appropriate execute grants, and not expose privileged operations to `PUBLIC` or `anon`.
- Column-level grants and triggers should prevent ordinary users from changing protected profile fields such as role.
- The final design should test RLS and storage access using actual user/admin sessions.

---

# 9. Current state: confirmed vs not yet confirmed

## 9.1 Confirmed completed

- [x] Cloudflare Pages site exists.
- [x] GitHub repository exists.
- [x] Supabase project exists and was healthy at last check.
- [x] Email authentication provider is enabled.
- [x] Email signups are enabled.
- [x] Email confirmation is enabled.
- [x] Site URL and redirect URL are configured.
- [x] Section 1 signal columns and constraints were created and inspected.
- [x] Section 2 subscriptions table was created and inspected.
- [x] Section 2 payments table was created and inspected.
- [x] Section 3 access functions were confirmed to exist.
- [x] Profiles and signals columns were inspected.
- [x] Existing public/storage RLS policies were inspected.
- [x] Storage buckets were inspected; none exist.

## 9.2 Not yet completed or not yet verified

- [x] Inspect the actual current `index.html` frontend. (Done 1 Nov 2026, Section 14.1)
- [ ] Confirm whether a PipPulse user account has been registered.
- [ ] Confirm or assign the intended administrator account safely.
- [ ] Inspect full table constraints, indexes, triggers, grants, and function definitions before final migration.
- [x] Inspect `signal_unlocks` columns, RLS and grants. (Done 1 Nov 2026; its constraints still to inspect)
- [x] Verify exact definitions and return types of all five Section 3 functions. (Done 1 Nov 2026, Section 14.2)
- [ ] Prepare a migration specifically compatible with the existing database. (Step 1 revision 1.1 written; Steps 2 and 3 pending; see Sections 14.3 and 16)
- [ ] Run the read-only pre-flight queries in `HANDOVER.md` (Step 0) and keep the output.
- [ ] Create and secure the private signal-image storage bucket.
- [ ] Replace the broad published-signal SELECT policy with the intended entitlement-based policy.
- [ ] Align database function signatures with the frontend.
- [ ] Implement/verify payment submission and admin review.
- [ ] Implement/verify subscription activation and expiration.
- [ ] Implement/verify audit logging and app settings.
- [ ] Test free-user, premium-user, admin, and unauthenticated access.
- [ ] Test signal publishing, unlocking, chart-image access, and payment approval.
- [ ] Only after compatibility testing, decide whether legacy signal columns can be removed.

---

# 10. Recommended migration strategy from this point

Do not execute the alternative V3.0 script as-is. Do not drop existing tables or legacy columns just to make the new script fit.

## Stage 1 — Frontend and schema compatibility review

1. Obtain and inspect the current `index.html`.
2. Identify every Supabase table, column, RPC function, and storage path used by the frontend.
3. Record exact expected request/response shapes.
4. Inspect full existing definitions of `signal_unlocks`, `is_admin`, `has_active_subscription`, `can_access_signal`, `get_signal_feed`, and `unlock_signal`.
5. Inspect triggers, indexes, constraints, grants, and table RLS settings.

**Exit condition:** We know exactly what the current frontend expects and what the database actually provides.

**Status (1 Nov 2026):** Complete. See Section 14.

## Stage 2 — Write a migration-safe database upgrade

1. Preserve all current tables and data.
2. Back up important rows before structural changes.
3. Standardize subscription plan identifiers without losing existing rows.
4. Adapt payment workflow to the existing payments schema.
5. Choose stable function signatures and align the frontend.
6. Add profile metadata safely.
7. Add or revise triggers and validators without duplicating existing ones.
8. Apply correct RLS policies and grants.
9. Preserve legacy signal columns during transition.
10. Use a transaction where practical and verify each migration step.

**Exit condition:** The upgraded schema is compatible with the frontend and enforces the intended access rules.

## Stage 3 — Storage and chart protection

1. Create a private bucket for signal images.
2. Define upload permissions for administrators.
3. Define read permissions based on signal entitlement.
4. Ensure storage object policies do not expose premium images.
5. Test access with free, premium, and admin accounts.

**Exit condition:** A user cannot retrieve a premium chart image without entitlement.

## Stage 4 — Frontend integration

1. Update registration/login and profile handling.
2. Update signal feed and unlock calls.
3. Update admin signal publishing.
4. Add payment submission and status display.
5. Add admin payment review.
6. Add subscription status and expiry handling.
7. Add secure chart-image display.

**Exit condition:** The live frontend works against the upgraded database without relying on hidden UI controls for security.

## Stage 5 — Testing and launch readiness

Test at least these cases:

| Test account | Expected behaviour |
|---|---|
| Logged-out visitor | Cannot access protected signal data |
| New free user | Can use the configured free unlock allowance |
| Free user after allowance | Cannot unlock additional paid signals |
| Active subscriber | Can access entitled premium signals |
| Expired subscriber | Loses subscription-based access |
| Administrator | Can manage signals and review payments |
| User A | Cannot read or modify User B's private profile/payment data |

Also test:

- BUY and SELL validation.
- Entry-zone and take-profit ordering.
- Draft-to-published transitions.
- Published signal edits and closure.
- Duplicate payment references.
- Rejected payment resubmission.
- Subscription expiry and renewal.
- Unauthorized RPC calls.
- Private image URL access and download behaviour.

**Exit condition:** All access, payment, signal, and storage tests pass.

## Stage 6 — Cleanup

Only after the new frontend is deployed and verified:

- Decide whether `entry_price` and `take_profit` are still needed.
- Remove obsolete functions, triggers, indexes, or policies only after checking dependencies.
- Remove redundant constraints.
- Update this README with the final schema and deployment details.

---

# 11. Operating notes and safety rules

1. **SQL goes in Supabase SQL Editor**, not the Kali terminal.
2. Copy only the SQL inside a code block; do not copy Markdown code fences.
3. Run one migration stage at a time and inspect the result before proceeding.
4. Do not run the unadapted alternative V3.0 script.
5. Do not drop legacy signal columns until the frontend is compatible.
6. Do not expose the Supabase service-role key or database password.
7. Do not rely on frontend hiding to protect premium data.
8. Do not assume a function or policy is correct merely because it exists.
9. Save a local copy of every migration SQL file and this README.
10. After each successful migration, record the exact SQL version, date, result, and any errors here.

---

# 12. Exact next action

**The next action is to run the Step 1 migration (revision 1.1), verify it, then deploy the v2.1 frontend and report the results.**

1. Run the Step 0 pre-flight queries in `HANDOVER.md` (read-only) and keep the output.
2. Run `pippulse_step1_migration.sql` (revision 1.1) in Supabase SQL Editor. It is one transaction, backs up all five data tables first, and rolls back by itself if a safety check fails. It is safe to run even if revision 1.0 was run before.
3. Run the verification queries in `HANDOVER.md`.
4. Only after step 3 passes: commit `index.html` (v2.1) to GitHub; Cloudflare Pages deploys it.
5. Register on the live site, confirm the email, then promote that account to administrator with the SQL line in Section 14.5.
6. Insert the four test signals (bottom of the SQL file) and run tests 1 to 11 in `HANDOVER.md`.
7. Record the outcome in Section 13 (change log) and send any errors for correction.

Only after Step 1 is confirmed do we build Drop 2 (payments, approvals, admin dashboard) and Drop 3 (private chart images).

---

# 13. Change log

| Date | Work performed | Result |
|---|---|---|
| 2026-11-01 | Reviewed PipPulse deployment and Supabase project baseline | Project details documented |
| 2026-11-01 | Inspected Section 1 signal extensions | New columns confirmed |
| 2026-11-01 | Inspected Section 2 subscriptions and payments | Both tables and actual columns confirmed |
| 2026-11-01 | Inspected Section 3 routine names | Five access functions confirmed |
| 2026-11-01 | Inspected profiles and signals columns | Existing and new fields documented |
| 2026-11-01 | Inspected public and storage RLS policies | Existing policy set documented; broad signal read policy flagged |
| 2026-11-01 | Inspected Supabase storage buckets | No buckets exist |
| 2026-11-01 | Reviewed alternative V3.0 migration script | Not executed; compatibility issues documented |
| 2026-11-01 | Inspected original `index.html` | Local-only prototype with no Supabase connection; critical issues documented (Section 14.1) |
| 2026-11-01 | Inspected live functions, triggers, policies, grants | Findings documented (Section 14.2) |
| 2026-11-01 | Wrote Step 1 migration (`pippulse_step1_migration.sql`) | Written; **not yet confirmed executed** |
| 2026-11-01 | Rebuilt `index.html` as v2 (Auth, profiles, feed, unlock) | Syntax-checked only; not yet deployed or tested live |
| 2026-11-01 | Owner confirmed plan prices | Section 14.6 |
| 2026-11-01 | Independent review of README, HANDOVER, SQL and frontend | Findings and resolutions in Section 16 |
| 2026-11-01 | Revised migration to rev 1.1 | Written; **not yet confirmed executed** |
| 2026-11-01 | Restyled frontend as v2.1 (price rail, error handling) | Written; not yet deployed or tested live |
| 2026-11-01 | Updated HANDOVER.md (pre-flight, four test signals, extra tests) | Done |

---

# 14. Session update: 1 November 2026

## 14.1 Original `index.html` inspection

The original frontend was a browser-only prototype. It had **no Supabase client and no database calls**. Accounts, passwords, signals, payments, settings and images were stored in `localStorage`, so nothing was shared between users or devices.

| Finding | Severity |
|---|---|
| No Supabase connection; the live site could not serve signals to anyone but the browser that created them | Critical |
| Admin passcode hardcoded in public JavaScript and printed on the admin login sheet | Critical |
| User passwords saved in plain text in `localStorage` | Critical |
| Locked signals only blurred with CSS; full content stayed in the page | Critical |
| Free-signal counter (`freeUsed`) never incremented, so the limit was never enforced | High |
| Payments and admin approvals stored locally, so approvals could not activate anyone else's account | High |
| Plan id `five-month` (database uses `five_month`); status values in capitals; numeric ids (database uses UUIDs); single text entry field (database needs numeric `entry_low`/`entry_high`) | Compatibility |
| Signup collected name, country and phone but `profiles` had no such columns | Compatibility |

## 14.2 Live database inspection (1 Nov 2026)

- Row Level Security is enabled on `profiles`, `signals`, `signal_unlocks`, `payments`, `subscriptions`.
- Triggers present: `on_auth_user_created` (on `auth.users`, runs `handle_new_user()`) and `signals_set_published_at` (runs `set_signal_published_at()`). The bodies of these two functions have **not** been read.
- All five access functions are `SECURITY DEFINER` with `search_path` set to empty, and use fully qualified names.
- `get_signal_feed()` returns only `id, symbol, status, published_at, unlocked`. It was left unchanged.
- `unlock_signal(uuid)` returns JSONB, has the free limit of **3** hardcoded, and uses an advisory lock per user.
- `has_active_subscription()` treats a row as active when `status = 'active'` and the plan is `lifetime` or `expires_at > now()`. Expiry therefore needs no scheduled job.
- `signal_unlocks` columns: `id`, `user_id`, `signal_id`, `unlocked_at`.
- `payments` and `subscriptions` have no policies and no SELECT/INSERT/UPDATE/DELETE grants for client roles (fully locked). Access will be added through functions.

Problems found:

1. The "Users can view published signals" policy let any signed-in user read every published signal in full.
2. `anon` and `authenticated` held TRUNCATE, REFERENCES and TRIGGER on `signal_unlocks`, `payments`, `subscriptions`.
3. `can_access_signal(user, signal)` and `has_active_subscription(user)` were callable by clients with any user id.
4. "Users can update their own profile" had no matching UPDATE grant, so it had no effect.
5. `signals.entry_price` and `signals.take_profit` are NOT NULL, so an insert using only the new fields would fail.

## 14.3 Step 1 migration (`pippulse_step1_migration.sql`)

**Status: written 1 Nov 2026. Not yet confirmed executed.** Record the run date and result here once done.

It is additive and runs in one transaction. It:

- Backs up `signals` and `profiles` into schema `pippulse_backup` (tables `signals_20261101`, `profiles_20261101`).
- Adds `email`, `phone`, `country` to `profiles` with length checks, and backfills email.
- Replaces `handle_new_user()` so signup copies name, phone and country from sign-up metadata. The role is never read from user input.
- Adds a `profiles_protect_role` trigger and a column-level grant so users can update only `display_name`, `phone`, `country`.
- Revokes TRUNCATE/REFERENCES/TRIGGER from client roles on the three locked tables.
- Adds trigger `signals_sync_legacy`, which fills `entry_price` (midpoint of the entry zone) and `take_profit` (first target) automatically.
- Adds `has_signal_access(uuid)` and `get_my_access()` (act only on the signed-in caller).
- Replaces the broad read policy with "Entitled users can view signals" (admin, or published/closed and unlocked/subscribed).
- Revokes client EXECUTE on internal functions; grants EXECUTE only to `authenticated` for `is_admin`, `get_signal_feed`, `unlock_signal`, `has_signal_access`, `get_my_access`.
- Creates `app_settings` (public text readable by everyone; other settings readable by signed-in users; only admins can write) and seeds `headline` and `description`.

Not changed: legacy signal columns, the signatures of `get_signal_feed()` and `unlock_signal(uuid)`, existing admin signal policies, and existing data.

Known assumption: the legacy BUY/SELL check constraints are evaluated against the midpoint of the entry zone and the first target. If a test insert is rejected, send the exact error.

**Revision 1.1 (1 Nov 2026)** keeps everything above and adds: backups of all five data tables and a locked backup schema; the signup function now never blocks signup (logs a warning instead); table-wide UPDATE on `profiles` is revoked before the column-level grant; `anon` loses all access to data tables; clients can no longer write `signal_unlocks` directly; the legacy sync trigger carries edits to the old columns into the new ones instead of overwriting them; `set_signal_published_at()` is removed from client EXECUTE; a tripwire aborts the migration if any other SELECT/ALL policy exists on `signals`; and a final assertion block checks permissions before COMMIT. No second signup trigger is created: `on_auth_user_created` already exists and calls `handle_new_user()`.

## 14.4 Frontend v2 (`index.html`)

Connected to Supabase Auth, profiles, the live signal feed and signal unlocking. Redesigned: sentence-case interface, SVG icons, loading skeletons, and a price-ladder layout on each signal showing take profits, entry zone and stop loss in price order. Locked signals receive **no trade data** from the server.

- Config at top of the script: `SB_URL`, `SB_KEY` (publishable key; safe to be public), `PLANS`.
- Signup collects name, country, phone, email, password; shows a "check your email" step because email confirmation is on.
- Signals: `get_signal_feed()` for the list, then a normal `select` on `signals` for unlocked rows (row security filters it).
- Unlock calls `unlock_signal`; when the free limit is reached the paywall sheet opens.
- Account tab shows profile, plan, expiry and free unlocks left.
- Plans tab shows prices only. Payment submission is not built yet.
- There is **no admin interface** in v2.
- Verified so far: JavaScript syntax check only. Not tested against the live database.

**v2.1 (1 Nov 2026), same concept, new look.** Display font Bricolage Grotesque with Manrope for text. Each unlocked signal has a **price rail**: vertical spacing is proportional to real price distance, the entry zone is a gold band, the profit side is green and the risk side red, with labels spaced so they never overlap and the distance from entry in price points. Also: confidence meter, reward-to-risk to TP 1, locked cards with a placeholder instead of data, "Save x%" and approximate monthly price on Plans (calculated from `PLANS`), free-unlock dots on Account, signals sorted newest first, friendly error messages, inline login errors, a retry state when the feed fails, Esc and tap-outside to close sheets, double-tap protection on Unlock, favicon and meta tags. Supabase calls, access logic, prices and the 3 free unlocks are unchanged. Not run or rendered by the author; test on a real phone (HANDOVER test 11).

## 14.5 Administrator access (replaces the old passcode)

The old hardcoded passcode no longer exists in v2. It only ever guarded a local prototype, but it was visible in public source and remains in GitHub history, so it must never be reused anywhere.

Administrators are now defined only by `profiles.role = 'admin'` in the database. There is no admin password in the code. An administrator logs in with the normal email and password of their own account. Users cannot promote themselves (no grant on `role`, plus a trigger).

To make the owner account an administrator, register and confirm the account through the app, then run in SQL Editor:

```sql
UPDATE public.profiles SET role = 'admin' WHERE email = 'YOUR_EMAIL_HERE';
```

Use a strong, unique password for that account and consider enabling multi-factor authentication for it before launch. Until the admin dashboard is built (Drop 2), signals are posted with SQL or the Supabase Table Editor.

## 14.6 Confirmed decisions

| Plan id | Label | GHS | USD | Duration |
|---|---|---|---|---|
| `monthly` | 1 Month | 50 | 10 | 30 days (proposed, not yet confirmed) |
| `five_month` | 5 Months | 170 | 35 | 150 days (proposed, not yet confirmed) |
| `lifetime` | Lifetime | 850 | 150 | No expiry |

The earlier prototype listed 5 months at GH₵160 / $30; the owner corrected it to GH₵170 / $35. Ghana pays GH₵ by Mobile Money; others pay USDT. Prices currently live in the `PLANS` list in `index.html`; Drop 2 will make the database the single source of truth for amounts.

Free unlock allowance: **3**, set in `unlock_signal` and `get_my_access` and shown in the UI. Owner to confirm this is final.

## 14.7 Open risks and recommendations

- **Forgot password** and **resend confirmation** are not built. Add before launch.
- **Email sending:** Supabase's built-in sender is heavily rate-limited. Configure custom SMTP before launch. For testing, create test users in Dashboard > Authentication > Users with auto-confirm.
- **Free unlocks are permanent and can be spent on old closed signals.** Add a confirmation before an unlock and decide whether free unlocks apply to open signals only.
- **Google Play:** if the app is wrapped for the Play Store, check Google's current policy on subscriptions and billing, and its rules for trading-signal apps. Manual Mobile Money/USDT approval may not be allowed inside a Play app. Also required: privacy policy, terms, risk disclaimer.
- **Public repo exposure:** Cloudflare Pages serves everything in the output directory (`/`), so `README.md` and any `.sql` files in the repo root are publicly downloadable. Keep secrets out of them, or move the site into a `public/` folder and set that as the output directory.
- **Hardening:** pin the `supabase-js` version with an integrity hash instead of the floating `@2`, and add security headers (a `_headers` file on Cloudflare Pages).
- **Never** put the Supabase secret/service_role key or the database password in the frontend, GitHub or this file.

# 15. Remaining plan

| Drop | Contents | Status |
|---|---|---|
| Step 1 | Migration (rev 1.1) + v2.1 frontend (Auth, profiles, feed, unlock) | Written, awaiting execution and testing |
| Drop 2 | `submit_payment` / `review_payment` functions, pending-payment limit, subscription activation, audit log, payment instructions in `app_settings`, admin dashboard (post/edit signals, review payments, settings) | Not started |
| Drop 3 | Private `signal-images` bucket, admin upload, image access tied to signal entitlement | Not started |
| Drop 4 | Forgot password, resend confirmation, confirm-before-unlock, legal pages, pin supabase-js version, security headers, final testing, README update | Not started |

---

# 16. Independent review (1 Nov 2026) and resolutions

An outside review of README, HANDOVER, the Step 1 SQL and `index.html` rated the architecture good, the frontend a sound foundation, the migration "needs corrections", and launch readiness "not yet". Resolutions:

| Review point | Resolution |
|---|---|
| Signup trigger may be duplicated | Not an issue: rev 1.0 never created a trigger. Rev 1.1 states this, replaces only the function, and HANDOVER verifies the trigger is still attached |
| Profile permissions: check role and email cannot be changed | Table-wide UPDATE revoked, then column grant; migration asserts role and email are not updatable; HANDOVER lists column privileges |
| Legacy sync trigger could overwrite old-column edits | Rewritten (migration Section 5) |
| Another broad SELECT policy would defeat the new one | Tripwire in the migration; policy query in HANDOVER |
| Function permission query needs careful reading | HANDOVER states the exact expected result per function; `set_signal_published_at()` now revoked too |
| Backups cover only two tables | All five data tables backed up; schema locked |
| Do not deploy before verifying; check live definitions first | HANDOVER has a read-only Step 0, and deploy comes only after verification passes |
| Test needs at least 3 (better 4) signals | Four test signals provided, plus clean-up lines |
| `get_signal_feed().limit(50)` should be confirmed | Kept (supabase-js supports it on set-returning functions); the frontend now also sorts newest first. Confirmed by test 4 |
| Logged-out visitor sees no preview | Open decision in HANDOVER |
| Error handling needs improvement | Done in v2.1 |
| Password recovery, payments, admin dashboard, chart images missing | Planned in Drops 2 to 4; not built yet |

Additional note: `app_settings` rows are readable by every signed-in user. Payment instructions are meant to be shown to them, but never store secrets there.

---

**End of reference document.**  
This README is the working baseline for continuing PipPulse. Update it as the database, frontend, and deployment evolve; retain earlier findings and append changes rather than silently discarding project history.
