import {
  Body, Container, Head, Heading, Hr, Html, Preview, Section, Text, Link, Tailwind,
} from '@react-email/components'

interface Props {
  name: string
  corridorName: string
  rewardTitle: string
  rewardCode?: string | null
  rewardUrl: string
}

export function CorridorCompleteEmail({ name, corridorName, rewardTitle, rewardCode, rewardUrl }: Props) {
  return (
    <Html>
      <Head />
      <Preview>You&apos;ve completed the {corridorName} — your reward awaits</Preview>
      <Tailwind>
        <Body style={{ backgroundColor: '#0a0a0a', fontFamily: 'ui-sans-serif, system-ui, sans-serif', margin: 0 }}>
          <Container style={{ maxWidth: '560px', margin: '0 auto', padding: '40px 20px' }}>
            <Text style={{ color: '#c8a96e', fontSize: '11px', letterSpacing: '0.3em', textTransform: 'uppercase', marginBottom: '8px' }}>
              Atlas Passport — Journey Complete
            </Text>

            <Heading style={{ color: '#f5f0e8', fontSize: '28px', fontWeight: 'bold', margin: '0 0 8px' }}>
              ✦
            </Heading>

            <Heading style={{ color: '#f5f0e8', fontSize: '24px', fontWeight: 'bold', margin: '0 0 24px' }}>
              Every stamp collected.
            </Heading>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '16px' }}>
              {name.split(' ')[0]},
            </Text>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '24px' }}>
              The {corridorName} is yours. Kaelo has stamped every stop. You moved fast, you moved right — and you earned it.
            </Text>

            <Section style={{ border: '1px solid #c8a96e', padding: '20px', marginBottom: '32px' }}>
              <Text style={{ color: '#c8a96e', fontSize: '11px', letterSpacing: '0.2em', textTransform: 'uppercase', marginBottom: '8px' }}>
                Your Reward
              </Text>
              <Text style={{ color: '#f5f0e8', fontSize: '18px', fontWeight: 'bold', margin: '0 0 8px' }}>
                {rewardTitle}
              </Text>
              {rewardCode && (
                <>
                  <Text style={{ color: '#555', fontSize: '11px', letterSpacing: '0.1em', textTransform: 'uppercase', margin: '16px 0 4px' }}>
                    Redemption Code
                  </Text>
                  <Text style={{ color: '#c8a96e', fontSize: '20px', fontFamily: 'ui-monospace, monospace', letterSpacing: '0.2em', margin: 0 }}>
                    {rewardCode}
                  </Text>
                </>
              )}
            </Section>

            <Link
              href={rewardUrl}
              style={{ display: 'inline-block', backgroundColor: '#c8a96e', color: '#0a0a0a', padding: '12px 28px', fontWeight: 'bold', fontSize: '12px', letterSpacing: '0.15em', textTransform: 'uppercase', textDecoration: 'none', marginBottom: '32px' }}
            >
              View Reward →
            </Link>

            <Hr style={{ borderColor: '#2a2a2a', margin: '32px 0' }} />
            <Text style={{ color: '#555', fontSize: '12px', lineHeight: 1.6 }}>
              The corridor remembers everyone who finishes.
              <br />
              — Kaelo
            </Text>
          </Container>
        </Body>
      </Tailwind>
    </Html>
  )
}

export default CorridorCompleteEmail
