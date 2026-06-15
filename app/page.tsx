import Link from 'next/link'

export default function LandingPage() {
  return (
    <main className="min-h-screen bg-ink">
      {/* Nav */}
      <nav className="flex items-center justify-between px-8 py-6 border-b border-border">
        <span className="font-serif text-xl tracking-tight text-parchment">Atlas Passport</span>
        <Link
          href="/login"
          className="text-sm text-muted hover:text-parchment transition-colors tracking-wide"
        >
          Sign in
        </Link>
      </nav>

      {/* Hero */}
      <section className="relative px-8 pt-24 pb-32 max-w-4xl mx-auto">
        <div className="stamp mb-10">Relevant Artist</div>
        <h1 className="font-serif text-5xl md:text-7xl leading-[1.05] text-parchment mb-8">
          Your passport to the global artist community.
        </h1>
        <p className="text-muted text-lg md:text-xl max-w-xl leading-relaxed mb-12">
          Atlas Passport is an invitation-based credential for working artists — a single
          page that represents who you are, where you've been, and what you make.
        </p>
        <Link
          href="/apply"
          className="inline-block bg-gold text-ink font-sans font-semibold text-sm tracking-widest uppercase px-8 py-4 hover:bg-gold-light transition-colors"
        >
          Apply for your passport
        </Link>
      </section>

      {/* How it works */}
      <section className="border-t border-border px-8 py-24 max-w-4xl mx-auto">
        <h2 className="font-serif text-2xl text-parchment mb-16">How it works</h2>
        <div className="grid md:grid-cols-3 gap-12">
          {[
            {
              step: '01',
              title: 'Apply',
              body: 'Submit your application with a portfolio link and a brief statement about your practice.',
            },
            {
              step: '02',
              title: 'Get approved',
              body: 'Our team reviews applications on a rolling basis. Accepted artists receive a confirmation within 5–7 days.',
            },
            {
              step: '03',
              title: 'Share your passport',
              body: 'Your Atlas Passport is a permanent public link showcasing your identity as a working artist.',
            },
          ].map(({ step, title, body }) => (
            <div key={step}>
              <span className="text-gold font-sans text-xs tracking-widest">{step}</span>
              <h3 className="font-serif text-xl text-parchment mt-3 mb-3">{title}</h3>
              <p className="text-muted text-sm leading-relaxed">{body}</p>
            </div>
          ))}
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-border px-8 py-8 flex items-center justify-between">
        <span className="text-muted text-xs tracking-wide">© {new Date().getFullYear()} Atlas Passport</span>
        <Link href="/apply" className="text-gold text-xs tracking-widest uppercase hover:text-gold-light transition-colors">
          Apply →
        </Link>
      </footer>
    </main>
  )
}
