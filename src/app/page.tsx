import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import Link from 'next/link'

export default async function HomePage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (user) {
    // Check for active passport
    const { data: passportData } = await supabase
      .from('passports')
      .select('id, status')
      .eq('user_id', user.id)
      .eq('status', 'active')
      .maybeSingle()
    const passport = passportData as { id: string } | null

    if (passport) redirect('/passport')
    redirect('/corridors')
  }

  return (
    <main className="min-h-screen flex flex-col items-center justify-center px-4 relative overflow-hidden">
      {/* Background grid */}
      <div
        className="absolute inset-0 opacity-[0.03]"
        style={{
          backgroundImage: `linear-gradient(#c8a96e 1px, transparent 1px), linear-gradient(90deg, #c8a96e 1px, transparent 1px)`,
          backgroundSize: '60px 60px',
        }}
      />

      <div className="relative z-10 text-center max-w-lg mx-auto animate-fade-in">
        <p className="text-atlas-gold text-xs tracking-[0.3em] uppercase mb-6">
          Relevant Artist
        </p>

        <h1 className="text-5xl sm:text-7xl font-bold tracking-tight text-atlas-text mb-4">
          ATLAS
          <br />
          <span className="text-atlas-gold">PASSPORT</span>
        </h1>

        <p className="text-atlas-text-dim text-base sm:text-lg leading-relaxed mb-12 max-w-sm mx-auto">
          A 72-hour real-world journey. Choose a corridor. Complete the stops. Claim your reward.
        </p>

        <div className="flex flex-col sm:flex-row gap-3 justify-center">
          <Link
            href="/auth/login"
            className="px-8 py-3 bg-atlas-gold text-atlas-black font-semibold text-sm tracking-wider uppercase hover:bg-atlas-gold-light transition-colors"
          >
            Activate Passport
          </Link>
          <Link
            href="/auth/login"
            className="px-8 py-3 border border-atlas-border text-atlas-text-dim text-sm tracking-wider uppercase hover:border-atlas-gold hover:text-atlas-gold transition-colors"
          >
            Sign In
          </Link>
        </div>

        <div className="mt-16 flex items-center gap-8 justify-center">
          {[
            { number: '72', label: 'Hours' },
            { number: '3+', label: 'Stops' },
            { number: '1', label: 'Reward' },
          ].map(({ number, label }) => (
            <div key={label} className="text-center">
              <div className="text-2xl font-bold text-atlas-gold">{number}</div>
              <div className="text-xs text-atlas-muted uppercase tracking-widest mt-1">{label}</div>
            </div>
          ))}
        </div>
      </div>

      {/* Corner decorations */}
      <div className="absolute top-6 left-6 w-8 h-8 border-t border-l border-atlas-border opacity-50" />
      <div className="absolute top-6 right-6 w-8 h-8 border-t border-r border-atlas-border opacity-50" />
      <div className="absolute bottom-6 left-6 w-8 h-8 border-b border-l border-atlas-border opacity-50" />
      <div className="absolute bottom-6 right-6 w-8 h-8 border-b border-r border-atlas-border opacity-50" />
    </main>
  )
}
