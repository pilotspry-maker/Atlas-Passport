import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import Link from 'next/link'
import DashboardForm from './form'

export default async function DashboardPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: artist } = await supabase
    .from('artists')
    .select('*')
    .eq('user_id', user.id)
    .single()

  return (
    <main className="min-h-screen bg-ink">
      <nav className="flex items-center justify-between px-8 py-6 border-b border-border">
        <Link href="/" className="font-serif text-xl tracking-tight text-parchment">
          Atlas Passport
        </Link>
        {artist && (
          <Link
            href={`/passport/${artist.slug}`}
            className="text-gold text-xs tracking-widest uppercase hover:text-gold-light transition-colors"
          >
            View my passport →
          </Link>
        )}
      </nav>

      <div className="max-w-2xl mx-auto px-8 py-16">
        <h1 className="font-serif text-4xl text-parchment mb-2">
          {artist ? 'Edit your passport' : 'Your passport is being set up'}
        </h1>
        <p className="text-muted mb-12">
          {artist
            ? 'Changes are published immediately to your public passport.'
            : 'Your application was approved. Complete your profile to publish your passport.'}
        </p>

        <DashboardForm artist={artist} userId={user.id} />
      </div>
    </main>
  )
}
