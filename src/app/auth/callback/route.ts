import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const next = searchParams.get('next') ?? '/passport'

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

  // Persist user_metadata (name, referral_code) into the profiles table
  try {
    const { data: { user } } = await supabase.auth.getUser()
    if (user) {
      const meta = user.user_metadata as Record<string, string | null> | null
      const fullName = meta?.full_name?.trim() || null
      const referralCode = meta?.referral_code?.trim() || null

      if (fullName || referralCode) {
        const admin = createAdminClient()

        // Try updating with referral_code first; fall back without it if column missing
        const { error: profileError } = await admin
          .from('profiles')
          .update({ full_name: fullName, referral_code: referralCode })
          .eq('id', user.id)

        if (profileError) {
          if (referralCode && profileError.message.includes('referral_code')) {
            // Column doesn't exist yet — update name only
            if (fullName) {
              await admin.from('profiles').update({ full_name: fullName }).eq('id', user.id)
            }
          } else {
            console.error('[auth/callback] Profile update error:', profileError.message)
          }
        }
      }
    }
  } catch (err) {
    // Non-fatal: user is authenticated, profile update is best-effort
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
