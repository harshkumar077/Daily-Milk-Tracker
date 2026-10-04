# Daily Milk Tracker

A simple mobile-first milk calendar for families. It works locally first and can connect to Supabase for authentication, family accounts, cloud sync, and row-level data isolation.

## Run locally

```powershell
python -m http.server 8080
```

Open http://localhost:8080. Without Supabase configuration, data stays in this browser's local cache.

## Supabase setup

1. Create a Supabase project.
2. Run [`supabase/schema.sql`](supabase/schema.sql) in the SQL Editor.
3. Copy [`supabase/config.example.js`](supabase/config.example.js) to `supabase/config.js` and add the project URL and publishable key.
4. Enable Email authentication in Supabase. Disable email confirmation for a simple local test, or configure SMTP.
5. Reload the app. It will show Login, account creation, family creation, and family-code joining.

The browser only uses the publishable key. Never put a service-role key in the frontend. RLS policies scope family records by membership, and the invite join is a security-definer function that does not expose family listings.

## GitHub Pages

1. Create a repository and push this folder to the `main` branch.
2. In repository Settings > Secrets and variables > Actions, add `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
3. In Settings > Pages, choose GitHub Actions as the source.
4. The included `.github/workflows/pages.yml` publishes the site and generates `supabase/config.js` from those secrets. These browser credentials are expected to be public; RLS protects data.
5. Add the deployed Pages origin to Supabase Authentication > URL Configuration as the Site URL and Redirect URL.
6. Verify signup, family setup/joining, daily entry, calendar, backup, and logout on the Pages URL.

All asset paths are relative, so the app works under `/repository-name/` as well as a custom domain.
