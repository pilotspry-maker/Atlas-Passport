import { redirect } from 'next/navigation'
import Link from 'next/link'
import { createClient } from '@/lib/supabase/server'

export default async function PassportCompletePage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/auth/login')

  const { data: passport } = await supabase
    .from('passports')
    .select('*, corridor:corridors(*)')
    .eq('user_id', user.id)
    .eq('status', 'complete')
    .order('completed_at', { ascending: false })
    .limit(1)
    .maybeSingle()

  if (!passport) redirect('/passport')

  const corridor = passport.corridor as { id: string; name: string; city: string; country: string }

  const { data: reward } = await supabase
    .from('rewards')
    .select('*')
    .eq('corridor_id', corridor.id)
    .maybeSingle()

  return (
    <main className="min-h-screen bg-atlas-black px-4 py-8 max-w-lg mx-auto flex flex-col justify-center">
      <div className="animate-fade-in">
        {/* Trophy */}
        <div className="text-center mb-8">
          <div className="text-6xl mb-4">✦</div>
          <p className="text-xs text-atlas-gold uppercase tracking-[0.3em] mb-2">
            Journey Complete
          </p>
          <h1 className="text-3xl font-bold text-atlas-text mb-2">
            {corridor.name}
          </h1>
          <p className="text-atlas-text-dim text-sm">{corridor.city}, {corridor.country}</p>
        </div>

        {/* Completion stamp */}
        <div className="border border-atlas-gold/40 bg-atlas-gold/5 p-6 mb-6 stamp-border text-center">
          <div className="text-xs text-atlas-gold uppercase tracking-widest mb-1">Atlas Passport</div>
          <div className="text-sm text-atlas-text-dim">All stops verified by Kaelo</div>
          {passport.completed_at && (
            <div className="mt-3 text-xs text-atlas-muted font-mono">
              Completed{' '}
              {new Date(passport.completed_at).toLocaleDateString('en-US', {
                month: 'long',
                day: 'numeric',
                year: 'numeric',
              })}
            </div>
          )}
        </div>

        {/* Reward */}
        {reward ? (
          <div className="border border-atlas-gold bg-atlas-card p-6 mb-6">
            <p className="text-xs text-atlas-gold uppercase tracking-widest mb-3">Your Reward</p>
            <h2 className="text-lg font-semibold text-atlas-text mb-2">{reward.title}</h2>
            {reward.description && (
              <p className="text-sm text-atlas-text-dim mb-4">{reward.description}</p>
            )}

            {reward.redemption_code && (
              <div className="bg-atlas-dark p-4 border border-atlas-border">
                <p className="text-xs text-atlas-muted uppercase tracking-widest mb-1">Redemption Code</p>
                <p className="font-mono text-lg text-atlas-gold tracking-widest select-all">
                  {reward.redemption_code}
                </p>
              </div>
            )}

            {reward.redemption_url && (
              <a
                href={reward.redemption_url}
                target="_blank"
                rel="noopener noreferrer"
                className="mt-4 block w-full py-3 bg-atlas-gold text-atlas-black font-semibold text-sm tracking-wider uppercase text-center hover:bg-atlas-gold-light transition-colors"
              >
                Claim Reward →
              </a>
            )}
          </div>
        ) : (
          <div className="border border-atlas-border p-6 mb-6 text-center text-atlas-text-dim text-sm">
            Your reward is being prepared. You&apos;ll receive an email from Kaelo with the details.
          </div>
        )}

        {/* Actions */}
        <div className="flex flex-col gap-3">
          <Link
            href="/corridors"
            className="block w-full py-3 border border-atlas-border text-atlas-text-dim text-sm text-center hover:border-atlas-gold hover:text-atlas-gold transition-colors uppercase tracking-wider"
          >
            Explore More Corridors
          </Link>
          <Link
            href="/passport"
            className="block w-full py-3 text-atlas-muted text-sm text-center hover:text-atlas-text transition-colors"
          >
            View Passport
          </Link>
        </div>
      </div>
    </main>
  )
}
