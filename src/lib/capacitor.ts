// Atlas Passport — Capacitor native bridge
// Wraps all native plugin calls with web fallbacks so code works on both
// web (PWA) and native (iOS via Capacitor) without conditional imports everywhere

import { Capacitor } from '@capacitor/core'

export const isNative = Capacitor.isNativePlatform()
export const isIos = Capacitor.getPlatform() === 'ios'

// ─── Push Notifications ───────────────────────────────────────────────────────
export async function requestPushPermission(): Promise<boolean> {
  if (!isNative) {
    // Web: use the Notifications API
    if (!('Notification' in window)) return false
    const permission = await Notification.requestPermission()
    return permission === 'granted'
  }

  const { PushNotifications } = await import('@capacitor/push-notifications')
  const result = await PushNotifications.requestPermissions()
  if (result.receive === 'granted') {
    await PushNotifications.register()
    return true
  }
  return false
}

export async function onPushToken(callback: (token: string) => void) {
  if (!isNative) return
  const { PushNotifications } = await import('@capacitor/push-notifications')
  await PushNotifications.addListener('registration', (token) => {
    callback(token.value)
  })
}

// ─── Local Notifications (72-hour countdown) ──────────────────────────────────
export async function scheduleCorridorExpiryAlert(expiresAt: Date) {
  if (!isNative) return

  const { LocalNotifications } = await import('@capacitor/local-notifications')
  const perm = await LocalNotifications.requestPermissions()
  if (perm.display !== 'granted') return

  // 1-hour warning
  const oneHourBefore = new Date(expiresAt.getTime() - 60 * 60 * 1000)
  if (oneHourBefore > new Date()) {
    await LocalNotifications.schedule({
      notifications: [
        {
          id: 1001,
          title: 'Atlas Passport',
          body: 'Your corridor closes in 1 hour. Complete the remaining nodes.',
          schedule: { at: oneHourBefore },
          sound: undefined,
          smallIcon: 'ic_stat_icon_config_sample',
        },
      ],
    })
  }

  // Expiry notification
  await LocalNotifications.schedule({
    notifications: [
      {
        id: 1002,
        title: 'Passport Expired',
        body: 'Your 72-hour corridor has closed. Activate a new passport to continue.',
        schedule: { at: expiresAt },
        sound: undefined,
        smallIcon: 'ic_stat_icon_config_sample',
      },
    ],
  })
}

// ─── Haptic Feedback ──────────────────────────────────────────────────────────
export async function hapticSuccess() {
  if (!isNative) return
  const { Haptics, ImpactStyle } = await import('@capacitor/haptics')
  await Haptics.impact({ style: ImpactStyle.Medium })
}

export async function hapticError() {
  if (!isNative) return
  const { Haptics, NotificationType } = await import('@capacitor/haptics')
  await Haptics.notification({ type: NotificationType.Error })
}

export async function hapticLight() {
  if (!isNative) return
  const { Haptics, ImpactStyle } = await import('@capacitor/haptics')
  await Haptics.impact({ style: ImpactStyle.Light })
}

// ─── Share Sheet ──────────────────────────────────────────────────────────────
export async function sharePassport(passportId: string) {
  const shareData = {
    title: 'Atlas Passport',
    text: `I'm on the Atlas Passport — 72 hours, one corridor. Join the journey.`,
    url: `https://atlas-passport.vercel.app/join?ref=${passportId}`,
  }

  if (isNative) {
    const { Share } = await import('@capacitor/share')
    await Share.share(shareData)
  } else if (navigator.share) {
    await navigator.share(shareData)
  } else {
    await navigator.clipboard.writeText(shareData.url)
  }
}
