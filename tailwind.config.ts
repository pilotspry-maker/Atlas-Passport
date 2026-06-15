import type { Config } from 'tailwindcss'

const config: Config = {
  content: [
    './src/pages/**/*.{js,ts,jsx,tsx,mdx}',
    './src/components/**/*.{js,ts,jsx,tsx,mdx}',
    './src/app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  theme: {
    extend: {
      colors: {
        atlas: {
          black: '#0a0a0a',
          dark: '#111111',
          card: '#1a1a1a',
          border: '#2a2a2a',
          muted: '#555555',
          text: '#f5f0e8',
          'text-dim': '#a09888',
          gold: '#c8a96e',
          'gold-dark': '#9a7d45',
          'gold-light': '#e8c98e',
          green: '#4a7c59',
          'green-light': '#6aac79',
          red: '#7c4a4a',
          'red-light': '#ac6a6a',
        },
      },
      fontFamily: {
        mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'Monaco', 'Consolas', 'monospace'],
      },
      keyframes: {
        blink: {
          '0%, 100%': { opacity: '1' },
          '50%': { opacity: '0' },
        },
        'fade-in': {
          from: { opacity: '0', transform: 'translateY(8px)' },
          to: { opacity: '1', transform: 'translateY(0)' },
        },
        'stamp': {
          '0%': { transform: 'scale(1.4) rotate(-8deg)', opacity: '0' },
          '60%': { transform: 'scale(0.95) rotate(2deg)', opacity: '1' },
          '100%': { transform: 'scale(1) rotate(0deg)', opacity: '1' },
        },
      },
      animation: {
        blink: 'blink 1s step-end infinite',
        'fade-in': 'fade-in 0.4s ease-out',
        stamp: 'stamp 0.4s cubic-bezier(0.34, 1.56, 0.64, 1)',
      },
    },
  },
  plugins: [],
}

export default config
