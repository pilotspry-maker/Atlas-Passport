import {
  Body, Container, Head, Heading, Hr, Html, Preview, Section, Text, Link, Tailwind,
} from '@react-email/components'

interface Props {
  name: string
  corridorName: string
  expiresAt: string
  approvedCount: number
  totalNodes: number
  passportUrl: string
}

export function TimerWarningEmail({ name, corridorName, expiresAt, approvedCount, totalNodes, passportUrl }: Props) {
  const remaining = totalNodes - approvedCount
  const expiryFormatted = new Date(expiresAt).toLocaleString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZoneName: 'short',
  })

  return (
    <Html>
      <Head />
      <Preview>24 hours left on your Atlas Passport — {corridorName}</Preview>
      <Tailwind>
        <Body style={{ backgroundColor: '#0a0a0a', fontFamily: 'ui-sans-serif, system-ui, sans-serif', margin: 0 }}>
          <Container style={{ maxWidth: '560px', margin: '0 auto', padding: '40px 20px' }}>
            <Text style={{ color: '#7c4a4a', fontSize: '11px', letterSpacing: '0.3em', textTransform: 'uppercase', marginBottom: '8px' }}>
              ⚠ Atlas Passport — Time Warning
            </Text>

            <Heading style={{ color: '#f5f0e8', fontSize: '24px', fontWeight: 'bold', margin: '0 0 24px' }}>
              24 hours remaining.
            </Heading>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '16px' }}>
              {name.split(' ')[0]}, the clock on the {corridorName} is running out.
            </Text>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '24px' }}>
              You&apos;ve stamped <strong style={{ color: '#c8a96e' }}>{approvedCount}</strong> of {totalNodes} stops.
              {remaining > 0
                ? ` ${remaining} ${remaining === 1 ? 'stop remains' : 'stops remain'}. Move now.`
                : ' All stops are submitted — wait for Kaelo\'s review.'}
            </Text>

            <Section style={{ border: '1px solid #7c4a4a', padding: '16px', marginBottom: '32px' }}>
              <Text style={{ color: '#7c4a4a', fontSize: '11px', letterSpacing: '0.2em', textTransform: 'uppercase', marginBottom: '4px' }}>
                Passport Expires
              </Text>
              <Text style={{ color: '#f5f0e8', fontSize: '15px', margin: 0 }}>
                {expiryFormatted}
              </Text>
            </Section>

            <Link
              href={passportUrl}
              style={{ display: 'inline-block', backgroundColor: '#c8a96e', color: '#0a0a0a', padding: '12px 28px', fontWeight: 'bold', fontSize: '12px', letterSpacing: '0.15em', textTransform: 'uppercase', textDecoration: 'none', marginBottom: '32px' }}
            >
              Open Passport →
            </Link>

            <Hr style={{ borderColor: '#2a2a2a', margin: '32px 0' }} />
            <Text style={{ color: '#555', fontSize: '12px' }}>Don&apos;t wait. — Kaelo</Text>
          </Container>
        </Body>
      </Tailwind>
    </Html>
  )
}

export default TimerWarningEmail
