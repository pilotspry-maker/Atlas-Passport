import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

interface Params {
  params: Promise<{ checkinId: string }>
}

export async function GET(_: Request, { params }: Params) {
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

  const admin = createAdminClient()

  const { data: checkIn } = await admin
    .from('check_ins')
    .select(`
      *,
      node:nodes(name, sequence, address, corridor:corridors(name, city)),
      profile:profiles(email, full_name),
      passport:passports(id, activated_at, expires_at, status)
    `)
    .eq('id', checkinId)
    .single()

  if (!checkIn) return NextResponse.json({ error: 'Not found' }, { status: 404 })

  // Generate a fresh signed URL for the admin view
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
