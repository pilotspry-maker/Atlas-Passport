import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

async function assertAdmin() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return false
  const { data: profile } = await supabase.from('profiles').select('is_admin').eq('id', user.id).single()
  return profile?.is_admin ?? false
}

export async function GET(request: Request) {
  if (!await assertAdmin()) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { searchParams } = new URL(request.url)
  const corridorId = searchParams.get('corridor_id')
  if (!corridorId) return NextResponse.json({ error: 'corridor_id required' }, { status: 400 })

  const admin = createAdminClient()
  const { data: nodes } = await admin
    .from('nodes').select('*').eq('corridor_id', corridorId).order('sequence')

  return NextResponse.json({ nodes: nodes ?? [] })
}

export async function POST(request: Request) {
  if (!await assertAdmin()) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { corridor_id, name, description, address, hint, latitude, longitude } = await request.json()
  if (!corridor_id || !name?.trim()) {
    return NextResponse.json({ error: 'corridor_id and name are required' }, { status: 400 })
  }

  const admin = createAdminClient()

  // Auto-assign next sequence number
  const { data: maxRow } = await admin
    .from('nodes').select('sequence').eq('corridor_id', corridor_id)
    .order('sequence', { ascending: false }).limit(1).maybeSingle()

  const sequence = (maxRow?.sequence ?? 0) + 1

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

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ node })
}
