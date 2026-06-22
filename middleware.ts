import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

/** Build a Supabase SSR client safe for the Vercel Edge Runtime.
 *  @supabase/realtime-js ≥2.108 throws when it detects EdgeRuntime via
 *  globalThis.EdgeRuntime before checking if native WebSocket exists.
 *  Passing `transport: globalThis.WebSocket` bypasses getWebSocketConstructor()
 *  entirely, so the RealtimeClient initialises without throwing.
 */
function makeEdgeSafeClient(
  request: NextRequest,
  getSupabaseResponse: () => NextResponse,
  setSupabaseResponse: (r: NextResponse) => void
) {
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet: { name: string; value: string; options: CookieOptions }[]) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          const next = NextResponse.next({ request })
          setSupabaseResponse(next)
          cookiesToSet.forEach(({ name, value, options }) =>
            next.cookies.set(name, value, options)
          )
        },
      },
      // Prevent @supabase/realtime-js from calling getWebSocketConstructor(),
      // which throws "Edge runtime detected" on Vercel Edge even when WebSocket
      // is natively available.
      realtime: {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        transport: (globalThis as any).WebSocket,
      },
    }
  )
}

export async function middleware(request: NextRequest) {
  if (!process.env.NEXT_PUBLIC_SUPABASE_URL || !process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY) {
    if (request.nextUrl.pathname.startsWith('/admin')) {
      const url = request.nextUrl.clone()
      url.pathname = '/auth/login'
      return NextResponse.redirect(url)
    }
    return NextResponse.next({ request })
  }

  let supabaseResponse = NextResponse.next({ request })
  let user = null

  try {
    const supabase = makeEdgeSafeClient(
      request,
      () => supabaseResponse,
      (r) => { supabaseResponse = r }
    )
    const { data } = await supabase.auth.getUser()
    user = data.user
  } catch {
    return NextResponse.next({ request })
  }

  const { pathname } = request.nextUrl

  const protectedPrefixes = ['/passport', '/corridors', '/nodes']
  const isProtected = protectedPrefixes.some(p => pathname.startsWith(p))

  if (isProtected && !user) {
    const url = request.nextUrl.clone()
    url.pathname = '/auth/login'
    url.searchParams.set('redirectTo', pathname)
    return NextResponse.redirect(url)
  }

  if (pathname.startsWith('/admin')) {
    if (!user) {
      const url = request.nextUrl.clone()
      url.pathname = '/auth/login'
      url.searchParams.set('redirectTo', pathname)
      return NextResponse.redirect(url)
    }

    try {
      const adminSupabase = makeEdgeSafeClient(
        request,
        () => supabaseResponse,
        (r) => { supabaseResponse = r }
      )
      const { data: profileData } = await adminSupabase
        .from('profiles')
        .select('is_admin')
        .eq('id', user.id)
        .single()

      const profile = profileData as { is_admin?: boolean } | null
      if (!profile?.is_admin) {
        const url = request.nextUrl.clone()
        url.pathname = '/'
        return NextResponse.redirect(url)
      }
    } catch {
      const url = request.nextUrl.clone()
      url.pathname = '/'
      return NextResponse.redirect(url)
    }
  }

  if (pathname === '/auth/login' && user) {
    const url = request.nextUrl.clone()
    url.pathname = '/passport'
    return NextResponse.redirect(url)
  }

  return supabaseResponse
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
