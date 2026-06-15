import { redirect } from 'next/navigation'
import { createClient, createServiceClient } from '@/lib/supabase/server'
import { isAdmin } from '@/lib/utils'
import AdminActions from './actions-ui'
import type { Application } from '@/lib/types'

export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>
}) {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user || !isAdmin(user.email)) redirect('/')

  const { status = 'pending' } = await searchParams

  const service = await createServiceClient()
  const { data: applications } = await service
    .from('applications')
    .select('*')
    .eq('status', status)
    .order('created_at', { ascending: false })

  return (
    <main className="min-h-screen bg-ink">
      <nav className="flex items-center justify-between px-8 py-6 border-b border-border">
        <span className="font-serif text-xl tracking-tight text-parchment">Atlas Passport — Admin</span>
        <span className="text-muted text-xs">{user.email}</span>
      </nav>

      <div className="max-w-5xl mx-auto px-8 py-12">
        <div className="flex items-center gap-6 mb-10">
          {['pending', 'approved', 'rejected'].map(s => (
            <a
              key={s}
              href={`/admin?status=${s}`}
              className={`text-xs tracking-widest uppercase transition-colors ${
                status === s ? 'text-gold' : 'text-muted hover:text-parchment'
              }`}
            >
              {s}
            </a>
          ))}
        </div>

        {!applications?.length ? (
          <p className="text-muted">No {status} applications.</p>
        ) : (
          <div className="space-y-4">
            {applications.map((app: Application) => (
              <ApplicationRow key={app.id} app={app} />
            ))}
          </div>
        )}
      </div>
    </main>
  )
}

function ApplicationRow({ app }: { app: Application }) {
  return (
    <div className="border border-border p-6">
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-3 mb-1">
            <h3 className="font-serif text-lg text-parchment">{app.full_name}</h3>
            <span className="text-gold text-xs tracking-widest">{app.discipline}</span>
          </div>
          <p className="text-muted text-sm mb-1">{app.email} · {app.location}</p>
          <p className="text-parchment/70 text-sm mt-3 line-clamp-2">{app.bio}</p>
          <p className="text-parchment/50 text-sm mt-2 italic line-clamp-2">"{app.why_atlas}"</p>

          <div className="flex gap-4 mt-3">
            {app.portfolio_url && (
              <a href={app.portfolio_url} target="_blank" rel="noopener noreferrer"
                className="text-gold text-xs hover:text-gold-light transition-colors">
                Portfolio →
              </a>
            )}
            {app.website && (
              <a href={app.website} target="_blank" rel="noopener noreferrer"
                className="text-gold text-xs hover:text-gold-light transition-colors">
                Website →
              </a>
            )}
          </div>

          <p className="text-muted/50 text-xs mt-3">
            Submitted {new Date(app.created_at).toLocaleDateString()}
          </p>
        </div>

        {app.status === 'pending' && <AdminActions applicationId={app.id} email={app.email} name={app.full_name} />}
      </div>
    </div>
  )
}
