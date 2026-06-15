import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function GET(request: Request) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { searchParams } = new URL(request.url)
  const id = searchParams.get('id')

  if (id) {
    const { data: corridor } = await supabase
      .from('corridors')
      .select('id, name, city, country, description')
      .eq('id', id)
      .eq('is_active', true)
      .single()

    return NextResponse.json({ corridor })
  }

  const { data: corridors } = await supabase
    .from('corridors')
    .select('*')
    .eq('is_active', true)
    .order('created_at')

  return NextResponse.json({ corridors })
}
