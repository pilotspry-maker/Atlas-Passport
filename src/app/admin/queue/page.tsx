import Link from 'next/link'
import Image from 'next/image'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/admin'
import AdminNav from '@/components/admin/AdminNav'
import { formatDateTime } from '@/lib/utils'

export const revalidate = 0

type QueueItem = {
  id: string
  proof_url: string
  notes: string | null
  submitted_at: string
  node: { name: string; sequence: number; corridor: { name: string; city: string } } | null
  profile: { email: string; full_name: string | null } | null
  passport: { activated_at: string; expires_at: string } | null
}

export default async function AdminQueuePage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/auth/login')
  const { data: profileData } = await supabase.from('profiles').select('is_admin').eq('id', user.id).single()
  if (!(profileData as { is_admin?: boolean } | null)?.is_admin) redirect('/')

  const admin = createAdminClient()

  const [{ data: rawCheckIns }, { data: rawStats }] = await Promise.all([
    admin
      .from('check_ins')
      .select('id, proof_url, notes, submitted_at, node:nodes(name, sequence, corridor:corridors(name, city)), profile:profiles(email, full_name), passport:passports(activated_at, expires_at)')
      .eq('status', 'pending')
      .order('submitted_at', { ascending: true }),
    admin
      .from('check_ins')
      .select('status'),
  ])

  const checkIns = rawCheckIns as unknown as QueueItem[] | null
  const stats = rawStats as { status: string }[] | null

  const total   = stats?.length ?? 0
  const pending  = stats?.filter(s => s.status === 'pending').length  ?? 0
  const approved = stats?.filter(s => s.status === 'approved').length ?? 0
  const rejected = stats?.filter(s => s.status === 'rejected').length ?? 0

  return (
    <div>
      <AdminNav active="queue" />

      {/* Stats */}
      <div className="grid grid-cols-4 gap-4 mb-8">
        {[
          { label: 'Total',    value: total,    color: 'text-atlas-text' },
          { label: 'Pending',  value: pending,  color: 'text-atlas-text-dim' },
          { label: 'Approved', value: approved, color: 'text-atlas-gold' },
          { label: 'Rejected', value: rejected, color: 'text-atlas-red-light' },
        ].map(s => (
          <div key={s.label} className="border border-atlas-border bg-atlas-card p-4 text-center">
            <div className={`text-2xl font-bold font-mono ${s.color}`}>{s.value}</div>
            <div className="text-xs text-atlas-muted uppercase tracking-widest mt-1">{s.label}</div>
          </div>
        ))}
      </div>

      <h2 className="text-xs uppercase tracking-widest text-atlas-muted mb-4">
        Pending Review ({pending})
      </h2>

      {!checkIns?.length ? (
        <div className="border border-atlas-border p-12 text-center text-atlas-muted">
          <p className="text-2xl mb-2">✓</p>
          <p className="text-sm">Queue is clear. All check-ins have been reviewed.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {checkIns.map(ci => {
            const isExpiringSoon = ci.passport
              ? new Date(ci.passport.expires_at).getTime() - Date.now() < 6 * 60 * 60 * 1000
              : false

            return (
              <Link
                key={ci.id}
                href={`/admin/checkins/${ci.id}`}
                className="flex items-center gap-4 border border-atlas-border bg-atlas-card hover:border-atlas-gold p-4 transition-colors group"
              >
                <div className="w-16 h-16 flex-shrink-0 bg-atlas-dark border border-atlas-border overflow-hidden relative">
                  <Image src={ci.proof_url} alt="Proof" fill className="object-cover" sizes="64px" />
                </div>

                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1">
                    <span className="text-xs font-mono text-atlas-gold">#{ci.node?.sequence}</span>
                    <span className="font-semibold text-atlas-text truncate">{ci.node?.name}</span>
                    {isExpiringSoon && (
                      <span className="text-xs border border-atlas-red text-atlas-red px-1 flex-shrink-0">EXPIRING</span>
                    )}
                  </div>
                  <p className="text-xs text-atlas-muted truncate">
                    {ci.node?.corridor?.name} — {ci.node?.corridor?.city}
                  </p>
                  <p className="text-xs text-atlas-text-dim mt-0.5 truncate">
                    {ci.profile?.full_name ?? ci.profile?.email}
                  </p>
                  {ci.notes && (
                    <p className="text-xs text-atlas-muted mt-1 truncate italic">&quot;{ci.notes}&quot;</p>
                  )}
                </div>

                <div className="flex-shrink-0 text-right">
                  <p className="text-xs text-atlas-muted">{formatDateTime(ci.submitted_at)}</p>
                  <p className="text-xs text-atlas-gold opacity-0 group-hover:opacity-100 transition-opacity mt-1">
                    Review →
                  </p>
                </div>
              </Link>
            )
          })}
        </div>
      )}
    </div>
  )
}
