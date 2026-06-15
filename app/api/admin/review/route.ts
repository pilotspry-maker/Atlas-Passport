import { NextResponse } from 'next/server'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { isAdmin, slugify } from '@/lib/utils'
import { sendApplicationApproved, sendApplicationRejected } from '@/lib/resend'

export async function POST(request: Request) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user || !isAdmin(user.email)) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { applicationId, action, email, name } = await request.json()

  if (!applicationId || !action || !email || !name) {
    return NextResponse.json({ error: 'Missing fields' }, { status: 400 })
  }

  const service = await createServiceClient()

  const { error: updateError } = await service
    .from('applications')
    .update({ status: action === 'approve' ? 'approved' : 'rejected', reviewed_at: new Date().toISOString(), reviewed_by: user.id })
    .eq('id', applicationId)

  if (updateError) {
    return NextResponse.json({ error: 'Failed to update application' }, { status: 500 })
  }

  if (action === 'approve') {
    const { data: app } = await service
      .from('applications')
      .select('*')
      .eq('id', applicationId)
      .single()

    if (app) {
      const slug = slugify(name)

      await service.from('artists').insert({
        full_name: app.full_name,
        bio: app.bio,
        location: app.location,
        website: app.website,
        instagram: app.instagram,
        portfolio_url: app.portfolio_url,
        discipline: app.discipline,
        slug,
        status: 'approved',
      })

      const loginUrl = `${process.env.NEXT_PUBLIC_APP_URL}/login`
      await sendApplicationApproved(email, name, loginUrl)
    }
  } else {
    await sendApplicationRejected(email, name)
  }

  return NextResponse.json({ success: true })
}
