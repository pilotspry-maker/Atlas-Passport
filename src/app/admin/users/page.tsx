import { createAdminClient } from '@/lib/supabase/admin'
import AdminNav from '@/components/admin/AdminNav'
import { formatDate } from '@/lib/utils'

export const revalidate = 0

type UserRow = {
  id: string
  email: string
  full_name: string | null
  is_admin: boolean
  created_at: string
  passports: Array<{
    id: string
    status: string
    activated_at: string
    expires_at: string
    corridor: { name: string } | null
  }>
}

export default async function AdminUsersPage() {
  const admin = createAdminClient()

  const { data } = await admin
    .from('profiles')
    .select('id, email, full_name, is_admin, created_at, passports(id, status, activated_at, expires_at, corridor:corridors(name))')
    .order('created_at', { ascending: false })

  const users = data as unknown as UserRow[] | null

  return (
    <div>
      <AdminNav active="users" />

      <div className="flex items-center justify-between mb-6">
        <h1 className="text-xl font-bold text-atlas-text">Users ({users?.length ?? 0})</h1>
      </div>

      <div className="space-y-3">
        {users?.map(user => {
          const activePassport = user.passports?.find(p => p.status === 'active')
          const completedCount = user.passports?.filter(p => p.status === 'complete').length ?? 0

          return (
            <div key={user.id} className="border border-atlas-border bg-atlas-card p-5">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <div className="flex items-center gap-2 mb-1">
                    <h2 className="font-semibold text-atlas-text">
                      {user.full_name ?? user.email}
                    </h2>
                    {user.is_admin && (
                      <span className="text-xs border border-atlas-gold text-atlas-gold px-1.5 py-0.5 uppercase tracking-wider">
                        Admin
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-atlas-text-dim">{user.email}</p>
                  <p className="text-xs text-atlas-muted mt-0.5">Joined {formatDate(user.created_at)}</p>
                </div>

                <div className="text-right text-xs">
                  <div className="text-atlas-gold font-bold font-mono">{completedCount}</div>
                  <div className="text-atlas-muted uppercase tracking-wide">completed</div>
                </div>
              </div>

              {activePassport && (
                <div className="mt-3 pt-3 border-t border-atlas-border">
                  <div className="flex items-center gap-2">
                    <span className="w-1.5 h-1.5 rounded-full bg-atlas-green inline-block" />
                    <span className="text-xs text-atlas-text-dim">
                      Active: {activePassport.corridor?.name}
                    </span>
                    <span className="text-xs text-atlas-muted">
                      — expires{' '}
                      {new Date(activePassport.expires_at).toLocaleString('en-US', {
                        month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
                      })}
                    </span>
                  </div>
                </div>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
