import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import AdminNav from '@/components/admin/AdminNav'
import type { Corridor } from '@/types/database'

type CorridorRow = Corridor & {
  nodes: { count: number }[]
  rewards: { title: string }[]
}

export const revalidate = 0

export default async function AdminCorridorsPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/auth/login')
  const { data: profileData } = await supabase.from('profiles').select('is_admin').eq('id', user.id).single()
  if (!(profileData as { is_admin?: boolean } | null)?.is_admin) redirect('/')

  const admin = createAdminClient()

  const { data } = await admin
    .from('corridors')
    .select('*, nodes(count), rewards(title)')
    .order('created_at')

  const corridors = data as unknown as CorridorRow[] | null

  return (
    <div>
      <AdminNav active="corridors" />

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-xl font-bold text-atlas-text">Corridors ({corridors?.length ?? 0})</h1>
        <Link
          href="/admin/corridors/new"
          className="px-4 py-2 bg-atlas-gold text-atlas-black text-xs font-semibold uppercase tracking-wider hover:bg-atlas-gold-light transition-colors"
        >
          + New Corridor
        </Link>
      </div>

      {!corridors?.length && (
        <div className="border border-dashed border-atlas-border p-12 text-center text-atlas-muted text-sm">
          No corridors yet.{' '}
          <Link href="/admin/corridors/new" className="text-atlas-gold hover:underline">
            Create the first one →
          </Link>
        </div>
      )}

      <div className="space-y-3">
        {corridors?.map(corridor => {
          const nodeCount = (corridor.nodes as unknown as { count: number }[])?.[0]?.count ?? 0
          const rewards = corridor.rewards as { title: string }[]

          return (
            <div
              key={corridor.id}
              className={`border ${corridor.is_active ? 'border-atlas-border' : 'border-atlas-border/30 opacity-60'} bg-atlas-card p-5`}
            >
              <div className="flex items-start justify-between gap-4">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-3 mb-1">
                    <h2 className="font-semibold text-atlas-text">{corridor.name}</h2>
                    <span className={`text-xs px-1.5 py-0.5 border uppercase tracking-wider flex-shrink-0 ${
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

                <div className="flex items-start gap-4 flex-shrink-0">
                  <div className="text-right">
                    <div className="text-xl font-bold text-atlas-gold font-mono">{nodeCount}</div>
                    <div className="text-xs text-atlas-muted">stops</div>
                  </div>
                  <Link
                    href={`/admin/corridors/${corridor.id}/edit`}
                    className="text-xs text-atlas-gold hover:text-atlas-gold-light uppercase tracking-widest transition-colors mt-1"
                  >
                    Edit →
                  </Link>
                </div>
              </div>

              {rewards?.length > 0 && (
                <div className="mt-3 pt-3 border-t border-atlas-border">
                  <p className="text-xs text-atlas-muted">
                    Reward: <span className="text-atlas-text-dim">{rewards[0].title}</span>
                  </p>
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
