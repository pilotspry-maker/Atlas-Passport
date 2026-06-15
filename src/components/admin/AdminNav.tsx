import Link from 'next/link'

interface Props {
  active: 'queue' | 'corridors' | 'users'
}

export default function AdminNav({ active }: Props) {
  const links = [
    { href: '/admin/queue', label: 'Review Queue', key: 'queue' },
    { href: '/admin/corridors', label: 'Corridors', key: 'corridors' },
    { href: '/admin/users', label: 'Users', key: 'users' },
  ] as const

  return (
    <nav className="border-b border-atlas-border mb-8">
      <div className="flex items-center gap-1 -mb-px">
        {links.map(link => (
          <Link
            key={link.key}
            href={link.href}
            className={`px-4 py-3 text-xs uppercase tracking-widest border-b-2 transition-colors ${
              active === link.key
                ? 'border-atlas-gold text-atlas-gold'
                : 'border-transparent text-atlas-muted hover:text-atlas-text'
            }`}
          >
            {link.label}
          </Link>
        ))}

        <div className="ml-auto">
          <Link
            href="/"
            className="text-xs text-atlas-muted hover:text-atlas-text transition-colors"
          >
            ← Site
          </Link>
        </div>
      </div>
    </nav>
  )
}
