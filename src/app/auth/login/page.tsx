import MagicLinkForm from '@/components/auth/MagicLinkForm'
import Link from 'next/link'

interface Props {
  searchParams: Promise<{ redirectTo?: string; error?: string }>
}

export default async function LoginPage({ searchParams }: Props) {
  const params = await searchParams

  return (
    <main className="min-h-screen flex flex-col items-center justify-center px-4">
      <div className="w-full max-w-sm animate-fade-in">
        <div className="mb-8 text-center">
          <Link
            href="/"
            className="text-atlas-gold text-xs tracking-[0.3em] uppercase hover:text-atlas-gold-light transition-colors"
          >
            ← Atlas Passport
          </Link>
          <h1 className="text-2xl font-bold text-atlas-text mt-4 mb-2">
            Enter your email
          </h1>
          <p className="text-atlas-text-dim text-sm">
            Kaelo will send you a magic link to begin.
          </p>
        </div>

        {params.error && (
          <div className="mb-6 p-3 border border-atlas-red text-sm text-atlas-text-dim">
            {params.error === 'auth_error'
              ? 'Something went wrong with authentication. Try again.'
              : params.error}
          </div>
        )}

        <MagicLinkForm redirectTo={params.redirectTo} />
      </div>
    </main>
  )
}
