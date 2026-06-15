'use client'

import { useCountdown } from '@/hooks/useCountdown'

interface Props {
  expiresAt: string
}

export default function CountdownTimer({ expiresAt }: Props) {
  const { hours, minutes, seconds, expired } = useCountdown(expiresAt)
  const isCritical = hours < 6 && !expired

  if (expired) {
    return (
      <div className="text-center">
        <p className="text-xs text-atlas-muted uppercase tracking-widest mb-2">
          Passport Status
        </p>
        <div className="text-2xl font-bold text-atlas-red-light tracking-wider font-mono">
          EXPIRED
        </div>
      </div>
    )
  }

  const pad = (n: number) => String(n).padStart(2, '0')

  return (
    <div className="text-center">
      <p className="text-xs text-atlas-muted uppercase tracking-widest mb-3">
        Time Remaining
      </p>
      <div
        className={`font-mono text-5xl sm:text-6xl font-bold tracking-wider transition-colors ${
          isCritical ? 'text-atlas-red-light' : 'text-atlas-gold'
        }`}
      >
        {pad(hours)}
        <span className={`${isCritical ? 'animate-blink' : ''} opacity-60 mx-1`}>:</span>
        {pad(minutes)}
        <span className={`${isCritical ? 'animate-blink' : ''} opacity-60 mx-1`}>:</span>
        {pad(seconds)}
      </div>
      <p className="text-xs text-atlas-muted mt-2 tracking-widest">
        HH&nbsp;&nbsp;MM&nbsp;&nbsp;SS
      </p>
      {isCritical && (
        <p className="mt-3 text-xs text-atlas-red-light animate-pulse">
          Final hours — move now
        </p>
      )}
    </div>
  )
}
