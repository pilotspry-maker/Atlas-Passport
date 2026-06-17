import { getResend, FROM } from './resend'
import { PassportActivatedEmail } from '../../emails/PassportActivatedEmail'
import { CheckInReceivedEmail }   from '../../emails/CheckInReceivedEmail'
import { CheckInApprovedEmail }   from '../../emails/CheckInApprovedEmail'
import { CheckInRejectedEmail }   from '../../emails/CheckInRejectedEmail'
import { TimerWarningEmail }      from '../../emails/TimerWarningEmail'
import { CorridorCompleteEmail }  from '../../emails/CorridorCompleteEmail'

const APP_URL = process.env.NEXT_PUBLIC_APP_URL
  ?? (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : 'http://localhost:3000')
if (!process.env.NEXT_PUBLIC_APP_URL && process.env.NODE_ENV === 'production') {
  console.error('[email] NEXT_PUBLIC_APP_URL is not set — email links will use Vercel URL fallback')
}

export async function sendPassportActivatedEmail(opts: {
  to: string
  name: string
  corridorName: string
  city: string
  expiresAt: string
  totalNodes: number
}) {
  return getResend().emails.send({
    from: FROM,
    to: opts.to,
    subject: `Your 72 hours begin now — ${opts.corridorName}`,
    react: PassportActivatedEmail({
      ...opts,
      passportUrl: `${APP_URL}/passport`,
    }),
  })
}

export async function sendCheckInReceivedEmail(opts: {
  to: string
  name: string
  nodeName: string
  corridorName: string
  sequence: number
  totalNodes: number
}) {
  return getResend().emails.send({
    from: FROM,
    to: opts.to,
    subject: `Kaelo received your proof — ${opts.nodeName}`,
    react: CheckInReceivedEmail({
      ...opts,
      passportUrl: `${APP_URL}/passport`,
    }),
  })
}

export async function sendCheckInApprovedEmail(opts: {
  to: string
  name: string
  nodeName: string
  corridorName: string
  sequence: number
  totalNodes: number
  isLastNode: boolean
}) {
  return getResend().emails.send({
    from: FROM,
    to: opts.to,
    subject: `Stamp approved — ${opts.nodeName}`,
    react: CheckInApprovedEmail({
      ...opts,
      passportUrl: `${APP_URL}/passport`,
    }),
  })
}

export async function sendCheckInRejectedEmail(opts: {
  to: string
  name: string
  nodeName: string
  corridorName: string
  adminNotes: string
}) {
  return getResend().emails.send({
    from: FROM,
    to: opts.to,
    subject: `Kaelo needs a clearer proof — ${opts.nodeName}`,
    react: CheckInRejectedEmail({
      ...opts,
      passportUrl: `${APP_URL}/passport`,
    }),
  })
}

export async function sendTimerWarningEmail(opts: {
  to: string
  name: string
  corridorName: string
  expiresAt: string
  approvedCount: number
  totalNodes: number
}) {
  return getResend().emails.send({
    from: FROM,
    to: opts.to,
    subject: `24 hours left on your Atlas Passport`,
    react: TimerWarningEmail({
      ...opts,
      passportUrl: `${APP_URL}/passport`,
    }),
  })
}

export async function sendCorridorCompleteEmail(opts: {
  to: string
  name: string
  corridorName: string
  rewardTitle: string
  rewardCode?: string | null
}) {
  return getResend().emails.send({
    from: FROM,
    to: opts.to,
    subject: `You've completed the ${opts.corridorName} — your reward awaits`,
    react: CorridorCompleteEmail({
      ...opts,
      rewardUrl: `${APP_URL}/passport/complete`,
    }),
  })
}
