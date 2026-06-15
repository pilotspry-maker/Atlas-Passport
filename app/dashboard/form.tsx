'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { slugify } from '@/lib/utils'
import type { Artist } from '@/lib/types'

interface Props {
  artist: Artist | null
  userId: string
}

export default function DashboardForm({ artist, userId }: Props) {
  const [loading, setLoading] = useState(false)
  const [saved, setSaved] = useState(false)
  const [error, setError] = useState('')

  async function handleSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault()
    setLoading(true)
    setSaved(false)
    setError('')

    const form = new FormData(e.currentTarget)
    const full_name = form.get('full_name') as string
    const payload = {
      full_name,
      bio: form.get('bio') as string,
      location: form.get('location') as string,
      website: (form.get('website') as string) || null,
      instagram: (form.get('instagram') as string) || null,
      portfolio_url: (form.get('portfolio_url') as string) || null,
      slug: artist?.slug ?? slugify(full_name),
      user_id: userId,
      status: 'approved' as const,
    }

    const supabase = createClient()

    const { error } = artist
      ? await supabase.from('artists').update(payload).eq('id', artist.id)
      : await supabase.from('artists').insert(payload)

    if (error) {
      setError(error.message)
    } else {
      setSaved(true)
    }
    setLoading(false)
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-8">
      <div className="grid md:grid-cols-2 gap-6">
        <Field label="Full name" name="full_name" defaultValue={artist?.full_name} required />
        <Field label="City / Country" name="location" defaultValue={artist?.location ?? ''} />
      </div>

      <div>
        <label className="block text-xs tracking-widest uppercase text-muted mb-2">
          Bio / Statement <span className="text-gold">*</span>
        </label>
        <textarea
          name="bio"
          required
          rows={5}
          defaultValue={artist?.bio ?? ''}
          className="w-full bg-transparent border border-border text-parchment px-4 py-3 text-sm focus:outline-none focus:border-gold transition-colors resize-none"
        />
      </div>

      <div className="grid md:grid-cols-3 gap-6">
        <Field label="Website" name="website" type="url" defaultValue={artist?.website ?? ''} placeholder="https://" />
        <Field label="Instagram" name="instagram" defaultValue={artist?.instagram ?? ''} placeholder="@handle" />
        <Field label="Portfolio URL" name="portfolio_url" type="url" defaultValue={artist?.portfolio_url ?? ''} placeholder="https://" />
      </div>

      {error && <p className="text-red-400 text-sm">{error}</p>}
      {saved && <p className="text-green-400 text-sm">Saved.</p>}

      <button
        type="submit"
        disabled={loading}
        className="bg-gold text-ink font-semibold text-sm tracking-widest uppercase px-8 py-4 hover:bg-gold-light transition-colors disabled:opacity-50"
      >
        {loading ? 'Saving…' : 'Save passport'}
      </button>
    </form>
  )
}

function Field({
  label, name, type = 'text', required, defaultValue, placeholder,
}: {
  label: string
  name: string
  type?: string
  required?: boolean
  defaultValue?: string
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
        defaultValue={defaultValue}
        placeholder={placeholder}
        className="w-full bg-transparent border border-border text-parchment px-4 py-3 text-sm focus:outline-none focus:border-gold transition-colors placeholder:text-border"
      />
    </div>
  )
}
