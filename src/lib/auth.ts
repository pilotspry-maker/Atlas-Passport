import { NextResponse } from 'next/server'
import { createClient } from './supabase/server'
import type { User } from '@supabase/supabase-js'

type AuthOk   = { user: User;  response: null }
type AuthFail = { user: null; response: NextResponse }
type AuthResult = AuthOk | AuthFail

export async function requireUser(): Promise<AuthResult> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) {
    return { user: null, response: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) }
  }
  return { user, response: null }
}

export async function requireAdmin(): Promise<AuthResult> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) {
    return { user: null, response: NextResponse.json({ error: 'Unauthorized' }, { status: 401 }) }
  }

  const { data } = await supabase
    .from('profiles')
    .select('is_admin')
    .eq('id', user.id)
    .single()

  const isAdmin = (data as { is_admin?: boolean } | null)?.is_admin

  if (!isAdmin) {
    return { user: null, response: NextResponse.json({ error: 'Forbidden' }, { status: 403 }) }
  }

  return { user, response: null }
}
