import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'

export async function POST(request: Request) {
  const supabase = await createClient()
  const { error } = await supabase.auth.signOut()
  if (error) {
    console.error('[signout] signOut error:', error.message)
  }
  return NextResponse.redirect(new URL('/auth/login', request.url))
}
