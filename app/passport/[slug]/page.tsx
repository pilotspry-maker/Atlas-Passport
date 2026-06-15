import { notFound } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { formatPassportNumber } from '@/lib/utils'
import type { Metadata } from 'next'
import Link from 'next/link'

interface Props {
  params: Promise<{ slug: string }>
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params
  const supabase = await createClient()
  const { data } = await supabase
    .from('artists')
    .select('full_name, bio')
    .eq('slug', slug)
    .eq('status', 'approved')
    .single()

  if (!data) return { title: 'Passport not found — Atlas Passport' }

  return {
    title: `${data.full_name} — Atlas Passport`,
    description: data.bio ?? undefined,
  }
}

export default async function PassportPage({ params }: Props) {
  const { slug } = await params
  const supabase = await createClient()

  const { data: artist } = await supabase
    .from('artists')
    .select('*')
    .eq('slug', slug)
    .eq('status', 'approved')
    .single()

  if (!artist) notFound()

  return (
    <main className="min-h-screen bg-ink">
      <nav className="flex items-center justify-between px-8 py-6 border-b border-border">
        <Link href="/" className="font-serif text-xl tracking-tight text-parchment">
          Atlas Passport
        </Link>
        <span className="text-muted text-xs tracking-widest uppercase">
          {formatPassportNumber(artist.id)}
        </span>
      </nav>

      <div className="max-w-3xl mx-auto px-8 py-16">
        {/* Passport header */}
        <div className="flex items-start justify-between mb-12">
          <div className="flex-1">
            <div className="stamp mb-6">Verified Artist</div>
            <h1 className="font-serif text-5xl text-parchment mb-2">{artist.full_name}</h1>
            {artist.discipline && (
              <p className="text-gold text-sm tracking-widest uppercase">{artist.discipline}</p>
            )}
            {artist.location && (
              <p className="text-muted text-sm mt-1">{artist.location}</p>
            )}
          </div>
          {artist.avatar_url && (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={artist.avatar_url}
              alt={artist.full_name}
              className="w-24 h-24 object-cover border border-border ml-8"
            />
          )}
        </div>

        {/* Divider */}
        <div className="border-t border-border mb-12" />

        {/* Bio */}
        {artist.bio && (
          <section className="mb-12">
            <h2 className="text-xs tracking-widest uppercase text-muted mb-4">Statement</h2>
            <p className="font-serif text-parchment text-lg leading-relaxed">{artist.bio}</p>
          </section>
        )}

        {/* Links */}
        {(artist.website || artist.instagram || artist.portfolio_url) && (
          <section className="mb-12">
            <h2 className="text-xs tracking-widest uppercase text-muted mb-4">Links</h2>
            <div className="space-y-2">
              {artist.portfolio_url && (
                <a href={artist.portfolio_url} target="_blank" rel="noopener noreferrer"
                  className="block text-gold hover:text-gold-light transition-colors text-sm">
                  Portfolio →
                </a>
              )}
              {artist.website && (
                <a href={artist.website} target="_blank" rel="noopener noreferrer"
                  className="block text-gold hover:text-gold-light transition-colors text-sm">
                  {artist.website.replace(/^https?:\/\//, '')} →
                </a>
              )}
              {artist.instagram && (
                <a
                  href={`https://instagram.com/${artist.instagram.replace('@', '')}`}
                  target="_blank" rel="noopener noreferrer"
                  className="block text-gold hover:text-gold-light transition-colors text-sm">
                  {artist.instagram.startsWith('@') ? artist.instagram : `@${artist.instagram}`} →
                </a>
              )}
            </div>
          </section>
        )}

        {/* Passport footer */}
        <div className="border-t border-border pt-8 flex items-center justify-between">
          <span className="text-muted text-xs">
            Issued {new Date(artist.created_at).toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })}
          </span>
          <span className="text-muted text-xs tracking-widest">{formatPassportNumber(artist.id)}</span>
        </div>
      </div>
    </main>
  )
}
