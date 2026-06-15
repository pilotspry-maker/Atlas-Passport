import Link from 'next/link'

export default function ApplySuccessPage() {
  return (
    <main className="min-h-screen bg-ink flex flex-col">
      <nav className="flex items-center px-8 py-6 border-b border-border">
        <Link href="/" className="font-serif text-xl tracking-tight text-parchment">
          Atlas Passport
        </Link>
      </nav>

      <div className="flex-1 flex items-center justify-center px-8">
        <div className="max-w-md text-center">
          <div className="stamp mb-8 mx-auto">Received</div>
          <h1 className="font-serif text-4xl text-parchment mb-4">
            Application submitted.
          </h1>
          <p className="text-muted leading-relaxed mb-10">
            Thank you for applying. We review applications on a rolling basis and will
            be in touch within 5–7 business days.
          </p>
          <Link
            href="/"
            className="text-gold text-sm tracking-widest uppercase hover:text-gold-light transition-colors"
          >
            ← Back to home
          </Link>
        </div>
      </div>
    </main>
  )
}
