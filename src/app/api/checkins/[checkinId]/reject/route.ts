import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { sendCheckInRejectedEmail } from '@/lib/email'

interface Params {
  params: Promise<{ checkinId: string }>
}

export async function POST(request: Request, { params }: Params) {
  const { checkinId } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: profile } = await supabase
    .from('profiles')
    .select('is_admin')
    .eq('id', user.id)
    .single()

  if (!profile?.is_admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { adminNotes } = await request.json()
  if (!adminNotes?.trim()) {
    return NextResponse.json({ error: 'Rejection reason required' }, { status: 400 })
  }

  const admin = createAdminClient()

  const { data: checkIn } = await admin
    .from('check_ins')
    .select(`
      *,
      node:nodes(name, sequence, corridor:corridors(name)),
      profile:profiles(email, full_name)
    `)
    .eq('id', checkinId)
    .single()

  if (!checkIn) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  if (checkIn.status !== 'pending') {
    return NextResponse.json({ error: 'Already reviewed' }, { status: 409 })
  }

  const { error } = await admin
    .from('check_ins')
    .update({
      status: 'rejected',
      admin_notes: adminNotes.trim(),
      reviewed_by: user.id,
      reviewed_at: new Date().toISOString(),
    })
    .eq('id', checkinId)

  if (error) return NextResponse.json({ error: 'Failed to reject' }, { status: 500 })

  const node = checkIn.node as { name: string; sequence: number; corridor: { name: string } }
  const userProfile = checkIn.profile as { email: string; full_name: string | null }

  sendCheckInRejectedEmail({
    to: userProfile.email,
    name: userProfile.full_name ?? 'Traveller',
    nodeName: node.name,
    corridorName: node.corridor.name,
    adminNotes: adminNotes.trim(),
  }).catch(err => console.error('Email error:', err))

  return NextResponse.json({ checkInId: checkinId })
}
