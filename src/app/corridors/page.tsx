import { redirect } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'
import type { Corridor } from '@/types/database'

type CorridorRow = Corridor & { nodes: { count: number }[] }

export default async function CorridorsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/auth/login')

  // If user has an active passport, go there
  const { data: activePassportData } = await supabase
    .from('passports')
    .select('id')
    .eq('user_id', user.id)
    .eq('status', 'active')
    .maybeSingle()
  const activePassport = activePassportData as { id: string } | null

  if (activePassport) redirect('/passport')

  const { data } = await supabase
    .from('corridors')
    .select('*, nodes(count)')
    .eq('is_active', true)
    .order('created_at')

  const corridors = data as unknown as CorridorRow[] | null

  const { data: prevData } = await supabase
    .from('passports')
    .select('corridor_id, status')
    .eq('user_id', user.id)
  const previousPassports = prevData as { corridor_id: string; status: string }[] | null

  const completedCorridorIds = new Set(
    previousPassports?.filter(p => p.status === 'complete').map(p => p.corridor_id) ?? []
  )

  return (
    <main className="min-h-screen bg-atlas-black px-4 py-8 max-w-2xl mx-auto">
      <div className="mb-10">
        <p className="text-xs text-atlas-gold uppercase tracking-[0.25em] mb-2">Choose Your Path</p>
        <h1 className="text-3xl font-bold text-atlas-text">Select a Corridor</h1>
        <p className="text-atlas-text-dim text-sm mt-2">
          Each corridor is a 72-hour journey. Once activated, the clock starts. Choose wisely.
        </p>
      </div>

      {!corridors?.length && (
        <div className="border border-atlas-border p-8 text-center text-atlas-muted">
          No corridors available yet. Check back soon.
        </div>
      )}

      <div className="space-y-4">
        {corridors?.map(corridor => {
          const nodeCount = (corridor.nodes as unknown as { count: number }[])?.[0]?.count ?? 0
          const isCompleted = completedCorridorIds.has(corridor.id)

          return (
            <Link
              key={corridor.id}
              href={`/corridors/${corridor.id}`}
              className="block border border-atlas-border bg-atlas-card hover:border-atlas-gold transition-colors p-6 group"
            >
              <div className="flex items-start justify-between gap-4">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-3 mb-1">
                    <h2 className="font-semibold text-atlas-text group-hover:text-atlas-gold transition-colors">
                      {corridor.name}
                    </h2>
                    {isCompleted && (
                      <span className="text-xs border border-atlas-gold text-atlas-gold px-1.5 py-0.5 uppercase tracking-wider">
                        ✓ Completed
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-atlas-muted mb-3">
                    {corridor.city}, {corridor.country}
                  </p>
                  {corridor.description && (
                    <p className="text-sm text-atlas-text-dim line-clamp-2">
                      {corridor.description}
                    </p>
                  )}
                </div>

                <div className="flex-shrink-0 text-right">
                  <div className="text-xl font-bold text-atlas-gold font-mono">{nodeCount}</div>
                  <div className="text-xs text-atlas-muted uppercase tracking-wide">stops</div>
                </div>
              </div>

              <div className="mt-4 pt-4 border-t border-atlas-border flex items-center justify-between">
                <div className="flex items-center gap-4 text-xs text-atlas-muted">
                  <span>72-hour window</span>
                  <span>·</span>
                  <span>Proof required at each stop</span>
                </div>
                <span className="text-xs text-atlas-gold opacity-0 group-hover:opacity-100 transition-opacity">
                  Select →
                </span>
              </div>
            </Link>
          )
        })}
      </div>

      <div className="mt-8 pt-6 border-t border-atlas-border flex justify-end">
        <form>
          <button
            formAction="/api/auth/signout"
            className="text-xs text-atlas-muted hover:text-atlas-text transition-colors"
          >
            Sign Out
          </button>
        </form>
      </div>
    </main>
  )
}
