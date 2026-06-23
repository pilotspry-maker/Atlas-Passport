import type { Metadata } from 'next'
import { Analytics } from '@vercel/analytics/next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Atlas Passport — Relevant Artist',
  description: 'A 72-hour real-world journey. Activate your passport. Complete the corridor. Claim your reward.',
  openGraph: {
    title: 'Atlas Passport',
    description: 'A 72-hour real-world travel activation game.',
    type: 'website',
  },
}

export default function RootLayout({
  children,
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="en" className="dark">
      <body className="bg-atlas-black text-atlas-text antialiased min-h-screen">
        {children}
        <Analytics />
      </body>
    </html>
  )
}
