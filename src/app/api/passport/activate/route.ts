import { NextResponse } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import { sendPassportActivatedEmail } from '@/lib/email'
import type { Passport, Corridor } from '@/types/database'

export async function POST(request: Request) {
  try {
    const supabase = await createClient()
    const { data: { user } } = await supabase.auth.getUser()

    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    let body: { corridorId?: string }
    try {
      body = await request.json()
    } catch {
      return NextResponse.json({ error: 'Invalid request body' }, { status: 400 })
    }

    const { corridorId } = body
    if (!corridorId) {
      return NextResponse.json({ error: 'corridorId required' }, { status: 400 })
    }

    const admin = createAdminClient()

    // Verify corridor exists and is active
    const { data: corridorData, error: corridorError } = await admin
      .from('corridors')
      .select('id, name, city, country')
      .eq('id', corridorId)
      .eq('is_active', true)
      .single()

    if (corridorError) {
      console.error('[activate] Corridor lookup error:', corridorError.message)
    }

    const corridor = corridorData as Pick<Corridor, 'id' | 'name' | 'city' | 'country'> | null
    if (!corridor) {
      return NextResponse.json({ error: 'Corridor not found or inactive' }, { status: 404 })
    }

    // Check for existing active passport (any corridor)
    const { data: existingActiveData, error: activeErr } = await admin
      .from('passports')
      .select('id')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .maybeSingle()

    if (activeErr) console.error('[activate] Active passport check error:', activeErr.message)

    const existingActive = existingActiveData as { id: string } | null
    if (existingActive) {
      return NextResponse.json({ error: 'You already have an active passport' }, { status: 409 })
    }

    // Check for existing passport on this specific corridor
    const { data: existingForCorridorData, error: corridorPassportErr } = await admin
      .from('passports')
      .select('id, status')
      .eq('user_id', user.id)
      .eq('corridor_id', corridorId)
      .maybeSingle()

    if (corridorPassportErr) console.error('[activate] Corridor passport check error:', corridorPassportErr.message)

    const existingForCorridor = existingForCorridorData as { id: string; status: string } | null
    if (existingForCorridor) {
      return NextResponse.json({ error: 'You have already started this corridor' }, { status: 409 })
    }

    // Ensure profile exists (create if trigger missed it)
    const { data: profileCheck } = await admin
      .from('profiles')
      .select('id')
      .eq('id', user.id)
      .maybeSingle()

    if (!profileCheck) {
      console.warn('[activate] Profile missing for user', user.id, '— creating now')
      const { error: profileInsertErr } = await admin
        .from('profiles')
        .insert({ id: user.id, email: user.email ?? '' })

      if (profileInsertErr) {
        console.error('[activate] Profile insert error:', profileInsertErr.message)
        return NextResponse.json(
          { error: 'Failed to create user profile. Please sign out and back in.' },
          { status: 500 }
        )
      }
    }

    // Get node count for email
    const { count: nodeCount } = await admin
      .from('nodes')
      .select('*', { count: 'exact', head: true })
      .eq('corridor_id', corridorId)
      .eq('is_active', true)

    // Create the passport
    const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString()

    const { data: passportData, error: insertError } = await admin
      .from('passports')
      .insert({
        user_id: user.id,
        corridor_id: corridorId,
        expires_at: expiresAt,
        status: 'active',
      })
      .select()
      .single()

    if (insertError) {
      console.error('[activate] Passport insert error:', insertError.message, insertError.details)
      return NextResponse.json(
        { error: `Failed to create passport: ${insertError.message}` },
        { status: 500 }
      )
    }

    const passport = passportData as Passport | null
    if (!passport) {
      return NextResponse.json({ error: 'Passport was not created' }, { status: 500 })
    }

    // Get user profile for email
    const { data: profileData } = await admin
      .from('profiles')
      .select('email, full_name')
      .eq('id', user.id)
      .single()
    const profile = profileData as { email: string; full_name: string | null } | null

    // Send activation email (non-blocking — never blocks the response)
    sendPassportActivatedEmail({
      to: profile?.email ?? user.email ?? '',
      name: profile?.full_name ?? 'Traveller',
      corridorName: corridor.name,
      city: corridor.city,
      expiresAt,
      totalNodes: nodeCount ?? 0,
    }).catch(err => console.error('[activate] Email send error:', err))

    return NextResponse.json({ passportId: passport.id, expiresAt })
  } catch (err) {
    console.error('[activate] Unhandled error:', err)
    return NextResponse.json(
      { error: 'An unexpected server error occurred. Please try again.' },
      { status: 500 }
    )
  }
}
