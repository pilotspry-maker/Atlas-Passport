import { NextResponse } from 'next/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { requireAdmin } from '@/lib/auth'

export async function POST(request: Request) {
  const auth = await requireAdmin()
  if (auth.response) return auth.response

  const { name, description, city, country, is_active } = await request.json()
  if (!name?.trim() || !city?.trim()) {
    return NextResponse.json({ error: 'name and city are required' }, { status: 400 })
  }

  const admin = createAdminClient()
  const { data: corridor, error } = await admin
    .from('corridors')
    .insert({
      name: name.trim(),
      description: description?.trim() || null,
      city: city.trim(),
      country: country?.trim() || 'US',
      is_active: is_active ?? true,
    })
    .select()
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ corridor })
}
