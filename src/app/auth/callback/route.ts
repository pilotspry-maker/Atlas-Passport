import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

/** Only allow relative paths from the `next` query param to prevent open redirects. */
function safeNext(raw: string | null): string {
  if (!raw) return '/passport'
  // Must start with exactly one slash, not // (scheme-relative) or //evil.com
  if (raw.startsWith('/') && !raw.startsWith('//')) return raw
  return '/passport'
}

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const next = safeNext(searchParams.get('next'))

  if (!code) {
    console.error('[auth/callback] No code param in URL')
    return NextResponse.redirect(`${origin}/auth/login?error=auth_error`)
  }

  const supabase = await createClient()
  const { error: sessionError } = await supabase.auth.exchangeCodeForSession(code)

  if (sessionError) {
    console.error('[auth/callback] exchangeCodeForSession error:', sessionError.message)
    return NextResponse.redirect(`${origin}/auth/login?error=auth_error`)
  }

  // Persist user_metadata (name, referral_code) into the profiles table.
  // This is best-effort: a failure here must never block the user from signing in.
  try {
    const { data: { user } } = await supabase.auth.getUser()
    if (user) {
      // user_metadata is JSON — guard types before calling string methods
      const meta = user.user_metadata as Record<string, unknown> | null
      const fullName = typeof meta?.full_name === 'string'
        ? meta.full_name.trim() || null
        : null
      const referralCode = typeof meta?.referral_code === 'string'
        ? meta.referral_code.trim() || null
        : null

      if (fullName || referralCode) {
        const admin = createAdminClient()

        // Try updating with referral_code first; fall back to name-only if column missing.
        const { error: profileError } = await admin
          .from('profiles')
          .update({ full_name: fullName, referral_code: referralCode })
          .eq('id', user.id)

        if (profileError) {
          if (
            referralCode &&
            (profileError.message.includes('referral_code') ||
              profileError.code === '42703') // Postgres "undefined_column"
          ) {
            // Column doesn't exist yet — update name only
            if (fullName) {
              await admin
                .from('profiles')
                .update({ full_name: fullName })
                .eq('id', user.id)
            }
          } else {
            console.error('[auth/callback] Profile update error:', profileError.message)
          }
        }
      }
    }
  } catch (err) {
    console.error('[auth/callback] Profile metadata sync error:', err)
  }

  const forwardedHost = request.headers.get('x-forwarded-host')
  const isLocalEnv = process.env.NODE_ENV === 'development'

  const destination =
    isLocalEnv
      ? `${origin}${next}`
      : forwardedHost
      ? `https://${forwardedHost}${next}`
      : `${origin}${next}`

  return NextResponse.redirect(destination)
}
