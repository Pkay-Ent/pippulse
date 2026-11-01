# PipPulse – Gold Signals App
## Project Reference, Database Baseline & Migration Roadmap

**Purpose:** Preserve a detailed record of the work completed, the database state inspected, decisions made, known compatibility issues, and the planned direction for PipPulse.

**Status:** Database inspection completed; final V3 migration has **not** been executed.  
**Last updated:** 1 November 2026  
**Frontend file:** Not yet inspected in this review.

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

Plan prices, payment instructions, wallet details, and exact currency amounts have not yet been confirmed in this review. Do not invent them.

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

- [ ] Inspect the actual current `index.html` frontend.
- [ ] Confirm whether a PipPulse user account has been registered.
- [ ] Confirm or assign the intended administrator account safely.
- [ ] Inspect full table constraints, indexes, triggers, grants, and function definitions before final migration.
- [ ] Inspect `signal_unlocks` columns, constraints, RLS, and grants.
- [ ] Verify exact definitions and return types of all five Section 3 functions.
- [ ] Prepare a migration specifically compatible with the existing database.
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

**The next action is to upload the current `index.html` file for inspection.**

The frontend must be reviewed before the final migration is written. We need to identify the actual database calls, field names, function signatures, authentication flow, payment workflow, and any existing UI assumptions.

Once the frontend is inspected, continue with the remaining database-definition checks and prepare a staged, migration-safe V3 upgrade based on the real project state documented above.

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

---

**End of reference document.**  
This README is the working baseline for continuing PipPulse. Update it as the database, frontend, and deployment evolve; retain earlier findings and append changes rather than silently discarding project history.
