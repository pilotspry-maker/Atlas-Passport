/**
 * Translate Supabase Auth errors into user-friendly copy.
 *
 * This module is isomorphic (no Next.js server imports) so it can be imported
 * from both server components and `'use client'` components.
 *
 * Why it exists
 * -------------
 * Atlas-Passport's only live auth surface today is the passwordless magic-link
 * flow at /auth/login (see MagicLinkForm). The errors that flow surfaces are
 * network / rate-limit / validation errors — there is no password set, so
 * leaked-password protection cannot fire from the current UI.
 *
 * However, leaked-password protection (HIBP / "Pwned Passwords") is now
 * enabled on the project (advisor sweep 2026-06-29, PR #49 follow-up). The
 * moment ANY password-touching path is added — a password reset, an admin
 * "set initial password" tool, a future email+password fallback — Supabase
 * will start returning `weak_password` with a `pwned` reason, and without a
 * dedicated handler the user will see something cryptic like:
 *
 *     "Password is known to be weak and easy to guess, please choose a
 *      different one (Reasons: pwned)"
 *
 * `formatAuthError` catches that case explicitly and renders the friendly
 * message we agreed on in the security follow-up:
 *
 *     "This password has appeared in known data breaches. Please choose a
 *      different one."
 *
 * It also subsumes the inline string-matching that MagicLinkForm was doing
 * (network errors, rate limits) so we have one place to maintain auth copy.
 */

import type { AuthError } from '@supabase/supabase-js'

/**
 * The minimal shape we read from a Supabase auth error. We accept either the
 * official `AuthError` type or any error-like object (e.g. plain `Error`,
 * objects thrown from a fetch). Anything we can't classify falls through to
 * a generic message.
 */
type AuthErrorLike = Partial<AuthError> & {
  message?: string
  code?: string
  /**
   * Set by `signInWithPassword` / `signUp` / `updateUser` when the new
   * password fails server-side strength rules. The `pwned` reason indicates
   * an HIBP / Pwned-Passwords API match.
   *
   * Shape from `@supabase/supabase-js`:
   *   { message: string, reasons: Array<'length' | 'characters' | 'pwned'> }
   */
  weakPassword?: {
    message?: string
    reasons?: string[]
  }
}

export interface FormattedAuthError {
  /** Stable kind for telemetry / tests / branching UI. */
  kind:
    | 'pwned_password'
    | 'weak_password'
    | 'rate_limit'
    | 'network'
    | 'invalid_input'
    | 'unknown'
  /** Short, user-facing copy. Safe to render directly. */
  message: string
}

const PWNED_PASSWORD_MESSAGE =
  'This password has appeared in known data breaches. Please choose a different one.'

const WEAK_PASSWORD_MESSAGE =
  'That password is too weak. Try a longer one with a mix of letters, numbers, and symbols.'

const RATE_LIMIT_MESSAGE =
  'Too many attempts. Please wait a minute before trying again.'

const NETWORK_MESSAGE =
  'Connection error — please check your internet and try again.'

const GENERIC_MESSAGE = 'Something went wrong. Please try again.'

/**
 * Returns a `FormattedAuthError` for any auth-related error from Supabase.
 *
 * Order of checks matters: `weak_password` is detected BEFORE generic
 * string matching, because the `pwned` reason is what we most want to
 * surface clearly.
 */
export function formatAuthError(error: unknown): FormattedAuthError {
  if (!error) return { kind: 'unknown', message: GENERIC_MESSAGE }

  const err = error as AuthErrorLike
  const rawMessage =
    typeof err.message === 'string' && err.message.length > 0
      ? err.message
      : ''
  const code = typeof err.code === 'string' ? err.code : ''

  // 1) Weak password — the case this helper exists for.
  //
  // Supabase Auth returns code `weak_password` with a populated
  // `weakPassword.reasons` array on signUp / updateUser / signInWithPassword.
  // We treat any presence of the `pwned` reason as the strongest signal
  // and surface dedicated copy. Other reasons (length, characters) get
  // generic weak-password copy.
  if (code === 'weak_password' || err.weakPassword) {
    const reasons = err.weakPassword?.reasons ?? []
    if (reasons.includes('pwned')) {
      return { kind: 'pwned_password', message: PWNED_PASSWORD_MESSAGE }
    }
    return { kind: 'weak_password', message: WEAK_PASSWORD_MESSAGE }
  }

  // Belt-and-braces: very old supabase-js versions surfaced HIBP rejections
  // only via the message string. Match defensively.
  if (/pwned/i.test(rawMessage)) {
    return { kind: 'pwned_password', message: PWNED_PASSWORD_MESSAGE }
  }

  // 2) Rate limit — keep the existing MagicLinkForm copy.
  if (
    code === 'over_request_rate_limit' ||
    code === 'over_email_send_rate_limit' ||
    /rate limit|too many/i.test(rawMessage)
  ) {
    return { kind: 'rate_limit', message: RATE_LIMIT_MESSAGE }
  }

  // 3) Network / fetch failure — keep the existing MagicLinkForm copy.
  if (
    rawMessage === 'Load failed' ||
    rawMessage === 'Failed to fetch' ||
    /networkerror|fetch/i.test(rawMessage)
  ) {
    return { kind: 'network', message: NETWORK_MESSAGE }
  }

  // 4) Validation / "not allowed" — surface the raw reason since it's
  //    usually actionable (e.g. "email not allowed by domain rules").
  if (/not allowed|invalid/i.test(rawMessage)) {
    return { kind: 'invalid_input', message: `Sign-in failed: ${rawMessage}` }
  }

  // 5) Fallback — surface whatever the server said, or a generic message.
  return {
    kind: 'unknown',
    message: rawMessage || GENERIC_MESSAGE,
  }
}

// Export the constants for tests so copy can be asserted without duplication.
export const AUTH_ERROR_COPY = {
  PWNED_PASSWORD_MESSAGE,
  WEAK_PASSWORD_MESSAGE,
  RATE_LIMIT_MESSAGE,
  NETWORK_MESSAGE,
  GENERIC_MESSAGE,
} as const
