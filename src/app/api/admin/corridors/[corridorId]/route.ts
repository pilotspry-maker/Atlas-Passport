import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

interface Params { params: Promise<{ corridorId: string }> }

async function assertAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return false
  const { data: profile } = await supabase.from('profiles').select('is_admin').eq('id', user.id).single()
  return profile?.is_admin ?? false
}

export async function GET(_: Request, { params }: Params) {
  const { corridorId } = await params
  if (!await assertAdmin()) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const admin = createAdminClient()
  const { data: corridor, error } = await admin.from('corridors').select('*').eq('id', corridorId).single()
  if (error || !corridor) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json({ corridor })
}

export async function PATCH(request: Request, { params }: Params) {
  const { corridorId } = await params
  if (!await assertAdmin()) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const body = await request.json()
  const updates: Record<string, unknown> = {}
  if (body.name !== undefined)        updates.name        = body.name.trim()
  if (body.description !== undefined) updates.description = body.description?.trim() || null
  if (body.city !== undefined)        updates.city        = body.city.trim()
  if (body.country !== undefined)     updates.country     = body.country.trim()
  if (body.is_active !== undefined)   updates.is_active   = body.is_active

  const admin = createAdminClient()
  const { data: corridor, error } = await admin
    .from('corridors').update(updates).eq('id', corridorId).select().single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ corridor })
}

export async function DELETE(_: Request, { params }: Params) {
  const { corridorId } = await params
  if (!await assertAdmin()) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const admin = createAdminClient()
  const { error } = await admin.from('corridors').delete().eq('id', corridorId)
  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ ok: true })
}
