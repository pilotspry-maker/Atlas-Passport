import {
  Body, Container, Head, Heading, Hr, Html, Preview, Section, Text, Link, Tailwind,
} from '@react-email/components'

interface Props {
  name: string
  nodeName: string
  corridorName: string
  sequence: number
  totalNodes: number
  passportUrl: string
}

export function CheckInReceivedEmail({ name, nodeName, corridorName, sequence, totalNodes, passportUrl }: Props) {
  return (
    <Html>
      <Head />
      <Preview>Kaelo received your proof at {nodeName}</Preview>
      <Tailwind>
        <Body style={{ backgroundColor: '#0a0a0a', fontFamily: 'ui-sans-serif, system-ui, sans-serif', margin: 0 }}>
          <Container style={{ maxWidth: '560px', margin: '0 auto', padding: '40px 20px' }}>
            <Text style={{ color: '#c8a96e', fontSize: '11px', letterSpacing: '0.3em', textTransform: 'uppercase', marginBottom: '8px' }}>
              Atlas Passport
            </Text>

            <Heading style={{ color: '#f5f0e8', fontSize: '24px', fontWeight: 'bold', margin: '0 0 24px' }}>
              Proof received — {nodeName}
            </Heading>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '16px' }}>
              {name.split(' ')[0]}, your submission for stop {sequence} of {totalNodes} on the {corridorName} is in Kaelo&apos;s hands.
            </Text>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '24px' }}>
              Review typically takes a few hours. Once stamped, you&apos;ll hear from Kaelo — keep moving in the meantime.
            </Text>

            <Section style={{ border: '1px solid #2a2a2a', padding: '16px', marginBottom: '32px' }}>
              <Text style={{ color: '#555', fontSize: '11px', letterSpacing: '0.2em', textTransform: 'uppercase', marginBottom: '4px' }}>
                Stop
              </Text>
              <Text style={{ color: '#f5f0e8', fontSize: '15px', margin: '0 0 8px' }}>
                {nodeName}
              </Text>
              <Text style={{ color: '#555', fontSize: '12px', margin: 0 }}>
                {sequence} of {totalNodes} — {corridorName}
              </Text>
            </Section>

            <Link
              href={passportUrl}
              style={{ display: 'inline-block', border: '1px solid #c8a96e', color: '#c8a96e', padding: '10px 24px', fontSize: '12px', letterSpacing: '0.15em', textTransform: 'uppercase', textDecoration: 'none', marginBottom: '32px' }}
            >
              View Passport →
            </Link>

            <Hr style={{ borderColor: '#2a2a2a', margin: '32px 0' }} />
            <Text style={{ color: '#555', fontSize: '12px' }}>— Kaelo</Text>
          </Container>
        </Body>
      </Tailwind>
    </Html>
  )
}

export default CheckInReceivedEmail
