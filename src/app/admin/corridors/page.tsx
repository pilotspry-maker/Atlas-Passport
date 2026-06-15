import { createAdminClient } from '@/lib/supabase/admin'
import AdminNav from '@/components/admin/AdminNav'

export const revalidate = 0

export default async function AdminCorridorsPage() {
  const admin = createAdminClient()

  const { data: corridors } = await admin
    .from('corridors')
    .select('*, nodes(count), rewards(title)')
    .order('created_at')

  return (
    <div>
      <AdminNav active="corridors" />

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-xl font-bold text-atlas-text">Corridors</h1>
        <span className="text-xs text-atlas-muted">
          Manage corridors via Supabase Studio or seed.sql
        </span>
      </div>

      <div className="space-y-3">
        {corridors?.map(corridor => {
          const nodeCount = (corridor.nodes as unknown as { count: number }[])?.[0]?.count ?? 0
          const rewards = corridor.rewards as { title: string }[]

          return (
            <div
              key={corridor.id}
              className={`border ${corridor.is_active ? 'border-atlas-border' : 'border-atlas-border/40 opacity-50'} bg-atlas-card p-5`}
            >
              <div className="flex items-start justify-between gap-4">
                <div>
                  <div className="flex items-center gap-3 mb-1">
                    <h2 className="font-semibold text-atlas-text">{corridor.name}</h2>
                    <span className={`text-xs px-1.5 py-0.5 border uppercase tracking-wider ${
                      corridor.is_active
                        ? 'border-atlas-green text-atlas-green'
                        : 'border-atlas-muted text-atlas-muted'
                    }`}>
                      {corridor.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </div>
                  <p className="text-xs text-atlas-muted">{corridor.city}, {corridor.country}</p>
                  {corridor.description && (
                    <p className="text-sm text-atlas-text-dim mt-2 line-clamp-2">{corridor.description}</p>
                  )}
                </div>

                <div className="text-right flex-shrink-0">
                  <div className="text-xl font-bold text-atlas-gold font-mono">{nodeCount}</div>
                  <div className="text-xs text-atlas-muted">stops</div>
                </div>
              </div>

              {rewards?.length > 0 && (
                <div className="mt-3 pt-3 border-t border-atlas-border">
                  <p className="text-xs text-atlas-muted">
                    Reward: <span className="text-atlas-text-dim">{rewards[0].title}</span>
                  </p>
                </div>
              )}

              <div className="mt-3 pt-3 border-t border-atlas-border">
                <p className="text-xs text-atlas-muted font-mono">{corridor.id}</p>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
