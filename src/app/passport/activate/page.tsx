'use client'

import { Suspense, useState, useEffect } from 'react'
import { useSearchParams, useRouter } from 'next/navigation'
import Link from 'next/link'

function ActivateContent() {
  const searchParams = useSearchParams()
  const router = useRouter()
  const corridorId = searchParams.get('corridor')

  const [corridor, setCorridor] = useState<{ name: string; city: string; country: string } | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [ready, setReady] = useState(false)

  useEffect(() => {
    if (!corridorId) {
      router.replace('/corridors')
      return
    }

    fetch(`/api/corridors?id=${corridorId}`)
      .then(r => r.json())
      .then(data => {
        if (data.corridor) setCorridor(data.corridor)
        else router.replace('/corridors')
      })
      .catch(() => router.replace('/corridors'))
  }, [corridorId, router])

  async function handleActivate() {
    if (!corridorId || !ready) return
    setLoading(true)
    setError(null)

    const res = await fetch('/api/passport/activate', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ corridorId }),
    })

    const data = await res.json()

    if (!res.ok) {
      setError(data.error ?? 'Failed to activate passport')
      setLoading(false)
      return
    }

    router.push('/passport')
  }

  if (!corridor) {
    return (
      <main className="min-h-screen flex items-center justify-center">
        <div className="text-atlas-muted text-sm">Loading corridor...</div>
      </main>
    )
  }

  return (
    <main className="min-h-screen bg-atlas-black px-4 py-8 max-w-lg mx-auto flex flex-col justify-center">
      <div className="animate-fade-in">
        <Link
          href={`/corridors/${corridorId}`}
          className="inline-block text-xs text-atlas-muted hover:text-atlas-text uppercase tracking-widest mb-8 transition-colors"
        >
          ← Back
        </Link>

        <div className="border border-atlas-border bg-atlas-card p-8 mb-6">
          <p className="text-xs text-atlas-gold uppercase tracking-[0.25em] mb-2">Confirm Activation</p>
          <h1 className="text-2xl font-bold text-atlas-text mb-1">{corridor.name}</h1>
          <p className="text-sm text-atlas-text-dim mb-6">{corridor.city}, {corridor.country}</p>

          <div className="space-y-4 border-t border-atlas-border pt-6">
            <div className="flex items-start gap-3">
              <div className="text-atlas-gold mt-0.5 text-sm">①</div>
              <p className="text-sm text-atlas-text-dim">
                Your 72-hour clock starts <strong className="text-atlas-text">immediately</strong> when you tap &quot;Activate.&quot;
              </p>
            </div>
            <div className="flex items-start gap-3">
              <div className="text-atlas-gold mt-0.5 text-sm">②</div>
              <p className="text-sm text-atlas-text-dim">
                You must visit every stop and upload proof within the window.
              </p>
            </div>
            <div className="flex items-start gap-3">
              <div className="text-atlas-gold mt-0.5 text-sm">③</div>
              <p className="text-sm text-atlas-text-dim">
                There are no extensions and no second chances on this corridor.
              </p>
            </div>
          </div>
        </div>

        {/* Acknowledgement checkbox */}
        <label className="flex items-start gap-3 cursor-pointer mb-6 group">
          <div className={`mt-0.5 w-5 h-5 flex-shrink-0 border flex items-center justify-center transition-colors ${
            ready ? 'border-atlas-gold bg-atlas-gold/10' : 'border-atlas-border group-hover:border-atlas-muted'
          }`}>
            {ready && (
              <svg viewBox="0 0 12 12" fill="none" className="w-3 h-3">
                <path d="M2 6l3 3 5-5" stroke="#c8a96e" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            )}
          </div>
          <input
            type="checkbox"
            checked={ready}
            onChange={e => setReady(e.target.checked)}
            className="sr-only"
          />
          <span className="text-sm text-atlas-text-dim">
            I understand the rules and I&apos;m ready to begin. The clock starts now.
          </span>
        </label>

        {error && (
          <p className="mb-4 text-sm text-atlas-red-light">{error}</p>
        )}

        <button
          onClick={handleActivate}
          disabled={!ready || loading}
          className="w-full py-4 bg-atlas-gold text-atlas-black font-bold text-sm tracking-widest uppercase hover:bg-atlas-gold-light transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
        >
          {loading ? 'Activating...' : 'Activate Passport — Start Clock'}
        </button>
      </div>
    </main>
  )
}

export default function ActivatePassportPage() {
  return (
    <Suspense fallback={
      <main className="min-h-screen flex items-center justify-center">
        <div className="text-atlas-muted text-sm">Loading...</div>
      </main>
    }>
      <ActivateContent />
    </Suspense>
  )
}
