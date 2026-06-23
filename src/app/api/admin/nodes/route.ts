import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { requireAdmin } from '@/lib/auth'

export async function GET(request: Request) {
  const auth = await requireAdmin()
  if (auth.response) return auth.response

  const { searchParams } = new URL(request.url)
  const corridorId = searchParams.get('corridor_id')
  if (!corridorId) return NextResponse.json({ error: 'corridor_id required' }, { status: 400 })

  const admin = createAdminClient()
  const { data: nodes } = await admin
    .from('nodes').select('*').eq('corridor_id', corridorId).order('sequence')

  return NextResponse.json({ nodes: nodes ?? [] })
}

export async function POST(request: Request) {
  const auth = await requireAdmin()
  if (auth.response) return auth.response

  const { corridor_id, name, description, address, hint, latitude, longitude } = await request.json()
  if (!corridor_id || !name?.trim()) {
    return NextResponse.json({ error: 'corridor_id and name are required' }, { status: 400 })
  }

  const admin = createAdminClient()

  const { data: maxRow } = await admin
    .from('nodes').select('sequence').eq('corridor_id', corridor_id)
    .order('sequence', { ascending: false }).limit(1).maybeSingle()

  const sequence = ((maxRow as { sequence?: number } | null)?.sequence ?? 0) + 1

  const { data: node, error } = await admin
    .from('nodes')
    .insert({
      corridor_id,
      name: name.trim(),
      description: description?.trim() || null,
      address: address?.trim() || null,
      hint: hint?.trim() || null,
      sequence,
      latitude: latitude ? parseFloat(latitude) : null,
      longitude: longitude ? parseFloat(longitude) : null,
      is_active: true,
    })
    .select().single()

  if (error) {
    console.error('[route] DB error:', error.message)
    return NextResponse.json({ error: 'Internal server error' }, { status: 500 })
  }
  return NextResponse.json({ node })
}
