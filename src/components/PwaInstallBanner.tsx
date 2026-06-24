'use client'

// PWA Install Banner — shown on Android when the browser fires beforeinstallprompt
// iOS: shows a manual "Add to Home Screen" instruction instead
// Does not render on desktop

import { useEffect, useState } from 'react'

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

export function PwaInstallBanner() {
  const [installPrompt, setInstallPrompt] =
    useState<BeforeInstallPromptEvent | null>(null)
  const [showIosTip, setShowIosTip] = useState(false)
  const [dismissed, setDismissed] = useState(false)

  useEffect(() => {
    // Already installed as standalone — don't show
    if (window.matchMedia('(display-mode: standalone)').matches) return

    // Check if already dismissed in this session
    if (sessionStorage.getItem('pwa-banner-dismissed')) return

    // Android — capture the install prompt
    const handler = (e: Event) => {
      e.preventDefault()
      setInstallPrompt(e as BeforeInstallPromptEvent)
    }
    window.addEventListener('beforeinstallprompt', handler)

    // iOS — detect Safari and show manual tip
    const isIos =
      /iphone|ipad|ipod/i.test(navigator.userAgent) &&
      !(window.navigator as { standalone?: boolean }).standalone
    if (isIos) setShowIosTip(true)

    return () => window.removeEventListener('beforeinstallprompt', handler)
  }, [])

  const handleInstall = async () => {
    if (!installPrompt) return
    await installPrompt.prompt()
    const { outcome } = await installPrompt.userChoice
    if (outcome === 'accepted') setInstallPrompt(null)
    setDismissed(true)
  }

  const handleDismiss = () => {
    sessionStorage.setItem('pwa-banner-dismissed', '1')
    setDismissed(true)
    setShowIosTip(false)
  }

  if (dismissed || (!installPrompt && !showIosTip)) return null

  return (
    <div className="fixed bottom-0 inset-x-0 z-50 p-4 pb-safe">
      <div className="bg-[#111] border border-white/10 rounded-2xl p-4 shadow-2xl">
        <div className="flex items-start gap-3">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/icons/icon-192.png"
            alt="Atlas Passport"
            className="w-12 h-12 rounded-xl flex-shrink-0"
          />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium text-white">Atlas Passport</p>
            {showIosTip ? (
              <p className="text-xs text-white/50 mt-0.5 leading-relaxed">
                Tap{' '}
                <span className="inline-block">
                  {/* Share icon */}
                  <svg className="w-3.5 h-3.5 inline mb-0.5" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M13 8V2H7v6H2l8 8 8-8h-5zM0 18h20v2H0v-2z" />
                  </svg>
                </span>{' '}
                then <strong className="text-white/70">Add to Home Screen</strong> to
                install.
              </p>
            ) : (
              <p className="text-xs text-white/50 mt-0.5">
                Install for instant access — no App Store needed.
              </p>
            )}
          </div>
          <button
            onClick={handleDismiss}
            className="text-white/30 hover:text-white/60 flex-shrink-0 p-1"
            aria-label="Dismiss"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        {installPrompt && (
          <button
            onClick={handleInstall}
            className="mt-3 w-full text-sm font-medium text-atlas-black bg-atlas-gold rounded-xl py-2.5 hover:bg-atlas-gold/90 transition-colors"
          >
            Install App
          </button>
        )}
      </div>
    </div>
  )
}
