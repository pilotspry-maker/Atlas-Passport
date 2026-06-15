'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import AdminNav from '@/components/admin/AdminNav'

export default function NewCorridorPage() {
  const router = useRouter()
  const [form, setForm] = useState({ name: '', description: '', city: '', country: 'US', is_active: true })
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  function set(field: string, value: string | boolean) {
    setForm(prev => ({ ...prev, [field]: value }))
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setSaving(true)
    setError(null)

    const res = await fetch('/api/admin/corridors', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(form),
    })

    const data = await res.json()
    if (!res.ok) {
      setError(data.error ?? 'Failed to create corridor')
      setSaving(false)
      return
    }

    router.push(`/admin/corridors/${data.corridor.id}/edit`)
  }

  return (
    <div className="max-w-lg">
      <AdminNav active="corridors" />

      <Link
        href="/admin/corridors"
        className="inline-block text-xs text-atlas-muted hover:text-atlas-text uppercase tracking-widest mb-8 transition-colors"
      >
        ← Corridors
      </Link>

      <h1 className="text-xl font-bold text-atlas-text mb-8">New Corridor</h1>

      <form onSubmit={handleSubmit} className="space-y-5">
        <Field label="Name *">
          <input
            type="text"
            value={form.name}
            onChange={e => set('name', e.target.value)}
            placeholder="The Midnight Corridor"
            required
            className={INPUT}
          />
        </Field>

        <Field label="Description">
          <textarea
            value={form.description}
            onChange={e => set('description', e.target.value)}
            rows={3}
            placeholder="What does this corridor journey feel like?"
            className={`${INPUT} resize-none`}
          />
        </Field>

        <div className="grid grid-cols-2 gap-4">
          <Field label="City *">
            <input
              type="text"
              value={form.city}
              onChange={e => set('city', e.target.value)}
              placeholder="New York"
              required
              className={INPUT}
            />
          </Field>

          <Field label="Country">
            <input
              type="text"
              value={form.country}
              onChange={e => set('country', e.target.value)}
              placeholder="US"
              className={INPUT}
            />
          </Field>
        </div>

        <label className="flex items-center gap-3 cursor-pointer">
          <div
            onClick={() => set('is_active', !form.is_active)}
            className={`w-9 h-5 rounded-full transition-colors relative ${form.is_active ? 'bg-atlas-green' : 'bg-atlas-border'}`}
          >
            <div className={`absolute top-0.5 w-4 h-4 rounded-full bg-white transition-transform ${form.is_active ? 'translate-x-4' : 'translate-x-0.5'}`} />
          </div>
          <span className="text-sm text-atlas-text-dim">Active (visible to users)</span>
        </label>

        {error && <p className="text-sm text-atlas-red-light">{error}</p>}

        <button
          type="submit"
          disabled={saving}
          className="w-full py-3 bg-atlas-gold text-atlas-black font-semibold text-sm tracking-wider uppercase hover:bg-atlas-gold-light transition-colors disabled:opacity-50"
        >
          {saving ? 'Creating...' : 'Create Corridor — Add Stops Next →'}
        </button>
      </form>
    </div>
  )
}

const INPUT = 'w-full px-4 py-2.5 bg-atlas-dark border border-atlas-border text-atlas-text placeholder-atlas-muted text-sm focus:outline-none focus:border-atlas-gold transition-colors'

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="block text-xs text-atlas-muted uppercase tracking-widest mb-2">{label}</label>
      {children}
    </div>
  )
}
