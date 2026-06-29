import { describe, expect, it } from 'vitest'
import { AUTH_ERROR_COPY, formatAuthError } from '../auth-errors'

describe('formatAuthError', () => {
  describe('pwned password', () => {
    it('detects HIBP rejection via code + weakPassword.reasons', () => {
      const result = formatAuthError({
        code: 'weak_password',
        message: 'Password is known to be weak and easy to guess.',
        weakPassword: { reasons: ['pwned'] },
      })
      expect(result.kind).toBe('pwned_password')
      expect(result.message).toBe(AUTH_ERROR_COPY.PWNED_PASSWORD_MESSAGE)
    })

    it('detects HIBP rejection when only the message mentions pwned', () => {
      // Defensive fallback for older supabase-js shapes.
      const result = formatAuthError({
        message: 'Password rejected: pwned',
      })
      expect(result.kind).toBe('pwned_password')
      expect(result.message).toBe(AUTH_ERROR_COPY.PWNED_PASSWORD_MESSAGE)
    })

    it('detects HIBP rejection when pwned is one of multiple reasons', () => {
      const result = formatAuthError({
        code: 'weak_password',
        weakPassword: { reasons: ['length', 'pwned'] },
      })
      expect(result.kind).toBe('pwned_password')
    })
  })

  describe('other weak password reasons', () => {
    it('uses generic weak-password copy when reasons do not include pwned', () => {
      const result = formatAuthError({
        code: 'weak_password',
        weakPassword: { reasons: ['length', 'characters'] },
      })
      expect(result.kind).toBe('weak_password')
      expect(result.message).toBe(AUTH_ERROR_COPY.WEAK_PASSWORD_MESSAGE)
    })

    it('handles weak_password code with no reasons array', () => {
      const result = formatAuthError({ code: 'weak_password' })
      expect(result.kind).toBe('weak_password')
    })
  })

  describe('rate limit', () => {
    it('matches over_request_rate_limit code', () => {
      const result = formatAuthError({ code: 'over_request_rate_limit' })
      expect(result.kind).toBe('rate_limit')
      expect(result.message).toBe(AUTH_ERROR_COPY.RATE_LIMIT_MESSAGE)
    })

    it('matches rate limit phrasing in message', () => {
      const result = formatAuthError({ message: 'too many requests' })
      expect(result.kind).toBe('rate_limit')
    })
  })

  describe('network errors', () => {
    it('matches Load failed', () => {
      const result = formatAuthError({ message: 'Load failed' })
      expect(result.kind).toBe('network')
      expect(result.message).toBe(AUTH_ERROR_COPY.NETWORK_MESSAGE)
    })

    it('matches Failed to fetch', () => {
      const result = formatAuthError({ message: 'Failed to fetch' })
      expect(result.kind).toBe('network')
    })

    it('matches NetworkError in message', () => {
      const result = formatAuthError({ message: 'NetworkError when attempting to fetch resource' })
      expect(result.kind).toBe('network')
    })
  })

  describe('invalid input', () => {
    it('surfaces the raw reason for "not allowed" messages', () => {
      const result = formatAuthError({ message: 'Email not allowed for signup' })
      expect(result.kind).toBe('invalid_input')
      expect(result.message).toContain('Email not allowed for signup')
    })
  })

  describe('fallback', () => {
    it('returns generic message for null/undefined', () => {
      expect(formatAuthError(null).kind).toBe('unknown')
      expect(formatAuthError(undefined).kind).toBe('unknown')
      expect(formatAuthError(null).message).toBe(AUTH_ERROR_COPY.GENERIC_MESSAGE)
    })

    it('falls through to raw message for unknown errors', () => {
      const result = formatAuthError({ message: 'something unexpected' })
      expect(result.kind).toBe('unknown')
      expect(result.message).toBe('something unexpected')
    })

    it('returns generic when there is no message and nothing matches', () => {
      const result = formatAuthError({})
      expect(result.kind).toBe('unknown')
      expect(result.message).toBe(AUTH_ERROR_COPY.GENERIC_MESSAGE)
    })
  })
})
