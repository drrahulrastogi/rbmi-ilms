# RBMI ILMS 2.0 - architecture

Updated 23 October 2026. The authoritative operator guide is docs/help/index.html.

## Developer installation and deployment

The source repository is drrahulrastogi/rbmi-ilms. The UI and account endpoints run on Vercel; shared records and Auth run on Supabase.

1. Install Node.js 20.16 or newer, run npm ci, npm test and npm run build. npm run dev starts local development. Without both Supabase variables it uses fictional browser-local records.
2. For a NEW Supabase project run database/install-new-supabase.sql once, containing all five migrations and the policy/institution seed. Never run the creation installer over an existing library.
3. Disable public signup, keep email/password login enabled, create rahul.r@rbmi.in in Auth and run scripts/bootstrap-admin.sql with its UUID.
4. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to the public URL/key. Set SUPABASE_SERVICE_ROLE_KEY only as a sensitive server-side Vercel variable; never prefix it with VITE_.
5. Set Auth Site URL to the HTTPS application, allow /?recovery=1, configure SMTP and require 12-character passwords with lower/upper letters, numbers and symbols.
6. Deploy the repository root to the intended Vercel Vite project. vercel.json runs tests before the build. The current release uses authenticated CLI deployment; GitHub source hosting alone does not imply automatic Vercel deployment.
7. For an existing installation, back up first and apply only missing migrations in order. Never recreate the original schema over live data.

PostgreSQL provides transactional circulation and unique identifiers. Supabase supplies managed database/Auth and Vercel serves the UI and server endpoints.

Free plans have quotas and provider-controlled pause/retention rules. Check dashboards before scaling. No paid upgrade is enabled by this release.

## Accounts and role permissions

Permissions are enforced by the database using memberships and designated librarian assignments. Editable user profile metadata is never used to grant access.

1. Admin manages all libraries, policies, accounts, assignments and audit records. The system permits one network administrator.
2. A librarian manages the assigned library's catalogue, patrons, circulation, fines, availability, acquisitions, authorities and serials. Each library has a distinct primary librarian.
3. Assistant operates circulation and holds. Accountant records payments and waivers. Auditor reads records and reports. Staff access is limited to assigned libraries.
4. Patron sign-ins must be linked to a patron UUID. They see the catalogue and their own loans, holds and fines, and can renew their own loans or manage their own holds.
5. Admin opens Settings > Accounts to create staff, update non-admin email addresses or send recovery messages. Sensitive actions require the administrator's current password.
6. To provision a patron sign-in, create its email/password identity in Supabase Auth, then assign patron role with the linked patron UUID in Institution access.

The create-account form supports librarian, assistant, accountant and auditor roles. Library records and Auth users are separate entities.

Retained sample accounts ending in .invalid cannot receive recovery emails. Replace them with real individual accounts before operational use.

## Backup, restore and private handover

The public source package includes schema and fictional seeds, not live students, staff passwords or original private workbooks.

1. Use an authorized database dump or trusted SQL export for all app tables, source archives and audit records. Store backups in a protected off-site location.
2. Inventory the Supabase/Vercel projects, environment variable names and SMTP setup. Keep secret values in an approved password manager.
3. Plan Supabase Auth identity backup/migration separately through supported tools. A patron CSV is not an Auth backup.
4. Before upgrades/imports take a verified backup and retain original Excel files and reconciliation reports.
5. Restore into a separate project and verify counts, memberships, loans, fines and recovery settings before trusting a restore procedure.
6. Treat initial-password CSVs as private handover files that become outdated after password changes; use recovery instead of assuming old passwords remain valid.

The pre-upgrade database backup is stored privately in the workspace. A full disaster-recovery restore drill has not been performed for this release.

Clearing browser storage removes local demonstration records, not live Supabase data.

