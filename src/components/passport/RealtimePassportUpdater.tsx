'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

interface Props {
  passportId: string
  passportStatus: string
}

export default function RealtimePassportUpdater({ passportId, passportStatus }: Props) {
  const router = useRouter()

  useEffect(() => {
    // Only subscribe while the passport can still receive updates. For
    // complete/expired passports the realtime channel is dead weight — no rows
    // will change, and the websocket adds bootup cost on /passport.
    if (passportStatus !== 'active') return

    // Defer the websocket connection out of the hydration critical path. This
    // keeps the realtime client's setup work off the main thread during the
    // initial render so it doesn't inflate TBT on first paint of /passport.
    let channel: ReturnType<ReturnType<typeof createClient>['channel']> | null = null
    let cancelled = false

    const timer = setTimeout(() => {
      if (cancelled) return
      const supabase = createClient()

      channel = supabase
        .channel(`passport-updates-${passportId}`)
        .on(
          'postgres_changes',
          {
            event: 'UPDATE',
            schema: 'public',
            table: 'check_ins_player_view',
            filter: `passport_id=eq.${passportId}`,
          },
          () => {
            router.refresh()
          }
        )
        .on(
          'postgres_changes',
          {
            event: 'UPDATE',
            schema: 'public',
            table: 'passports',
            filter: `id=eq.${passportId}`,
          },
          () => {
            router.refresh()
          }
        )
        .subscribe()
    }, 0)

    return () => {
      cancelled = true
      clearTimeout(timer)
      if (channel) {
        const supabase = createClient()
        supabase.removeChannel(channel)
      }
    }
  }, [passportId, passportStatus, router])

  return null
}
