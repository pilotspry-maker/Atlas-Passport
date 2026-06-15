'use client'

import { useState, useEffect } from 'react'
import { useParams, useRouter } from 'next/navigation'
import Image from 'next/image'
import Link from 'next/link'

interface CheckInDetail {
  id: string
  status: string
  proof_url: string
  notes: string | null
  admin_notes: string | null
  submitted_at: string
  node: {
    name: string
    sequence: number
    address: string | null
    corridor: { name: string; city: string }
  }
  profile: { email: string; full_name: string | null }
  passport: { id: string; activated_at: string; expires_at: string; status: string }
}

export default function CheckInReviewPage() {
  const { checkinId } = useParams<{ checkinId: string }>()
  const router = useRouter()
  const [checkIn, setCheckIn] = useState<CheckInDetail | null>(null)
  const [loading, setLoading] = useState(true)
  const [adminNotes, setAdminNotes] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetch(`/api/admin/checkins/${checkinId}`)
      .then(r => r.json())
      .then(data => {
        setCheckIn(data.checkIn)
        setAdminNotes(data.checkIn?.admin_notes ?? '')
        setLoading(false)
      })
      .catch(() => setLoading(false))
  }, [checkinId])

  async function handleAction(action: 'approve' | 'reject') {
    if (action === 'reject' && !adminNotes.trim()) {
      setError('Please provide a reason for rejection.')
      return
    }
    setSubmitting(true)
    setError(null)

    const res = await fetch(`/api/checkins/${checkinId}/${action}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ adminNotes: adminNotes.trim() }),
    })

    if (res.ok) {
      router.push('/admin/queue')
    } else {
      const data = await res.json()
      setError(data.error ?? 'Action failed')
      setSubmitting(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-20">
        <p className="text-atlas-muted text-sm">Loading...</p>
      </div>
    )
  }

  if (!checkIn) {
    return (
      <div className="py-20 text-center">
        <p className="text-atlas-muted">Check-in not found.</p>
        <Link href="/admin/queue" className="mt-4 inline-block text-sm text-atlas-gold hover:underline">
          ← Back to queue
        </Link>
      </div>
    )
  }

  const passportExpiry = new Date(checkIn.passport.expires_at)
  const hoursLeft = (passportExpiry.getTime() - Date.now()) / (1000 * 60 * 60)
  const isReviewed = checkIn.status !== 'pending'

  return (
    <div className="max-w-3xl">
      <div className="flex items-center justify-between mb-8">
        <Link
          href="/admin/queue"
          className="text-xs text-atlas-muted hover:text-atlas-text uppercase tracking-widest transition-colors"
        >
          ← Queue
        </Link>
        <div className={`text-xs uppercase tracking-widest px-2 py-1 border ${
          checkIn.status === 'approved'
            ? 'border-atlas-gold text-atlas-gold'
            : checkIn.status === 'rejected'
            ? 'border-atlas-red text-atlas-red'
            : 'border-atlas-text-dim text-atlas-text-dim'
        }`}>
          {checkIn.status}
        </div>
      </div>

      <div className="grid md:grid-cols-2 gap-6">
        {/* Proof photo */}
        <div>
          <p className="text-xs text-atlas-muted uppercase tracking-widest mb-2">Proof</p>
          <div className="relative aspect-[4/3] border border-atlas-border overflow-hidden bg-atlas-dark">
            <Image
              src={checkIn.proof_url}
              alt="Check-in proof"
              fill
              className="object-cover"
              sizes="(max-width: 768px) 100vw, 50vw"
            />
          </div>
          {checkIn.notes && (
            <div className="mt-3 p-3 border border-atlas-border bg-atlas-card">
              <p className="text-xs text-atlas-muted uppercase tracking-widest mb-1">User Note</p>
              <p className="text-sm text-atlas-text-dim italic">&quot;{checkIn.notes}&quot;</p>
            </div>
          )}
        </div>

        {/* Details + actions */}
        <div className="space-y-4">
          {/* Node info */}
          <div className="border border-atlas-border bg-atlas-card p-4">
            <p className="text-xs text-atlas-muted uppercase tracking-widest mb-2">Stop</p>
            <div className="flex items-start gap-3">
              <div className="w-7 h-7 border border-atlas-border flex items-center justify-center text-xs font-mono text-atlas-muted flex-shrink-0">
                {checkIn.node.sequence}
              </div>
              <div>
                <p className="font-semibold text-atlas-text">{checkIn.node.name}</p>
                <p className="text-xs text-atlas-muted">{checkIn.node.corridor.name}</p>
                {checkIn.node.address && (
                  <p className="text-xs text-atlas-muted mt-0.5">{checkIn.node.address}</p>
                )}
              </div>
            </div>
          </div>

          {/* User info */}
          <div className="border border-atlas-border bg-atlas-card p-4">
            <p className="text-xs text-atlas-muted uppercase tracking-widest mb-2">User</p>
            <p className="text-sm text-atlas-text">{checkIn.profile.full_name ?? '—'}</p>
            <p className="text-xs text-atlas-text-dim">{checkIn.profile.email}</p>
            <div className="mt-2 pt-2 border-t border-atlas-border">
              <p className="text-xs text-atlas-muted">
                Passport expires:{' '}
                <span className={hoursLeft < 6 ? 'text-atlas-red-light' : 'text-atlas-text-dim'}>
                  {hoursLeft > 0
                    ? `${Math.floor(hoursLeft)}h remaining`
                    : 'Expired'}
                </span>
              </p>
            </div>
          </div>

          {/* Submitted time */}
          <div className="text-xs text-atlas-muted">
            Submitted: {new Date(checkIn.submitted_at).toLocaleString('en-US', {
              month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
            })}
          </div>

          {/* Admin notes */}
          {!isReviewed && (
            <div>
              <label className="block text-xs text-atlas-muted uppercase tracking-widest mb-2">
                Note to User (required if rejecting)
              </label>
              <textarea
                value={adminNotes}
                onChange={e => setAdminNotes(e.target.value)}
                rows={3}
                placeholder="Kaelo's message to the user..."
                className="w-full px-3 py-2 bg-atlas-dark border border-atlas-border text-sm text-atlas-text placeholder-atlas-muted resize-none focus:outline-none focus:border-atlas-gold transition-colors"
              />
            </div>
          )}

          {checkIn.admin_notes && isReviewed && (
            <div className="p-3 border border-atlas-border bg-atlas-dark">
              <p className="text-xs text-atlas-muted uppercase tracking-widest mb-1">Admin Note</p>
              <p className="text-sm text-atlas-text-dim">{checkIn.admin_notes}</p>
            </div>
          )}

          {error && (
            <p className="text-sm text-atlas-red-light">{error}</p>
          )}

          {/* Action buttons */}
          {!isReviewed && (
            <div className="flex gap-3">
              <button
                onClick={() => handleAction('approve')}
                disabled={submitting}
                className="flex-1 py-3 bg-atlas-green text-atlas-text font-semibold text-sm tracking-wider uppercase hover:bg-atlas-green-light transition-colors disabled:opacity-50"
              >
                {submitting ? '...' : '✓ Approve'}
              </button>
              <button
                onClick={() => handleAction('reject')}
                disabled={submitting}
                className="flex-1 py-3 bg-atlas-red text-atlas-text font-semibold text-sm tracking-wider uppercase hover:bg-atlas-red-light transition-colors disabled:opacity-50"
              >
                {submitting ? '...' : '✕ Reject'}
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
