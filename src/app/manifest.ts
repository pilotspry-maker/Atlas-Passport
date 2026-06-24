import type { MetadataRoute } from 'next'

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Atlas Passport',
    short_name: 'Atlas',
    description: 'A 72-hour real-world journey. Activate your passport. Complete the corridor. Claim your reward.',
    start_url: '/',
    display: 'standalone',
    background_color: '#0a0a0a',
    theme_color: '#0a0a0a',
    orientation: 'portrait',
    scope: '/',
    lang: 'en',
    categories: ['travel', 'lifestyle', 'entertainment'],
    icons: [
      {
        src: '/icons/icon-192.png',
        sizes: '192x192',
        type: 'image/png',
        purpose: 'any',
      },
      {
        src: '/icons/icon-192-maskable.png',
        sizes: '192x192',
        type: 'image/png',
        purpose: 'maskable',
      },
      {
        src: '/icons/icon-512.png',
        sizes: '512x512',
        type: 'image/png',
        purpose: 'any',
      },
      {
        src: '/icons/icon-512-maskable.png',
        sizes: '512x512',
        type: 'image/png',
        purpose: 'maskable',
      },
    ],
    screenshots: [
      {
        src: '/screenshots/mobile-home.png',
        sizes: '390x844',
        type: 'image/png',
        // @ts-expect-error — form_factor is valid in the spec, TS types lag
        form_factor: 'narrow',
        label: 'Atlas Passport Home',
      },
      {
        src: '/screenshots/mobile-passport.png',
        sizes: '390x844',
        type: 'image/png',
        // @ts-expect-error
        form_factor: 'narrow',
        label: 'Active Corridor Passport',
      },
    ],
    shortcuts: [
      {
        name: 'My Passport',
        short_name: 'Passport',
        description: 'View your active corridor passport',
        url: '/dashboard',
        icons: [{ src: '/icons/icon-192.png', sizes: '192x192' }],
      },
    ],
    prefer_related_applications: false,
  }
}
