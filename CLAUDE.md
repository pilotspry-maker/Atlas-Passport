# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Atlas Passport is an invitation-based credential platform for working artists — a public "passport" page per artist, driven by an application → admin review → approval flow. Live at https://atlas-passport.vercel.app.

## Commands

```bash
npm install          # install deps
npm run dev          # start dev server (localhost:3000)
npm run build        # production build
npm run lint         # ESLint
npm run type-check   # tsc --noEmit (no build output)
```

No test runner is configured yet.

## Stack

- **Next.js 14 (App Router)** — TypeScript, server components by default
- **Tailwind CSS** — custom design tokens in `tailwind.config.ts`
- **Supabase** — Postgres + Row Level Security + Auth (magic link only)
- **Resend** — transactional email
- **Vercel** — deployment target

## Architecture

### Auth

Magic link only via Supabase Auth. The callback at `/auth/callback/route.ts` exchanges the code for a session, then redirects admins to `/admin` and artists to `/dashboard`. Admin access is gated by the `ADMIN_EMAILS` env var (checked via `lib/utils.ts:isAdmin`).

### Supabase clients

Two clients in `lib/supabase/`:
- `client.ts` — browser client (use in `'use client'` components)
- `server.ts` — exports `createClient()` (anon key, cookie-based) and `createServiceClient()` (service role key, bypasses RLS). Service client is required for all admin operations and the `/api/apply` route.

### Data flow

```
/apply (public form)
  → POST /api/apply/route.ts
  → applications table (via service client)
  → Resend: confirmation to applicant + notify admin

/admin (admin only)
  → reads applications table (service client)
  → POST /api/admin/review/route.ts
  → updates applications.status
  → if approved: inserts into artists table + Resend approval email
  → if rejected: Resend rejection email

/passport/[slug] (public)
  → reads artists table (anon client, status = 'approved')

/dashboard (authenticated artist)
  → reads/writes artists table (anon client, RLS: user_id = auth.uid())
```

### Route protection

`middleware.ts` redirects unauthenticated users away from `/dashboard` and `/admin`. Admin-specific email check happens inside `/admin/page.tsx` and `/api/admin/review/route.ts`.

### Slug generation

Artist slugs are generated with `lib/utils.ts:slugify()` at the time of approval using `full_name`. Slugs must be unique — if a collision occurs, append a suffix manually or add a uniqueness check.

## Environment variables

See `.env.example`. Required for full functionality:

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon/public key |
| `SUPABASE_SERVICE_ROLE_KEY` | Bypasses RLS (server-only) |
| `RESEND_API_KEY` | Email delivery |
| `RESEND_FROM_EMAIL` | Sender address (must be verified domain in Resend) |
| `ADMIN_EMAILS` | Comma-separated admin emails |
| `NEXT_PUBLIC_APP_URL` | Full URL, no trailing slash (used in email links) |

## Database

Run `supabase/migrations/001_initial.sql` against your Supabase project to create `artists` and `applications` tables with RLS policies. The `applications` table has no public RLS policies — all access goes through the service role key on the server.

## Design system

Colors and typography are defined in `tailwind.config.ts`:
- `ink` (#0D0D0D) — background
- `parchment` (#F5F0E8) — primary text
- `gold` (#C4A35A) — accent / CTAs
- `muted` (#6B6560) — secondary text
- `border` (#2A2520) — borders

Fonts: `font-serif` = Playfair Display, `font-sans` = Inter (loaded via `next/font/google` in `app/layout.tsx`).

The `.stamp` CSS class in `globals.css` renders the passport stamp motif used on public-facing pages.
