import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

interface Params { params: Promise<{ nodeId: string }> }

async function assertAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return false
  const { data: profile } = await supabase.from('profiles').select('is_admin').eq('id', user.id).single()
  return profile?.is_admin ?? false
}

export async function PATCH(request: Request, { params }: Params) {
  const { nodeId } = await params
  if (!await assertAdmin()) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const body = await request.json()
  const updates: Record<string, unknown> = {}
  if (body.name !== undefined)        updates.name        = body.name.trim()
  if (body.description !== undefined) updates.description = body.description?.trim() || null
  if (body.address !== undefined)     updates.address     = body.address?.trim() || null
  if (body.hint !== undefined)        updates.hint        = body.hint?.trim() || null
  if (body.sequence !== undefined)    updates.sequence    = parseInt(body.sequence)
  if (body.latitude !== undefined)    updates.latitude    = body.latitude ? parseFloat(body.latitude) : null
  if (body.longitude !== undefined)   updates.longitude   = body.longitude ? parseFloat(body.longitude) : null
  if (body.is_active !== undefined)   updates.is_active   = body.is_active

  const admin = createAdminClient()
  const { data: node, error } = await admin
    .from('nodes').update(updates).eq('id', nodeId).select().single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ node })
}

export async function DELETE(_: Request, { params }: Params) {
  const { nodeId } = await params
  if (!await assertAdmin()) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const admin = createAdminClient()
  const { error } = await admin.from('nodes').delete().eq('id', nodeId)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}
