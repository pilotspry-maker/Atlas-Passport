'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import Link from 'next/link'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [sent, setSent] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setLoading(true)
    setError('')

    const supabase = createClient()
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
      },
    })

    if (error) {
      setError(error.message)
    } else {
      setSent(true)
    }
    setLoading(false)
  }

  return (
    <main className="min-h-screen bg-ink flex flex-col">
      <nav className="flex items-center px-8 py-6 border-b border-border">
        <Link href="/" className="font-serif text-xl tracking-tight text-parchment">
          Atlas Passport
        </Link>
      </nav>

      <div className="flex-1 flex items-center justify-center px-8">
        <div className="w-full max-w-sm">
          {sent ? (
            <div>
              <h1 className="font-serif text-3xl text-parchment mb-4">Check your email</h1>
              <p className="text-muted leading-relaxed">
                We sent a magic link to <strong className="text-parchment">{email}</strong>.
                Click it to sign in.
              </p>
            </div>
          ) : (
            <form onSubmit={handleSubmit}>
              <h1 className="font-serif text-3xl text-parchment mb-2">Sign in</h1>
              <p className="text-muted text-sm mb-8">We'll email you a magic link.</p>

              <label className="block text-xs tracking-widest uppercase text-muted mb-2">
                Email address
              </label>
              <input
                type="email"
                value={email}
                onChange={e => setEmail(e.target.value)}
                required
                className="w-full bg-transparent border border-border text-parchment px-4 py-3 text-sm focus:outline-none focus:border-gold transition-colors mb-6"
                placeholder="you@example.com"
              />

              {error && <p className="text-red-400 text-sm mb-4">{error}</p>}

              <button
                type="submit"
                disabled={loading}
                className="w-full bg-gold text-ink font-semibold text-sm tracking-widest uppercase py-3 hover:bg-gold-light transition-colors disabled:opacity-50"
              >
                {loading ? 'Sending…' : 'Send magic link'}
              </button>
            </form>
          )}
        </div>
      </div>
    </main>
  )
}
