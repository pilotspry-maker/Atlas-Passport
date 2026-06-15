import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { requireAdmin } from '@/lib/auth'
import { sendCheckInApprovedEmail, sendCorridorCompleteEmail } from '@/lib/email'

interface Params {
  params: Promise<{ checkinId: string }>
}

type CheckInRow = {
  id: string
  status: string
  passport_id: string
  node_id: string
  node: { id: string; name: string; sequence: number; corridor_id: string; corridor: { id: string; name: string } } | null
  profile: { id: string; email: string; full_name: string | null } | null
  passport: { id: string; corridor_id: string; user_id: string } | null
}

export async function POST(request: Request, { params }: Params) {
  const { checkinId } = await params
  const auth = await requireAdmin()
  if (auth.response) return auth.response

  const { adminNotes } = await request.json()
  const admin = createAdminClient()

  const { data } = await admin
    .from('check_ins')
    .select('id, status, passport_id, node_id, node:nodes(id, name, sequence, corridor_id, corridor:corridors(id, name)), profile:profiles(id, email, full_name), passport:passports(id, corridor_id, user_id)')
    .eq('id', checkinId)
    .single()

  if (!data) return NextResponse.json({ error: 'Check-in not found' }, { status: 404 })

  const checkIn = data as unknown as CheckInRow

  if (checkIn.status !== 'pending') {
    return NextResponse.json({ error: 'Check-in already reviewed' }, { status: 409 })
  }

  const { error: updateError } = await admin
    .from('check_ins')
    .update({
      status: 'approved',
      admin_notes: adminNotes || null,
      reviewed_by: auth.user.id,
      reviewed_at: new Date().toISOString(),
    })
    .eq('id', checkinId)

  if (updateError) return NextResponse.json({ error: 'Failed to approve' }, { status: 500 })

  const node    = checkIn.node!
  const profile = checkIn.profile!
  const passport = checkIn.passport!

  // Check corridor completion
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
    const { error } = await admin
      .from('passports')
      .update({ status: 'complete', completed_at: new Date().toISOString() })
      .eq('id', passport.id)
    if (!error) passportComplete = true
  }

  sendCheckInApprovedEmail({
    to: profile.email,
    name: profile.full_name ?? 'Traveller',
    nodeName: node.name,
    corridorName: node.corridor?.name ?? '',
    sequence: node.sequence,
    totalNodes: totalNodes ?? 0,
    isLastNode,
  }).catch(console.error)

  if (passportComplete) {
    const { data: reward } = await admin
      .from('rewards')
      .select('title, redemption_code')
      .eq('corridor_id', node.corridor_id)
      .maybeSingle()

    sendCorridorCompleteEmail({
      to: profile.email,
      name: profile.full_name ?? 'Traveller',
      corridorName: node.corridor?.name ?? '',
      rewardTitle: (reward as { title?: string; redemption_code?: string } | null)?.title ?? 'your reward',
      rewardCode: (reward as { title?: string; redemption_code?: string } | null)?.redemption_code ?? null,
    }).catch(console.error)
  }

  return NextResponse.json({ checkInId: checkinId, passportComplete })
}
