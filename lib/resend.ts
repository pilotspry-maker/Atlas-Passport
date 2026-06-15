import { Resend } from 'resend'

export const resend = new Resend(process.env.RESEND_API_KEY)

const FROM = `${process.env.RESEND_FROM_NAME ?? 'Atlas Passport'} <${process.env.RESEND_FROM_EMAIL ?? 'noreply@atlaspassport.co'}>`

export async function sendApplicationConfirmation(to: string, name: string) {
  return resend.emails.send({
    from: FROM,
    to,
    subject: 'Your Atlas Passport application was received',
    html: `
      <div style="font-family:Georgia,serif;max-width:560px;margin:0 auto;color:#0D0D0D;">
        <h1 style="font-size:24px;margin-bottom:8px;">Thank you, ${name}.</h1>
        <p style="color:#6B6560;font-size:16px;line-height:1.6;">
          We've received your application for Atlas Passport and will review it shortly.
          You'll hear from us within 5–7 business days.
        </p>
        <p style="color:#6B6560;font-size:14px;margin-top:32px;">— The Atlas Passport Team</p>
      </div>
    `,
  })
}

export async function sendApplicationApproved(to: string, name: string, loginUrl: string) {
  return resend.emails.send({
    from: FROM,
    to,
    subject: 'Your Atlas Passport has been approved',
    html: `
      <div style="font-family:Georgia,serif;max-width:560px;margin:0 auto;color:#0D0D0D;">
        <h1 style="font-size:24px;margin-bottom:8px;">Welcome to Atlas Passport, ${name}.</h1>
        <p style="color:#6B6560;font-size:16px;line-height:1.6;">
          Your application has been approved. Click below to activate your passport and complete your profile.
        </p>
        <a href="${loginUrl}" style="display:inline-block;margin-top:24px;padding:12px 28px;background:#C4A35A;color:#0D0D0D;text-decoration:none;font-family:system-ui,sans-serif;font-size:14px;font-weight:600;letter-spacing:0.05em;">
          ACTIVATE YOUR PASSPORT
        </a>
        <p style="color:#6B6560;font-size:14px;margin-top:32px;">— The Atlas Passport Team</p>
      </div>
    `,
  })
}

export async function sendApplicationRejected(to: string, name: string) {
  return resend.emails.send({
    from: FROM,
    to,
    subject: 'Update on your Atlas Passport application',
    html: `
      <div style="font-family:Georgia,serif;max-width:560px;margin:0 auto;color:#0D0D0D;">
        <h1 style="font-size:24px;margin-bottom:8px;">Thank you for applying, ${name}.</h1>
        <p style="color:#6B6560;font-size:16px;line-height:1.6;">
          After careful review, we're unable to issue an Atlas Passport at this time.
          We encourage you to reapply in the future as your practice evolves.
        </p>
        <p style="color:#6B6560;font-size:14px;margin-top:32px;">— The Atlas Passport Team</p>
      </div>
    `,
  })
}

export async function notifyAdminNewApplication(applicationId: string, name: string, email: string) {
  const adminEmails = (process.env.ADMIN_EMAILS ?? '').split(',').map(e => e.trim()).filter(Boolean)
  if (!adminEmails.length) return

  const adminUrl = `${process.env.NEXT_PUBLIC_APP_URL}/admin`

  return resend.emails.send({
    from: FROM,
    to: adminEmails,
    subject: `New Atlas Passport application: ${name}`,
    html: `
      <div style="font-family:system-ui,sans-serif;max-width:560px;margin:0 auto;color:#0D0D0D;">
        <h2>New Application</h2>
        <p><strong>Name:</strong> ${name}</p>
        <p><strong>Email:</strong> ${email}</p>
        <p><strong>ID:</strong> ${applicationId}</p>
        <a href="${adminUrl}" style="display:inline-block;margin-top:16px;padding:10px 20px;background:#0D0D0D;color:#F5F0E8;text-decoration:none;font-size:14px;">
          Review in Admin
        </a>
      </div>
    `,
  })
}
