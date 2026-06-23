import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { createServerClient, type CookieOptions } from '@supabase/ssr'

const PROTECTED_PATHS = ['/passport', '/corridors', '/nodes', '/admin']

export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl

  // API routes handle their own auth; skip to avoid unnecessary session checks
  if (pathname.startsWith('/api/')) {
    return NextResponse.next()
  }

  const response = NextResponse.next()

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (cookiesToSet: Array<{ name: string; value: string; options: CookieOptions }>) =>
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options as Parameters<typeof response.cookies.set>[2])
          ),
      },
    }
  )

  // getUser() refreshes the session token when needed
  const { data: { user } } = await supabase.auth.getUser()

  if (!user && PROTECTED_PATHS.some(p => pathname.startsWith(p))) {
    const loginUrl = new URL('/auth/login', request.url)
    loginUrl.searchParams.set('next', pathname)
    return NextResponse.redirect(loginUrl)
  }

  if (user && pathname === '/auth/login') {
    return NextResponse.redirect(new URL('/passport', request.url))
  }

  return response
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
