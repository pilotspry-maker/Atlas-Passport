'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'

interface Props {
  applicationId: string
  email: string
  name: string
}

export default function AdminActions({ applicationId, email, name }: Props) {
  const router = useRouter()
  const [loading, setLoading] = useState<'approve' | 'reject' | null>(null)

  async function act(action: 'approve' | 'reject') {
    setLoading(action)
    const res = await fetch('/api/admin/review', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ applicationId, action, email, name }),
    })
    if (res.ok) {
      router.refresh()
    }
    setLoading(null)
  }

  return (
    <div className="flex gap-2 shrink-0">
      <button
        onClick={() => act('approve')}
        disabled={!!loading}
        className="text-xs tracking-widest uppercase px-4 py-2 border border-gold text-gold hover:bg-gold hover:text-ink transition-colors disabled:opacity-40"
      >
        {loading === 'approve' ? '…' : 'Approve'}
      </button>
      <button
        onClick={() => act('reject')}
        disabled={!!loading}
        className="text-xs tracking-widest uppercase px-4 py-2 border border-border text-muted hover:border-muted hover:text-parchment transition-colors disabled:opacity-40"
      >
        {loading === 'reject' ? '…' : 'Reject'}
      </button>
    </div>
  )
}
