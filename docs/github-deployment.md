# RBMI ILMS 2.0 - github deployment

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

