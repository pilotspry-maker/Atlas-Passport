import type { PassportFull } from '@/types/database'

export function getPassportProgress(passport: PassportFull): {
  total: number
  approved: number
  pending: number
  rejected: number
  percent: number
} {
  const total = passport.nodes.length
  const approved = passport.nodes.filter(n => n.check_in?.status === 'approved').length
  const pending = passport.nodes.filter(n => n.check_in?.status === 'pending').length
  const rejected = passport.nodes.filter(n => n.check_in?.status === 'rejected').length
  const percent = total > 0 ? Math.round((approved / total) * 100) : 0

  return { total, approved, pending, rejected, percent }
}

export function isPassportExpired(expiresAt: string): boolean {
  return new Date(expiresAt).getTime() < Date.now()
}

export function isPassportComplete(passport: PassportFull): boolean {
  return (
    passport.nodes.length > 0 &&
    passport.nodes.every(n => n.check_in?.status === 'approved')
  )
}

export function getHoursRemaining(expiresAt: string): number {
  const ms = new Date(expiresAt).getTime() - Date.now()
  return Math.max(0, ms / (1000 * 60 * 60))
}
