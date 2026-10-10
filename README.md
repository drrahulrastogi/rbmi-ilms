# RBMI Integrated Library Management System

Modern React application for RBCET, RBMI, RBCP, RBCN and RBTTI. PostgreSQL is the backend, with Supabase Auth and transactional RPCs. Includes catalogue/copies, patrons, circulation, holds, holiday-aware fines, payments/waivers, bulk CSV upload, acquisitions, stock verification, exports, roles, audit and complete help sources.

## Run the working demonstration

Install Node.js 20.16 or newer. Extract this project to a local folder, open PowerShell there and run:

```powershell
npm ci
npm run dev
```

Open the URL printed by Vite, normally `http://127.0.0.1:5173`. The first load boots browser-local PostgreSQL and fictional sample records. It can take several seconds and downloads about 14 MB of demo runtime. Data persists in this browser's IndexedDB. No password is needed in demo mode. The role selector demonstrates server permission rules with mock users; it is not real authentication.

For Windows, `scripts\start-windows.cmd` runs installation and starts development. To build: `npm run build`; to serve the build: `npm run preview`. Do not open `dist/index.html` using file://.

## Deploy live

1. Create a free Supabase project owned by RBMI. In SQL Editor run `supabase/migrations/202610090001_library.sql`, then `supabase/seed.sql` exactly once. Alternatively use the Supabase CLI migrations workflow in the manual.
2. Disable public signup in Auth settings. Create the first staff user through Auth > Users; use a strong unique password. Copy their UUID into `scripts/bootstrap-admin.sql` and run that file in the trusted SQL Editor.
3. Copy `.env.example` to `.env.local`. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` to the project's URL and public publishable/anon key. Never use a service-role key in the frontend.
4. Rebuild and verify live sign-in locally. Assign further roles in Settings after creating Auth users.
5. Create a Cloudflare Pages project from your Git repository: build command `npm ci && npm run build`, output `dist`. Set both `VITE_` variables in the Pages build settings for the target environment. Deploy and set Supabase Auth's Site URL to the HTTPS deployment URL. See the full manual for direct upload and custom domains.
6. Run institutional acceptance tests and an off-site backup/restore drill before entering production data. Free Supabase lacks automatic backups and may pause when inactive.

## Verification

```powershell
npm test
npm run build
npm run preview
# In a second terminal (Chrome installed):
npm run test:ui
```

Database tests execute the actual migration/RPCs in PostgreSQL via PGlite. Browser tests use headless Chrome. See `docs/verification.md` for observed results and limitations.

## Manual / CHM

Open `docs/help/index.html` or `docs/help/printable.html` (Print > Save as PDF). The complete Windows CHM source is under `docs/help`. After installing Microsoft HTML Help Workshop:

```powershell
.\scripts\build-chm.ps1
# If installed elsewhere:
.\scripts\build-chm.ps1 -Compiler 'C:\Tools\HTML Help Workshop\hhc.exe'
```

The script verifies a newly produced nonempty `docs/help/RBMI.chm`. No compiled CHM is supplied when the compiler is unavailable.

## Package contents

- `src/`: React screens, styles, live/demo adapters.
- `supabase/`: authoritative SQL migration, institution/policy seed, local CLI config.
- `scripts/`: demo generation, barcode/browser checks, startup and CHM build helpers.
- `docs/`: requirements, architecture, research, verification and full manual.
- `public/`: SPA host headers/redirects, demo SQL and hosted help.
- `tests/`: executable PostgreSQL workflow/security checks.
- `package-lock.json`: reproducible dependencies.

Known scope: institution snapshots load all accessible rows; plan pagination before very large catalogues/audit history. Holds use a manual FIFO queue without notification emails. Acquisition receipt is full quantity. Lost copies do not automatically create replacement charges. See architecture/manual for exact policy semantics and acceptance steps.
