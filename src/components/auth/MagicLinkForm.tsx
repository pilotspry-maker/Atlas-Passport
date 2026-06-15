'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'

interface Props {
  redirectTo?: string
}

export default function MagicLinkForm({ redirectTo }: Props) {
  const [email, setEmail] = useState('')
  const [loading, setLoading] = useState(false)
  const [sent, setSent] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email.trim()) return

    setLoading(true)
    setError(null)

    const supabase = createClient()
    const callbackUrl = `${window.location.origin}/auth/callback${redirectTo ? `?next=${redirectTo}` : ''}`

    const { error } = await supabase.auth.signInWithOtp({
      email: email.trim(),
      options: {
        emailRedirectTo: callbackUrl,
      },
    })

    setLoading(false)

    if (error) {
      setError(error.message)
    } else {
      setSent(true)
    }
  }

  if (sent) {
    return (
      <div className="text-center animate-fade-in">
        <div className="w-12 h-12 border border-atlas-gold flex items-center justify-center mx-auto mb-4">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" className="w-6 h-6 text-atlas-gold">
            <path strokeLinecap="round" strokeLinejoin="round" d="M21.75 6.75v10.5a2.25 2.25 0 01-2.25 2.25h-15a2.25 2.25 0 01-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25m19.5 0v.243a2.25 2.25 0 01-1.07 1.916l-7.5 4.615a2.25 2.25 0 01-2.36 0L3.32 8.91a2.25 2.25 0 01-1.07-1.916V6.75" />
          </svg>
        </div>
        <h2 className="text-lg font-semibold text-atlas-text mb-2">Check your inbox</h2>
        <p className="text-atlas-text-dim text-sm mb-6">
          Kaelo has sent a link to <span className="text-atlas-gold">{email}</span>.
          <br />
          Click it to activate your session.
        </p>
        <button
          onClick={() => { setSent(false); setEmail('') }}
          className="text-xs text-atlas-muted hover:text-atlas-text-dim transition-colors underline"
        >
          Use a different email
        </button>
      </div>
    )
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label htmlFor="email" className="block text-xs text-atlas-muted uppercase tracking-widest mb-2">
          Email Address
        </label>
        <input
          id="email"
          type="email"
          value={email}
          onChange={e => setEmail(e.target.value)}
          placeholder="you@example.com"
          required
          disabled={loading}
          className="w-full px-4 py-3 bg-atlas-card border border-atlas-border text-atlas-text placeholder-atlas-muted text-sm focus:outline-none focus:border-atlas-gold transition-colors disabled:opacity-50"
        />
      </div>

      {error && (
        <p className="text-sm text-atlas-red-light">{error}</p>
      )}

      <button
        type="submit"
        disabled={loading || !email.trim()}
        className="w-full py-3 bg-atlas-gold text-atlas-black font-semibold text-sm tracking-wider uppercase hover:bg-atlas-gold-light transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {loading ? 'Sending...' : 'Send Magic Link'}
      </button>

      <p className="text-xs text-atlas-muted text-center">
        No password needed. Check your spam folder if the link doesn&apos;t arrive within a minute.
      </p>
    </form>
  )
}
