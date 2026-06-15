'use client'

import { useState, useEffect } from 'react'

export function useCountdown(expiresAt: string | null) {
  const [timeLeft, setTimeLeft] = useState<{
    hours: number
    minutes: number
    seconds: number
    total: number
    expired: boolean
  }>({
    hours: 0,
    minutes: 0,
    seconds: 0,
    total: 0,
    expired: false,
  })

  useEffect(() => {
    if (!expiresAt) return

    function calculate() {
      const ms = new Date(expiresAt!).getTime() - Date.now()
      if (ms <= 0) {
        setTimeLeft({ hours: 0, minutes: 0, seconds: 0, total: 0, expired: true })
        return
      }
      const totalSeconds = Math.floor(ms / 1000)
      setTimeLeft({
        hours: Math.floor(totalSeconds / 3600),
        minutes: Math.floor((totalSeconds % 3600) / 60),
        seconds: totalSeconds % 60,
        total: ms,
        expired: false,
      })
    }

    calculate()
    const interval = setInterval(calculate, 1000)
    return () => clearInterval(interval)
  }, [expiresAt])

  return timeLeft
}
