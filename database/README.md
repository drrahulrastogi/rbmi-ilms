# Database setup
For a **new Supabase project**, run install-new-supabase.sql once in trusted SQL Editor. It creates all eleven application migrations and seeds the legacy institution/policy rows, then consolidates them into four active libraries. Supabase supplies auth.users and platform roles. Do not run schema.sql and the installer together.

Create the first Auth user rahul.r@rbmi.in, disable public signup while keeping email/password login enabled, and run scripts/bootstrap-admin.sql with its UUID. This creates one network administrator with access to all active libraries. Create individual staff in the app Settings after configuring server credentials. Configure SMTP and the recovery redirect before distributing accounts.

For an existing library, take a verified backup and apply ONLY missing timestamped migrations in order. Never run the fresh installer or seed over existing data. The upgrade archives legacy institution entries rather than dropping historical records. Schema-only schema.sql concatenates migrations; seed.sql is a separate reference. Prefer the ordered installer for a new project.

All app tables have RLS and no direct browser-role access. Public authenticated RPCs check library membership; anonymous library_catalogue exposes an explicit holdings-only projection. Private import archives never appear in that response.

The package contains no live data, original student workbooks, Auth passwords/hashes, private keys or source import SQL. Those require protected backup procedures. Schema and fictional demonstration seed are sufficient to run a clean installation.
