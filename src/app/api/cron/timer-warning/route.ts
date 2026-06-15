import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { sendTimerWarningEmail } from '@/lib/email'

// Vercel cron: 0 * * * * (every hour)
// Protected by CRON_SECRET header

export async function GET(request: Request) {
  const authHeader = request.headers.get('authorization')
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const admin = createAdminClient()

  // Find active passports expiring in 23–25 hours that haven't received a warning
  const twentyThreeHoursFromNow = new Date(Date.now() + 23 * 60 * 60 * 1000).toISOString()
  const twentyFiveHoursFromNow = new Date(Date.now() + 25 * 60 * 60 * 1000).toISOString()

  const { data: passports } = await admin
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

  if (!passports?.length) {
    return NextResponse.json({ sent: 0 })
  }

  let sent = 0
  const errors: string[] = []

  for (const passport of passports) {
    const corridor = passport.corridor as { name: string } | null
    const profile = passport.profile as { email: string; full_name: string | null } | null

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
