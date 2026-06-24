'use client'

// Service Worker registration — client component, placed in root layout
// Registers /sw.js silently on mount; logs errors only in development

import { useEffect } from 'react'

export function SwRegister() {
  useEffect(() => {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker
        .register('/sw.js', { scope: '/' })
        .then((reg) => {
          if (process.env.NODE_ENV === 'development') {
            console.log('[SW] Registered:', reg.scope)
          }
        })
        .catch((err) => {
          if (process.env.NODE_ENV === 'development') {
            console.error('[SW] Registration failed:', err)
          }
        })
    }
  }, [])

  return null
}
