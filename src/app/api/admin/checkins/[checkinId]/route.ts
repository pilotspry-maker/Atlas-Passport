import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { requireAdmin } from '@/lib/auth'

interface Params {
  params: Promise<{ checkinId: string }>
}

type CheckInDetail = {
  id: string
  status: string
  proof_url: string
  proof_storage_path: string
  notes: string | null
  admin_notes: string | null
  submitted_at: string
  node: { name: string; sequence: number; address: string | null; corridor: { name: string; city: string } } | null
  profile: { email: string; full_name: string | null } | null
  passport: { id: string; activated_at: string; expires_at: string; status: string } | null
}

export async function GET(_: Request, { params }: Params) {
  const { checkinId } = await params
  const auth = await requireAdmin()
  if (auth.response) return auth.response

  const admin = createAdminClient()

  const { data } = await admin
    .from('check_ins')
    .select('id, status, proof_url, proof_storage_path, notes, admin_notes, submitted_at, node:nodes(name, sequence, address, corridor:corridors(name, city)), profile:profiles(email, full_name), passport:passports(id, activated_at, expires_at, status)')
    .eq('id', checkinId)
    .single()

  if (!data) return NextResponse.json({ error: 'Not found' }, { status: 404 })

  const checkIn = data as unknown as CheckInDetail

  // Generate a fresh signed URL for the admin view (1 hour)
  const { data: freshUrl } = await admin.storage
    .from('check-in-proofs')
    .createSignedUrl(checkIn.proof_storage_path, 3600)

  return NextResponse.json({
    checkIn: {
      ...checkIn,
      proof_url: freshUrl?.signedUrl ?? checkIn.proof_url,
    },
  })
}
