import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import type { Corridor } from '@/types/database'

export async function GET(request: Request) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { searchParams } = new URL(request.url)
  const id = searchParams.get('id')

  if (id) {
    const { data } = await supabase
      .from('corridors')
      .select('id, name, city, country, description')
      .eq('id', id)
      .eq('is_active', true)
      .maybeSingle()
    const corridor = data as Pick<Corridor, 'id' | 'name' | 'city' | 'country' | 'description'> | null

    return NextResponse.json({ corridor })
  }

  const { data } = await supabase
    .from('corridors')
    .select('*')
    .eq('is_active', true)
    .order('created_at')
  const corridors = data as Corridor[] | null

  return NextResponse.json({ corridors })
}
