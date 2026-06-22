import { NextResponse, type NextRequest } from 'next/server'

// Diagnostic: minimal pass-through to confirm Edge Runtime works without Supabase.
// Auth redirects are temporarily disabled — pages still validate auth server-side.
export function middleware(request: NextRequest) {
  return NextResponse.next()
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
