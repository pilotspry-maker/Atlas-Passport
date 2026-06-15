import { redirect, notFound } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import ProofUploader from '@/components/nodes/ProofUploader'
import type { Node } from '@/types/database'

interface Props {
  params: Promise<{ nodeId: string }>
  searchParams: Promise<{ passport?: string }>
}

type NodeWithCorridorName = Node & { corridor: { name: string } | null }

export default async function CheckInPage({ params, searchParams }: Props) {
  const { nodeId } = await params
  const { passport: passportId } = await searchParams

  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/auth/login')

  if (!passportId) redirect(`/nodes/${nodeId}`)

  const [nodeRes, passportRes] = await Promise.all([
    supabase.from('nodes').select('*, corridor:corridors(name)').eq('id', nodeId).single(),
    supabase
      .from('passports')
      .select('id, status, expires_at, corridor_id')
      .eq('id', passportId)
      .eq('user_id', user.id)
      .single(),
  ])

  const node = nodeRes.data as NodeWithCorridorName | null
  const passport = passportRes.data as { id: string; status: string; expires_at: string; corridor_id: string } | null

  if (!node || !passport) notFound()

  const isExpired = passport.status !== 'active' ||
    new Date(passport.expires_at).getTime() < Date.now()

  if (isExpired) redirect('/passport')

  // Check for existing approved check-in
  const { data: existingData } = await supabase
    .from('check_ins')
    .select('status')
    .eq('passport_id', passportId)
    .eq('node_id', nodeId)
    .maybeSingle()
  const existingCheckIn = existingData as { status: string } | null

  if (existingCheckIn?.status === 'approved') redirect('/passport')

  const corridorName = node.corridor?.name ?? ''

  return (
    <main className="min-h-screen bg-atlas-black px-4 py-8 max-w-lg mx-auto">
      <Link
        href={`/nodes/${nodeId}`}
        className="inline-block text-xs text-atlas-muted hover:text-atlas-text uppercase tracking-widest mb-8 transition-colors"
      >
        ← Node Details
      </Link>

      {/* Header */}
      <div className="mb-8">
        <p className="text-xs text-atlas-gold uppercase tracking-[0.25em] mb-1">
          Stop {node.sequence} — {corridorName}
        </p>
        <h1 className="text-2xl font-bold text-atlas-text mb-1">{node.name}</h1>
        <p className="text-sm text-atlas-text-dim">
          Upload a photo proving you&apos;re here. Kaelo will review and stamp your passport.
        </p>
      </div>

      {existingCheckIn?.status === 'rejected' && (
        <div className="mb-6 p-4 border border-atlas-red/40 bg-atlas-red/5 text-sm text-atlas-text-dim">
          Your previous submission was rejected. Upload new proof to try again.
        </div>
      )}

      <ProofUploader passportId={passportId} nodeId={nodeId} />
    </main>
  )
}
