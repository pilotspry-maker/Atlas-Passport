import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'

export async function POST(request: Request) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: profile } = await supabase
    .from('profiles').select('is_admin').eq('id', user.id).single()
  if (!profile?.is_admin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { name, description, city, country, is_active } = await request.json()
  if (!name?.trim() || !city?.trim()) {
    return NextResponse.json({ error: 'name and city are required' }, { status: 400 })
  }

  const admin = createAdminClient()
  const { data: corridor, error } = await admin
    .from('corridors')
    .insert({ name: name.trim(), description: description?.trim() || null, city: city.trim(), country: country?.trim() || 'US', is_active: is_active ?? true })
    .select()
    .single()

  if (error) return NextResponse.json({ error: error.message }, { status: 500 })
  return NextResponse.json({ corridor })
}
