# Vercel deployment and shared staff access

Import `https://github.com/drrahulrastogi/rbmi-ilms` into the intended Vercel account. Choose Vite and the repository root. `vercel.json` installs locked dependencies, runs database tests, builds the app, and publishes `dist`. Keep `VITE_BASE_PATH` unset: Vercel serves this app at `/`, while the GitHub Pages workflow supplies its own repository path. No paid plan is selected by the project.

## Database and staff accounts

Vercel hosts the frontend. Each browser has separate fictional records until Supabase is configured. A public frontend URL alone does not provide shared records or staff authentication.

1. Create a Supabase project in an organization you control. Select the region appropriate for RBMI, and enter a unique database password yourself. Store that password securely; never commit it or put it in frontend variables.
2. Run `supabase/migrations/202610090001_library.sql` and then `supabase/seed.sql` in the Supabase SQL Editor. The seed initializes institutions and policies; fictional demonstration books and patrons are generated only by the browser demo adapter.
3. Disable new user signups in Supabase Auth. Create the initial administrator in Auth > Users. Fill their UUID into `scripts/bootstrap-admin.sql` and execute that script in SQL Editor. Give colleagues individual Auth accounts and institution memberships in app Settings. Accounts without memberships cannot access institutional records.
4. In Vercel Project > Settings > Environment Variables add both `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` for Production. Use the Supabase project HTTPS URL and public publishable/anon key. **Never use a service-role key, secret key or database password.** The two frontend values are public by design.
5. Deploy or redeploy after adding the variables. Set Supabase Auth's Site URL to the exact production Vercel URL. Sign in as the administrator and verify all five institution memberships.
6. Verify a record created by one authorized colleague appears for another colleague in the same institution after Refresh data. Confirm a colleague without membership cannot access that institution. Check issue/return/renewal, holidays, fines and audit logs before adding real records.

The existing help manual contains detailed migration, access, backup and operating procedures. Keep independent database backups. The PGlite demo database remains browser-local and is not automatically imported into Supabase.

## Sharing the site

Share the stable production domain shown by Vercel after deployment. Production visitors should see the app sign-in page with Supabase configured. Vercel dashboard/team membership is not required for library users; the app's Supabase accounts and institution roles control access.

Check the deployed logo, Help link and a successful staff sign-in. GitHub pushes to the connected production branch trigger Vercel deployments. Keep GitHub Pages variables separate from Vercel environment variables.

## Hosting plan

Vercel's Hobby plan is for personal, non-commercial use. A personal demonstration for peers may fit; institutional production use must be assessed against Vercel's current terms before choosing a plan. Do not upgrade or incur charges without the owner's approval.

Official references: https://vercel.com/docs/frameworks/frontend/vite and https://vercel.com/docs/plans/hobby.
