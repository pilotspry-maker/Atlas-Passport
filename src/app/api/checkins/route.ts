import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { sendCheckInReceivedEmail } from '@/lib/email'
import type { Passport, Node, CheckIn } from '@/types/database'

export async function POST(request: Request) {
  try {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  let body: { passportId?: string; nodeId?: string; storagePath?: string; notes?: string }
  try {
    body = await request.json()
  } catch {
    return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
  }
  const { passportId, nodeId, storagePath, notes } = body

  if (!passportId || !nodeId || !storagePath) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
  }

  const admin = createAdminClient()

  // Verify passport belongs to user and is active
  const { data: passportData } = await admin
    .from('passports')
    .select('id, status, expires_at, corridor_id, user_id')
    .eq('id', passportId)
    .eq('user_id', user.id)
    .single()
  const passport = passportData as Pick<Passport, 'id' | 'status' | 'expires_at' | 'corridor_id' | 'user_id'> | null

  if (!passport) return NextResponse.json({ error: 'Passport not found' }, { status: 404 })
  if (passport.status !== 'active') return NextResponse.json({ error: 'Passport not active' }, { status: 403 })
  if (new Date(passport.expires_at).getTime() < Date.now()) {
    return NextResponse.json({ error: 'Passport expired' }, { status: 403 })
  }

  // Verify node belongs to this corridor
  const { data: nodeData } = await admin
    .from('nodes')
    .select('id, name, sequence, corridor_id')
    .eq('id', nodeId)
    .eq('corridor_id', passport.corridor_id)
    .single()
  const node = nodeData as Pick<Node, 'id' | 'name' | 'sequence' | 'corridor_id'> | null

  if (!node) return NextResponse.json({ error: 'Node not in this corridor' }, { status: 400 })

  // Check for existing approved check-in
  const { data: existingData } = await admin
    .from('check_ins')
    .select('id, status')
    .eq('passport_id', passportId)
    .eq('node_id', nodeId)
    .maybeSingle()
  const existingCheckIn = existingData as Pick<CheckIn, 'id' | 'status'> | null

  if (existingCheckIn?.status === 'approved') {
    return NextResponse.json({ error: 'Already approved' }, { status: 409 })
  }

  if (existingCheckIn?.status === 'pending') {
    return NextResponse.json({ error: 'Already submitted and pending review' }, { status: 409 })
  }

  // Generate signed URL for viewing (1 year)
  const { data: urlData } = await admin.storage
    .from('check-in-proofs')
    .createSignedUrl(storagePath, 60 * 60 * 24 * 365)

  const proofUrl = urlData?.signedUrl ?? storagePath

  // If rejected, update; otherwise insert
  let checkInId: string

  if (existingCheckIn?.status === 'rejected') {
    const { data: updated, error } = await admin
      .from('check_ins')
      .update({
        proof_url: proofUrl,
        proof_storage_path: storagePath,
        notes: notes ?? null,
        status: 'pending',
        admin_notes: null,
        reviewed_by: null,
        reviewed_at: null,
        submitted_at: new Date().toISOString(),
      })
      .eq('id', existingCheckIn.id)
      .select('id')
      .single()

    if (error || !updated) {
      return NextResponse.json({ error: 'Failed to update check-in' }, { status: 500 })
    }
    checkInId = (updated as { id: string }).id
  } else {
    const { data: inserted, error } = await admin
      .from('check_ins')
      .insert({
        passport_id: passportId,
        user_id: user.id,
        node_id: nodeId,
        proof_url: proofUrl,
        proof_storage_path: storagePath,
        notes: notes ?? null,
        status: 'pending',
      })
      .select('id')
      .single()

    if (error || !inserted) {
      console.error('Check-in insert error:', error)
      return NextResponse.json({ error: 'Failed to record check-in' }, { status: 500 })
    }
    checkInId = (inserted as { id: string }).id
  }

  // Get corridor for email
  const { data: corridorData } = await admin
    .from('corridors')
    .select('name')
    .eq('id', passport.corridor_id)
    .single()
  const corridor = corridorData as { name: string } | null

  const { count: totalNodes } = await admin
    .from('nodes')
    .select('*', { count: 'exact', head: true })
    .eq('corridor_id', passport.corridor_id)
    .eq('is_active', true)

  // Get profile for email
  const { data: profileData } = await admin
    .from('profiles')
    .select('email, full_name')
    .eq('id', user.id)
    .single()
  const profile = profileData as { email: string; full_name: string | null } | null

  sendCheckInReceivedEmail({
    to: profile?.email ?? user.email!,
    name: profile?.full_name ?? 'Traveller',
    nodeName: node.name,
    corridorName: corridor?.name ?? '',
    sequence: node.sequence,
    totalNodes: totalNodes ?? 0,
  }).catch(err => console.error('Email error:', err))

  return NextResponse.json({ checkInId })
  } catch (err) {
    console.error('[checkins] Unhandled error:', err)
    return NextResponse.json({ error: 'An unexpected error occurred' }, { status: 500 })
  }
}
