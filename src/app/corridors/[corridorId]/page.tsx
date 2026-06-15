import { redirect, notFound } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import type { Corridor, Node } from '@/types/database'

interface Props {
  params: Promise<{ corridorId: string }>
}

export default async function CorridorDetailPage({ params }: Props) {
  const { corridorId } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/auth/login')

  const [corridorRes, nodesRes, rewardRes] = await Promise.all([
    supabase.from('corridors').select('*').eq('id', corridorId).eq('is_active', true).single(),
    supabase.from('nodes').select('*').eq('corridor_id', corridorId).order('sequence'),
    supabase.from('rewards').select('title, description').eq('corridor_id', corridorId).maybeSingle(),
  ])

  const corridor = corridorRes.data as Corridor | null
  const nodes = nodesRes.data as Node[] | null
  const reward = rewardRes.data as { title: string; description: string | null } | null

  if (!corridor) notFound()

  // Check for existing passport on this corridor
  const { data: existingData } = await supabase
    .from('passports')
    .select('id, status')
    .eq('user_id', user.id)
    .eq('corridor_id', corridorId)
    .maybeSingle()
  const existingPassport = existingData as { id: string; status: string } | null

  const hasActivePassport = existingPassport?.status === 'active'
  const hasCompleted = existingPassport?.status === 'complete'

  return (
    <main className="min-h-screen bg-atlas-black px-4 py-8 max-w-2xl mx-auto">
      {/* Back */}
      <Link
        href="/corridors"
        className="inline-block text-xs text-atlas-muted hover:text-atlas-text uppercase tracking-widest mb-8 transition-colors"
      >
        ← All Corridors
      </Link>

      {/* Header */}
      <div className="mb-8">
        <p className="text-xs text-atlas-gold uppercase tracking-[0.25em] mb-2">
          {corridor.city}, {corridor.country}
        </p>
        <h1 className="text-3xl font-bold text-atlas-text mb-4">{corridor.name}</h1>
        {corridor.description && (
          <p className="text-atlas-text-dim leading-relaxed">{corridor.description}</p>
        )}
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-4 mb-8">
        {[
          { value: nodes?.length ?? 0, label: 'Stops' },
          { value: '72', label: 'Hours' },
          { value: reward ? '1' : '—', label: 'Reward' },
        ].map(({ value, label }) => (
          <div key={label} className="border border-atlas-border bg-atlas-card p-4 text-center">
            <div className="text-2xl font-bold text-atlas-gold font-mono">{value}</div>
            <div className="text-xs text-atlas-muted uppercase tracking-widest mt-1">{label}</div>
          </div>
        ))}
      </div>

      {/* Reward teaser */}
      {reward && (
        <div className="mb-8 p-4 border border-atlas-gold/30 bg-atlas-gold/5">
          <p className="text-xs text-atlas-gold uppercase tracking-widest mb-1">Reward</p>
          <p className="font-semibold text-atlas-text">{reward.title}</p>
          {reward.description && (
            <p className="text-sm text-atlas-text-dim mt-1">{reward.description}</p>
          )}
        </div>
      )}

      {/* Nodes preview */}
      <div className="mb-8">
        <h2 className="text-xs uppercase tracking-widest text-atlas-muted mb-4">The Stops</h2>
        <div className="space-y-2">
          {nodes?.map(node => (
            <div
              key={node.id}
              className="flex items-start gap-4 border border-atlas-border bg-atlas-card p-4"
            >
              <div className="w-7 h-7 flex-shrink-0 border border-atlas-border flex items-center justify-center text-xs font-mono text-atlas-muted">
                {node.sequence}
              </div>
              <div className="flex-1 min-w-0">
                <p className="font-semibold text-atlas-text">{node.name}</p>
                {node.address && (
                  <p className="text-xs text-atlas-muted mt-0.5 truncate">{node.address}</p>
                )}
                {node.description && (
                  <p className="text-sm text-atlas-text-dim mt-1 line-clamp-1">{node.description}</p>
                )}
              </div>
              <div className="text-atlas-muted text-lg">○</div>
            </div>
          ))}
        </div>
      </div>

      {/* Rules */}
      <div className="mb-8 p-4 border border-atlas-border text-sm text-atlas-text-dim space-y-2">
        <p className="text-xs uppercase tracking-widest text-atlas-muted mb-3">The Rules</p>
        <p>① The 72-hour timer starts the moment you activate your passport.</p>
        <p>② Visit each stop and upload photo proof. Kaelo will review and stamp your passport.</p>
        <p>③ Complete all stops within the window to unlock your reward.</p>
        <p>④ No timer resets. No extensions. Plan your route.</p>
      </div>

      {/* CTA */}
      <div className="flex flex-col sm:flex-row gap-3">
        {hasActivePassport ? (
          <Link
            href="/passport"
            className="flex-1 py-3 bg-atlas-gold text-atlas-black font-semibold text-sm tracking-wider uppercase text-center hover:bg-atlas-gold-light transition-colors"
          >
            View Active Passport →
          </Link>
        ) : hasCompleted ? (
          <div className="flex-1 py-3 border border-atlas-gold text-atlas-gold text-sm text-center">
            ✓ Already Completed
          </div>
        ) : (
          <Link
            href={`/passport/activate?corridor=${corridorId}`}
            className="flex-1 py-3 bg-atlas-gold text-atlas-black font-semibold text-sm tracking-wider uppercase text-center hover:bg-atlas-gold-light transition-colors"
          >
            Activate Passport — Start 72h Clock
          </Link>
        )}
        <Link
          href="/corridors"
          className="flex-1 py-3 border border-atlas-border text-atlas-text-dim text-sm text-center hover:border-atlas-gold hover:text-atlas-gold transition-colors uppercase tracking-wider"
        >
          Choose Different Corridor
        </Link>
      </div>
    </main>
  )
}
