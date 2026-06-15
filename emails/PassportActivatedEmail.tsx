import {
  Body,
  Container,
  Head,
  Heading,
  Hr,
  Html,
  Preview,
  Section,
  Text,
  Link,
  Tailwind,
} from '@react-email/components'

interface Props {
  name: string
  corridorName: string
  city: string
  expiresAt: string
  totalNodes: number
  passportUrl: string
}

export function PassportActivatedEmail({
  name,
  corridorName,
  city,
  expiresAt,
  totalNodes,
  passportUrl,
}: Props) {
  const expiryFormatted = new Date(expiresAt).toLocaleString('en-US', {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZoneName: 'short',
  })

  return (
    <Html>
      <Head />
      <Preview>Your 72 hours begin now — {corridorName}</Preview>
      <Tailwind>
        <Body style={{ backgroundColor: '#0a0a0a', fontFamily: 'ui-sans-serif, system-ui, sans-serif', margin: 0 }}>
          <Container style={{ maxWidth: '560px', margin: '0 auto', padding: '40px 20px' }}>
            <Text style={{ color: '#c8a96e', fontSize: '11px', letterSpacing: '0.3em', textTransform: 'uppercase', marginBottom: '8px' }}>
              Atlas Passport — Relevant Artist
            </Text>

            <Heading style={{ color: '#f5f0e8', fontSize: '28px', fontWeight: 'bold', margin: '0 0 32px', lineHeight: 1.2 }}>
              {corridorName}
            </Heading>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '24px' }}>
              {name.split(' ')[0]},
            </Text>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '16px' }}>
              The clock is running. Your passport is live.
            </Text>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '24px' }}>
              You have <strong style={{ color: '#f5f0e8' }}>72 hours</strong> to complete all {totalNodes} stops on the {corridorName} in {city}. Every stop requires proof. Kaelo will review each submission before stamping your passport.
            </Text>

            <Section style={{ borderLeft: '2px solid #c8a96e', paddingLeft: '16px', marginBottom: '32px' }}>
              <Text style={{ color: '#c8a96e', fontSize: '11px', letterSpacing: '0.2em', textTransform: 'uppercase', marginBottom: '4px' }}>
                Deadline
              </Text>
              <Text style={{ color: '#f5f0e8', fontSize: '15px', margin: 0 }}>
                {expiryFormatted}
              </Text>
            </Section>

            <Link
              href={passportUrl}
              style={{ display: 'inline-block', backgroundColor: '#c8a96e', color: '#0a0a0a', padding: '12px 28px', fontWeight: 'bold', fontSize: '12px', letterSpacing: '0.15em', textTransform: 'uppercase', textDecoration: 'none', marginBottom: '32px' }}
            >
              View Your Passport →
            </Link>

            <Hr style={{ borderColor: '#2a2a2a', margin: '32px 0' }} />

            <Text style={{ color: '#555', fontSize: '12px', lineHeight: 1.6, margin: 0 }}>
              Move wisely. The corridor is yours.
              <br />
              — Kaelo
            </Text>
          </Container>
        </Body>
      </Tailwind>
    </Html>
  )
}

export default PassportActivatedEmail
