import { redirect, notFound } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import type { Node, CheckIn } from '@/types/database'

interface Props {
  params: Promise<{ nodeId: string }>
}

type NodeWithCorridor = Node & { corridor: { id: string; name: string; city: string } }

export default async function NodeDetailPage({ params }: Props) {
  const { nodeId } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/auth/login')

  const { data: nodeData } = await supabase
    .from('nodes')
    .select('*, corridor:corridors(*)')
    .eq('id', nodeId)
    .single()
  const node = nodeData as NodeWithCorridor | null

  if (!node) notFound()

  const corridor = node.corridor

  // Find user's active passport for this corridor
  const { data: passportData } = await supabase
    .from('passports')
    .select('id, status, expires_at')
    .eq('user_id', user.id)
    .eq('corridor_id', corridor.id)
    .maybeSingle()
  const passport = passportData as { id: string; status: string; expires_at: string } | null

  const checkInData = passport
    ? await supabase
        .from('check_ins_player_view')
        .select('*')
        .eq('passport_id', passport.id)
        .eq('node_id', nodeId)
        .maybeSingle()
        .then(r => r.data)
    : null
  const checkIn = checkInData as CheckIn | null

  // eslint-disable-next-line react-hooks/purity -- server component async function, Date.now() evaluated once on the server
  const now = Date.now()
  const isPassportActive = passport?.status === 'active' &&
    new Date(passport.expires_at).getTime() > now

  const canCheckIn = isPassportActive &&
    (!checkIn || checkIn.status === 'rejected')

  return (
    <main className="min-h-screen bg-atlas-black px-4 py-8 max-w-lg mx-auto">
      <Link
        href="/passport"
        className="inline-block text-xs text-atlas-muted hover:text-atlas-text uppercase tracking-widest mb-8 transition-colors"
      >
        ← Passport
      </Link>

      {/* Header */}
      <div className="mb-6">
        <p className="text-xs text-atlas-gold uppercase tracking-[0.25em] mb-1">
          Stop {node.sequence} — {corridor.name}
        </p>
        <h1 className="text-2xl font-bold text-atlas-text">{node.name}</h1>
        {node.address && (
          <p className="text-sm text-atlas-text-dim mt-2">{node.address}</p>
        )}
      </div>

      {/* Description */}
      {node.description && (
        <div className="mb-6 text-atlas-text-dim leading-relaxed">{node.description}</div>
      )}

      {/* Kaelo's hint */}
      {node.hint && (
        <div className="mb-6 p-5 border border-atlas-gold/30 bg-atlas-gold/5">
          <p className="text-xs text-atlas-gold uppercase tracking-widest mb-2">Kaelo Says</p>
          <p className="text-sm text-atlas-text-dim italic leading-relaxed">
            &quot;{node.hint}&quot;
          </p>
        </div>
      )}

      {/* Check-in status */}
      {checkIn && (
        <div className={`mb-6 p-4 border text-sm ${
          checkIn.status === 'approved'
            ? 'border-atlas-gold text-atlas-gold bg-atlas-gold/5'
            : checkIn.status === 'pending'
            ? 'border-atlas-text-dim text-atlas-text-dim'
            : 'border-atlas-red text-atlas-red bg-atlas-red/5'
        }`}>
          <p className="font-semibold uppercase tracking-wider text-xs mb-1">
            {checkIn.status === 'approved' ? '✓ Stamp Approved' : checkIn.status === 'pending' ? '◉ Under Review' : '✕ Proof Rejected'}
          </p>
          {checkIn.status === 'approved' && checkIn.reviewed_at && (
            <p className="text-xs opacity-70">
              Stamped {new Date(checkIn.reviewed_at).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })}
            </p>
          )}
          {checkIn.status === 'rejected' && checkIn.admin_notes && (
            <p className="text-xs mt-1">Reason: {checkIn.admin_notes}</p>
          )}
        </div>
      )}

      {/* No passport */}
      {!passport && (
        <div className="mb-6 p-4 border border-atlas-border text-sm text-atlas-text-dim">
          You need an active passport for the {corridor.name} to check in here.{' '}
          <Link href={`/corridors/${corridor.id}`} className="text-atlas-gold hover:underline">
            Activate passport →
          </Link>
        </div>
      )}

      {/* CTA */}
      {canCheckIn && (
        <Link
          href={`/nodes/${nodeId}/checkin?passport=${passport!.id}`}
          className="block w-full py-4 bg-atlas-gold text-atlas-black font-bold text-sm tracking-widest uppercase text-center hover:bg-atlas-gold-light transition-colors"
        >
          Submit Proof →
        </Link>
      )}
    </main>
  )
}
