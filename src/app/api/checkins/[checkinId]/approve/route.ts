import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { sendCheckInApprovedEmail, sendCorridorCompleteEmail } from '@/lib/email'

interface Params {
  params: Promise<{ checkinId: string }>
}

export async function POST(request: Request, { params }: Params) {
  const { checkinId } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  // Verify admin
  const { data: profile } = await supabase
    .from('profiles')
    .select('is_admin')
    .eq('id', user.id)
    .single()

  if (!profile?.is_admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { adminNotes } = await request.json()
  const admin = createAdminClient()

  // Get check-in with full context
  const { data: checkIn } = await admin
    .from('check_ins')
    .select(`
      *,
      node:nodes(id, name, sequence, corridor_id, corridor:corridors(id, name)),
      profile:profiles(id, email, full_name),
      passport:passports(id, corridor_id, user_id)
    `)
    .eq('id', checkinId)
    .single()

  if (!checkIn) return NextResponse.json({ error: 'Check-in not found' }, { status: 404 })
  if (checkIn.status !== 'pending') {
    return NextResponse.json({ error: 'Check-in already reviewed' }, { status: 409 })
  }

  // Approve
  const { error: updateError } = await admin
    .from('check_ins')
    .update({
      status: 'approved',
      admin_notes: adminNotes || null,
      reviewed_by: user.id,
      reviewed_at: new Date().toISOString(),
    })
    .eq('id', checkinId)

  if (updateError) {
    return NextResponse.json({ error: 'Failed to approve' }, { status: 500 })
  }

  const node = checkIn.node as { id: string; name: string; sequence: number; corridor_id: string; corridor: { id: string; name: string } }
  const userProfile = checkIn.profile as { id: string; email: string; full_name: string | null }
  const passport = checkIn.passport as { id: string; corridor_id: string; user_id: string }

  // Check if corridor is now complete
  const { count: totalNodes } = await admin
    .from('nodes')
    .select('*', { count: 'exact', head: true })
    .eq('corridor_id', node.corridor_id)
    .eq('is_active', true)

  const { count: approvedCount } = await admin
    .from('check_ins')
    .select('*', { count: 'exact', head: true })
    .eq('passport_id', passport.id)
    .eq('status', 'approved')

  const isLastNode = (approvedCount ?? 0) >= (totalNodes ?? 0)
  let passportComplete = false

  if (isLastNode) {
    const { error: passportError } = await admin
      .from('passports')
      .update({
        status: 'complete',
        completed_at: new Date().toISOString(),
      })
      .eq('id', passport.id)

    if (!passportError) passportComplete = true
  }

  // Send emails (non-blocking)
  sendCheckInApprovedEmail({
    to: userProfile.email,
    name: userProfile.full_name ?? 'Traveller',
    nodeName: node.name,
    corridorName: node.corridor.name,
    sequence: node.sequence,
    totalNodes: totalNodes ?? 0,
    isLastNode,
  }).catch(err => console.error('Email error:', err))

  if (passportComplete) {
    const { data: reward } = await admin
      .from('rewards')
      .select('title, redemption_code')
      .eq('corridor_id', node.corridor_id)
      .maybeSingle()

    sendCorridorCompleteEmail({
      to: userProfile.email,
      name: userProfile.full_name ?? 'Traveller',
      corridorName: node.corridor.name,
      rewardTitle: reward?.title ?? 'your reward',
      rewardCode: reward?.redemption_code ?? null,
    }).catch(err => console.error('Email error:', err))
  }

  return NextResponse.json({ checkInId: checkinId, passportComplete })
}
