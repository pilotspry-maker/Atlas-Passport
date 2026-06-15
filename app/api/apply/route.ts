import { NextResponse } from 'next/server'
import { createServiceClient } from '@/lib/supabase/server'
import {
  sendApplicationConfirmation,
  notifyAdminNewApplication,
} from '@/lib/resend'

export async function POST(request: Request) {
  const body = await request.json()

  const { email, full_name, bio, location, discipline, website, instagram, portfolio_url, why_atlas } = body

  if (!email || !full_name || !bio || !location || !discipline || !why_atlas) {
    return NextResponse.json({ error: 'Missing required fields.' }, { status: 400 })
  }

  const supabase = await createServiceClient()

  const { data, error } = await supabase
    .from('applications')
    .insert({
      email,
      full_name,
      bio,
      location,
      discipline,
      website: website || null,
      instagram: instagram || null,
      portfolio_url: portfolio_url || null,
      why_atlas,
    })
    .select('id')
    .single()

  if (error) {
    console.error('Application insert error:', error)
    return NextResponse.json({ error: 'Failed to submit application.' }, { status: 500 })
  }

  await Promise.allSettled([
    sendApplicationConfirmation(email, full_name),
    notifyAdminNewApplication(data.id, full_name, email),
  ])

  return NextResponse.json({ success: true })
}
