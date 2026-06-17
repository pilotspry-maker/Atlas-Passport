import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { sendTimerWarningEmail } from '@/lib/email'

// Vercel cron: 0 * * * * (every hour)
// Protected by CRON_SECRET header

type PassportRow = {
  id: string
  corridor_id: string
  expires_at: string
  warning_sent_at: string | null
  corridor: { name: string } | null
  profile: { email: string; full_name: string | null } | null
}

export async function GET(request: Request) {
  if (!process.env.CRON_SECRET) {
    console.error('[cron/timer-warning] CRON_SECRET env var is not set')
    return NextResponse.json({ error: 'Server misconfiguration' }, { status: 500 })
  }

  const authHeader = request.headers.get('authorization')
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const admin = createAdminClient()

  // Find active passports expiring in 23–25 hours that haven't received a warning
  const twentyThreeHoursFromNow = new Date(Date.now() + 23 * 60 * 60 * 1000).toISOString()
  const twentyFiveHoursFromNow = new Date(Date.now() + 25 * 60 * 60 * 1000).toISOString()

  const { data: passportsData } = await admin
    .from('passports')
    .select(`
      *,
      corridor:corridors(name),
      profile:profiles(email, full_name)
    `)
    .eq('status', 'active')
    .is('warning_sent_at', null)
    .gte('expires_at', twentyThreeHoursFromNow)
    .lte('expires_at', twentyFiveHoursFromNow)

  const passports = passportsData as PassportRow[] | null

  if (!passports?.length) {
    return NextResponse.json({ sent: 0 })
  }

  let sent = 0
  const errors: string[] = []

  for (const passport of passports) {
    const corridor = passport.corridor
    const profile = passport.profile

    if (!profile?.email) continue

    // Get approved count
    const { count: approvedCount } = await admin
      .from('check_ins')
      .select('*', { count: 'exact', head: true })
      .eq('passport_id', passport.id)
      .eq('status', 'approved')

    const { count: totalNodes } = await admin
      .from('nodes')
      .select('*', { count: 'exact', head: true })
      .eq('corridor_id', passport.corridor_id)
      .eq('is_active', true)

    try {
      await sendTimerWarningEmail({
        to: profile.email,
        name: profile.full_name ?? 'Traveller',
        corridorName: corridor?.name ?? '',
        expiresAt: passport.expires_at,
        approvedCount: approvedCount ?? 0,
        totalNodes: totalNodes ?? 0,
      })

      await admin
        .from('passports')
        .update({ warning_sent_at: new Date().toISOString() })
        .eq('id', passport.id)

      sent++
    } catch (err) {
      errors.push(`${passport.id}: ${err}`)
    }
  }

  return NextResponse.json({ sent, errors })
}
