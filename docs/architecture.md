# Architecture

React/Vite on Vercel uses Supabase PostgreSQL and Auth. Private app tables deny browser access; explicit transactional RPCs check the authenticated library role, pending password setup and enabled administrator MFA. app functions have fixed search paths and cannot be called directly by browser roles.

Twelve ordered migrations and the institution/policy seed are bundled in database/install-new-supabase.sql for a new project. Existing projects apply only missing migrations. Source-only GitHub Pages cannot run account endpoints. Configure the public VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY and server-only SUPABASE_SERVICE_ROLE_KEY. Allow recovery and invitation redirect URLs and configure SMTP.

Growing records use keyset pages; overview counts are aggregates. Holdings still load in bounded collection requests for catalogue joins. Reports fetch their full bounded sources only on request, with explicit capacity checks. Public title searches return counts and a bounded preview; physical copies use a separate cursor. Shared database quotas protect account APIs and public reads. Vercel enforces CSP and emits redacted request logs; the health workflow supplies scheduled availability checks.

See HARDENING.md and the complete illustrated manual for invitation, MFA, operational limits, concurrency tests and backup/restore details.
