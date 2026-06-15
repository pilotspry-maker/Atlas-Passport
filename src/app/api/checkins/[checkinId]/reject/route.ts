import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { requireAdmin } from '@/lib/auth'
import { sendCheckInRejectedEmail } from '@/lib/email'

interface Params {
  params: Promise<{ checkinId: string }>
}

type CheckInRow = {
  status: string
  node: { name: string; sequence: number; corridor: { name: string } } | null
  profile: { email: string; full_name: string | null } | null
}

export async function POST(request: Request, { params }: Params) {
  const { checkinId } = await params
  const auth = await requireAdmin()
  if (auth.response) return auth.response

  const { adminNotes } = await request.json()
  if (!adminNotes?.trim()) {
    return NextResponse.json({ error: 'Rejection reason required' }, { status: 400 })
  }

  const admin = createAdminClient()

  const { data } = await admin
    .from('check_ins')
    .select('status, node:nodes(name, sequence, corridor:corridors(name)), profile:profiles(email, full_name)')
    .eq('id', checkinId)
    .single()

  if (!data) return NextResponse.json({ error: 'Not found' }, { status: 404 })

  const checkIn = data as unknown as CheckInRow

  if (checkIn.status !== 'pending') {
    return NextResponse.json({ error: 'Already reviewed' }, { status: 409 })
  }

  const { error } = await admin
    .from('check_ins')
    .update({
      status: 'rejected',
      admin_notes: adminNotes.trim(),
      reviewed_by: auth.user.id,
      reviewed_at: new Date().toISOString(),
    })
    .eq('id', checkinId)

  if (error) return NextResponse.json({ error: 'Failed to reject' }, { status: 500 })

  const node    = checkIn.node!
  const profile = checkIn.profile!

  sendCheckInRejectedEmail({
    to: profile.email,
    name: profile.full_name ?? 'Traveller',
    nodeName: node.name,
    corridorName: (node.corridor as { name: string } | null)?.name ?? '',
    adminNotes: adminNotes.trim(),
  }).catch(console.error)

  return NextResponse.json({ checkInId: checkinId })
}
