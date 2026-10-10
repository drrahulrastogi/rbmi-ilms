# GitHub deployment

The GitHub repository's `.github/workflows/pages.yml` installs locked dependencies, runs the PostgreSQL tests, builds React and deploys `dist` to GitHub Pages. The build uses the repository's actual Pages base path. Logos, help links and demo SQL use that base path too.

Push changes to `main` to publish updates, or run the workflow manually from Actions. Pages must use GitHub Actions as its publishing source.

## Connect the live Supabase database

Follow the schema/Auth/bootstrap steps in README.md first. Then set these **repository Actions variables** in Settings > Secrets and variables > Actions > Variables:

- `VITE_SUPABASE_URL`: your Supabase project HTTPS URL.
- `VITE_SUPABASE_ANON_KEY`: its public publishable/anon client key.

These two client values are public build configuration. Never use a service-role key, secret key or database password here. Set both together. Run the Pages workflow again after editing them. With both unset, the application deliberately serves its labelled fictional browser-local demonstration.

Set Supabase Auth's Site URL to the exact published Pages URL. Accounts and role assignments are provisioned as described in the manual. GitHub Pages hosts the React frontend; Supabase supplies shared records, authentication and transactional writes.

No `.env.local`, database password, CLI token, node_modules or local IndexedDB data belongs in the GitHub repository. Downloadable PDF/CHM sources are included through the documentation files and release package.
