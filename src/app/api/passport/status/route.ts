import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function GET() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: passport } = await supabase
    .from('passports')
    .select('*')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()

  if (!passport) return NextResponse.json({ passport: null })

  // Lazy expiry check
  if (new Date(passport.expires_at).getTime() < Date.now()) {
    const admin = createAdminClient()
    await admin
      .from('passports')
      .update({ status: 'expired' })
      .eq('id', passport.id)

    return NextResponse.json({ passport: { ...passport, status: 'expired' } })
  }

  return NextResponse.json({ passport })
}
