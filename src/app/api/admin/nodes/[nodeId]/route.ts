import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { requireAdmin } from '@/lib/auth'

interface Params { params: Promise<{ nodeId: string }> }

export async function PATCH(request: Request, { params }: Params) {
  const { nodeId } = await params
  const auth = await requireAdmin()
  if (auth.response) return auth.response

  const body = await request.json()
  const updates: {
    name?: string
    description?: string | null
    address?: string | null
    hint?: string | null
    sequence?: number
    latitude?: number | null
    longitude?: number | null
    is_active?: boolean
  } = {}
  if (body.name        !== undefined) updates.name        = body.name.trim()
  if (body.description !== undefined) updates.description = body.description?.trim() || null
  if (body.address     !== undefined) updates.address     = body.address?.trim() || null
  if (body.hint        !== undefined) updates.hint        = body.hint?.trim() || null
  if (body.sequence    !== undefined) updates.sequence    = parseInt(body.sequence)
  if (body.latitude    !== undefined) updates.latitude    = body.latitude ? parseFloat(body.latitude) : null
  if (body.longitude   !== undefined) updates.longitude   = body.longitude ? parseFloat(body.longitude) : null
  if (body.is_active   !== undefined) updates.is_active   = body.is_active

  const admin = createAdminClient()
  const { data: node, error } = await admin
    .from('nodes').update(updates).eq('id', nodeId).select().single()

  if (error) {
    console.error('[route] DB error:', error.message)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
  return NextResponse.json({ node })
}

export async function DELETE(_: Request, { params }: Params) {
  const { nodeId } = await params
  const auth = await requireAdmin()
  if (auth.response) return auth.response

  const admin = createAdminClient()
  const { error } = await admin.from('nodes').delete().eq('id', nodeId)
  if (error) {
    console.error('[route] DB error:', error.message)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
  return NextResponse.json({ ok: true })
}
