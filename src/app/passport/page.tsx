import { redirect } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import CountdownTimer from '@/components/passport/CountdownTimer'
import CorridorProgress from '@/components/passport/CorridorProgress'
import NodeCard from '@/components/nodes/NodeCard'
import type { PassportFull } from '@/types/database'

async function getPassportData(userId: string): Promise<PassportFull | null> {
  const supabase = await createClient()

  const { data: passport } = await supabase
    .from('passports')
    .select('*')
    .eq('user_id', userId)
    .in('status', ['active', 'complete'])
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!passport) return null

  const [{ data: corridor }, { data: nodes }, { data: checkIns }, { data: reward }] =
    await Promise.all([
      supabase.from('corridors').select('*').eq('id', passport.corridor_id).single(),
      supabase.from('nodes').select('*').eq('corridor_id', passport.corridor_id).order('sequence'),
      supabase.from('check_ins').select('*').eq('passport_id', passport.id),
      supabase.from('rewards').select('*').eq('corridor_id', passport.corridor_id).maybeSingle(),
    ])

  if (!corridor || !nodes) return null

  const nodesWithCheckIns = nodes.map(node => ({
    ...node,
    check_in: checkIns?.find(ci => ci.node_id === node.id) ?? null,
  }))

  return {
    ...passport,
    corridor,
    nodes: nodesWithCheckIns,
    reward: reward ?? null,
  }
}

interface Props {
  searchParams: Promise<{ submitted?: string }>
}

export default async function PassportPage({ searchParams }: Props) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/auth/login')

  const params = await searchParams
  const passport = await getPassportData(user.id)

  if (!passport) {
    redirect('/corridors')
  }

  const isExpired = passport.status === 'expired' ||
    (passport.status === 'active' && new Date(passport.expires_at).getTime() < Date.now())

  const isComplete = passport.status === 'complete'

  return (
    <main className="min-h-screen bg-atlas-black px-4 py-8 max-w-2xl mx-auto">
      {/* Header */}
      <div className="flex items-start justify-between mb-8">
        <div>
          <p className="text-xs text-atlas-gold uppercase tracking-[0.25em] mb-1">Atlas Passport</p>
          <h1 className="text-2xl font-bold text-atlas-text">{passport.corridor.name}</h1>
          <p className="text-sm text-atlas-text-dim mt-1">
            {passport.corridor.city}, {passport.corridor.country}
          </p>
        </div>

        <div className="text-right">
          <div className={`inline-block px-2 py-1 text-xs uppercase tracking-widest border ${
            isComplete
              ? 'border-atlas-gold text-atlas-gold'
              : isExpired
              ? 'border-atlas-red text-atlas-red'
              : 'border-atlas-green text-atlas-green'
          }`}>
            {isComplete ? 'Complete' : isExpired ? 'Expired' : 'Active'}
          </div>
        </div>
      </div>

      {/* Submitted confirmation */}
      {params.submitted && (
        <div className="mb-6 p-4 border border-atlas-gold/30 bg-atlas-gold/5 text-sm text-atlas-text-dim animate-fade-in">
          <span className="text-atlas-gold">✓</span> Kaelo received your proof. Review typically takes a few hours.
        </div>
      )}

      {/* Timer */}
      {!isComplete && (
        <div className="mb-8 p-6 border border-atlas-border bg-atlas-card">
          <CountdownTimer expiresAt={passport.expires_at} />
        </div>
      )}

      {/* Complete state */}
      {isComplete && (
        <div className="mb-8 p-6 border border-atlas-gold bg-atlas-gold/5 text-center animate-fade-in">
          <p className="text-atlas-gold text-2xl mb-2">✦</p>
          <h2 className="text-lg font-semibold text-atlas-gold mb-1">Corridor Complete</h2>
          <p className="text-sm text-atlas-text-dim mb-4">
            You&apos;ve earned every stamp on the {passport.corridor.name}.
          </p>
          <Link
            href="/passport/complete"
            className="inline-block px-6 py-2 bg-atlas-gold text-atlas-black text-sm font-semibold tracking-wider uppercase hover:bg-atlas-gold-light transition-colors"
          >
            Claim Reward →
          </Link>
        </div>
      )}

      {/* Progress bar */}
      <div className="mb-8 p-5 border border-atlas-border bg-atlas-card">
        <CorridorProgress nodes={passport.nodes} />
      </div>

      {/* Node list */}
      <div className="space-y-3 mb-8">
        <h2 className="text-xs uppercase tracking-widest text-atlas-muted mb-4">
          Corridor Stops
        </h2>
        {passport.nodes.map(node => (
          <NodeCard
            key={node.id}
            node={node}
            passportStatus={isExpired ? 'expired' : passport.status}
            passportId={passport.id}
          />
        ))}
      </div>

      {/* Footer nav */}
      <div className="flex items-center justify-between pt-6 border-t border-atlas-border text-xs text-atlas-muted">
        <span className="font-mono">
          {new Date(passport.activated_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}
        </span>
        <form action="/auth/signout" method="post">
          <button
            formAction="/api/auth/signout"
            className="hover:text-atlas-text transition-colors"
          >
            Sign Out
          </button>
        </form>
      </div>
    </main>
  )
}
