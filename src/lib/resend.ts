import { Resend } from 'resend'

export const resend = new Resend(process.env.RESEND_API_KEY)

export const FROM = `Kaelo <${process.env.RESEND_FROM_EMAIL ?? 'kaelo@atlaspassport.com'}>`
