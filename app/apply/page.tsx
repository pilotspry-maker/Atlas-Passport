'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'

const DISCIPLINES = [
  'Visual Art', 'Photography', 'Film & Video', 'Music', 'Performance',
  'Dance', 'Writing & Poetry', 'Fashion', 'Architecture', 'Other',
]

export default function ApplyPage() {
  const router = useRouter()
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setLoading(true)
    setError('')

    const form = new FormData(e.currentTarget)
    const body = Object.fromEntries(form.entries())

    const res = await fetch('/api/apply', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })

    if (res.ok) {
      router.push('/apply/success')
    } else {
      const data = await res.json()
      setError(data.error ?? 'Something went wrong. Please try again.')
      setLoading(false)
    }
  }

  return (
    <main className="min-h-screen bg-ink">
      <nav className="flex items-center px-8 py-6 border-b border-border">
        <Link href="/" className="font-serif text-xl tracking-tight text-parchment">
          Atlas Passport
        </Link>
      </nav>

      <div className="max-w-2xl mx-auto px-8 py-16">
        <div className="stamp mb-8">Application</div>
        <h1 className="font-serif text-4xl text-parchment mb-3">Apply for your passport</h1>
        <p className="text-muted mb-12 leading-relaxed">
          Tell us about your practice. We review applications on a rolling basis.
        </p>

        <form onSubmit={handleSubmit} className="space-y-8">
          <div className="grid md:grid-cols-2 gap-6">
            <Field label="Full name" name="full_name" required />
            <Field label="Email address" name="email" type="email" required />
          </div>

          <div className="grid md:grid-cols-2 gap-6">
            <Field label="City / Country" name="location" placeholder="e.g. Lagos, Nigeria" required />
            <div>
              <label className="block text-xs tracking-widest uppercase text-muted mb-2">
                Primary discipline <span className="text-gold">*</span>
              </label>
              <select
                name="discipline"
                required
                className="w-full bg-transparent border border-border text-parchment px-4 py-3 text-sm focus:outline-none focus:border-gold transition-colors appearance-none"
              >
                <option value="" disabled selected className="bg-ink">Select discipline</option>
                {DISCIPLINES.map(d => (
                  <option key={d} value={d} className="bg-ink">{d}</option>
                ))}
              </select>
            </div>
          </div>

          <TextArea label="Bio" name="bio" required rows={4}
            placeholder="A brief description of your practice (2–4 sentences)." />

          <TextArea label="Why Atlas Passport?" name="why_atlas" required rows={4}
            placeholder="Why do you want to be part of this community?" />

          <div className="grid md:grid-cols-3 gap-6">
            <Field label="Website" name="website" type="url" placeholder="https://" />
            <Field label="Instagram" name="instagram" placeholder="@handle" />
            <Field label="Portfolio URL" name="portfolio_url" type="url" placeholder="https://" />
          </div>

          {error && <p className="text-red-400 text-sm">{error}</p>}

          <button
            type="submit"
            disabled={loading}
            className="bg-gold text-ink font-semibold text-sm tracking-widest uppercase px-8 py-4 hover:bg-gold-light transition-colors disabled:opacity-50"
          >
            {loading ? 'Submitting…' : 'Submit application'}
          </button>
        </form>
      </div>
    </main>
  )
}

function Field({
  label, name, type = 'text', required, placeholder,
}: {
  label: string
  name: string
  type?: string
  required?: boolean
  placeholder?: string
}) {
  return (
    <div>
      <label className="block text-xs tracking-widest uppercase text-muted mb-2">
        {label} {required && <span className="text-gold">*</span>}
      </label>
      <input
        type={type}
        name={name}
        required={required}
        placeholder={placeholder}
        className="w-full bg-transparent border border-border text-parchment px-4 py-3 text-sm focus:outline-none focus:border-gold transition-colors placeholder:text-border"
      />
    </div>
  )
}

function TextArea({
  label, name, required, rows, placeholder,
}: {
  label: string
  name: string
  required?: boolean
  rows?: number
  placeholder?: string
}) {
  return (
    <div>
      <label className="block text-xs tracking-widest uppercase text-muted mb-2">
        {label} {required && <span className="text-gold">*</span>}
      </label>
      <textarea
        name={name}
        required={required}
        rows={rows ?? 3}
        placeholder={placeholder}
        className="w-full bg-transparent border border-border text-parchment px-4 py-3 text-sm focus:outline-none focus:border-gold transition-colors resize-none placeholder:text-border"
      />
    </div>
  )
}
