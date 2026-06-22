import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { requireAdmin } from '@/lib/auth'

interface Params { params: Promise<{ corridorId: string }> }

export async function GET(_: Request, { params }: Params) {
  const { corridorId } = await params
  const auth = await requireAdmin()
  if (auth.response) return auth.response

  const admin = createAdminClient()
  const { data: corridor, error } = await admin
    .from('corridors').select('*').eq('id', corridorId).single()

  if (error || !corridor) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json({ corridor })
}

export async function PATCH(request: Request, { params }: Params) {
  const { corridorId } = await params
  const auth = await requireAdmin()
  if (auth.response) return auth.response

  const body = await request.json()
  const updates: {
    name?: string
    description?: string | null
    city?: string
    country?: string
    is_active?: boolean
  } = {}
  if (body.name        !== undefined) updates.name        = body.name.trim()
  if (body.description !== undefined) updates.description = body.description?.trim() || null
  if (body.city        !== undefined) updates.city        = body.city.trim()
  if (body.country     !== undefined) updates.country     = body.country.trim()
  if (body.is_active   !== undefined) updates.is_active   = body.is_active

  const admin = createAdminClient()
  const { data: corridor, error } = await admin
    .from('corridors').update(updates).eq('id', corridorId).select().single()

  if (error) {
    console.error('[route] DB error:', error.message)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
  return NextResponse.json({ corridor })
}

export async function DELETE(_: Request, { params }: Params) {
  const { corridorId } = await params
  const auth = await requireAdmin()
  if (auth.response) return auth.response

  const admin = createAdminClient()
  const { error } = await admin.from('corridors').delete().eq('id', corridorId)
  if (error) {
    console.error('[route] DB error:', error.message)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
  return NextResponse.json({ ok: true })
}
