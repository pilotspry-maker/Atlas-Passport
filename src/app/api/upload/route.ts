import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import type { Passport } from '@/types/database'

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
const MAX_SIZE = 10 * 1024 * 1024 // 10MB

export async function POST(request: Request) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { passportId, nodeId, fileType, fileSize } = await request.json()

  if (!passportId || !nodeId || !fileType) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
  }

  if (!ALLOWED_TYPES.includes(fileType)) {
    return NextResponse.json({ error: 'Invalid file type' }, { status: 400 })
  }

  if (fileSize > MAX_SIZE) {
    return NextResponse.json({ error: 'File too large (max 10MB)' }, { status: 400 })
  }

  const admin = createAdminClient()

  // Verify passport belongs to user and is active (admin client for reliable reads)
  const { data: passportData } = await admin
    .from('passports')
    .select('id, status, expires_at')
    .eq('id', passportId)
    .eq('user_id', user.id)
    .single()
  const passport = passportData as Pick<Passport, 'id' | 'status' | 'expires_at'> | null

  if (!passport || passport.status !== 'active') {
    return NextResponse.json({ error: 'Passport not active' }, { status: 403 })
  }

  if (new Date(passport.expires_at).getTime() < Date.now()) {
    return NextResponse.json({ error: 'Passport expired' }, { status: 403 })
  }

  const ext = fileType.split('/')[1].replace('jpeg', 'jpg')
  const storagePath = `${user.id}/${passportId}/${nodeId}/${Date.now()}.${ext}`

  const { data, error } = await admin.storage
    .from('check-in-proofs')
    .createSignedUploadUrl(storagePath)

  if (error || !data) {
    console.error('Signed URL error:', error)
    return NextResponse.json({ error: 'Failed to generate upload URL' }, { status: 500 })
  }

  return NextResponse.json({
    signedUrl: data.signedUrl,
    storagePath,
  })
}
