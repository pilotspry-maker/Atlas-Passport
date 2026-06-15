import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Admin — Atlas Passport',
}

export default function AdminLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-atlas-black">
      <div className="border-b border-atlas-border bg-atlas-dark px-6 py-4 flex items-center justify-between">
        <div>
          <span className="text-xs text-atlas-gold uppercase tracking-[0.25em]">Atlas Passport</span>
          <span className="text-xs text-atlas-muted ml-3">Admin</span>
        </div>
      </div>
      <div className="max-w-5xl mx-auto px-4 py-8">
        {children}
      </div>
    </div>
  )
}
