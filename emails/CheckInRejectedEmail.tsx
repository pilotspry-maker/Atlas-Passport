import {
  Body, Container, Head, Heading, Hr, Html, Preview, Section, Text, Link, Tailwind,
} from '@react-email/components'

interface Props {
  name: string
  nodeName: string
  corridorName: string
  adminNotes: string
  passportUrl: string
}

export function CheckInRejectedEmail({ name, nodeName, corridorName, adminNotes, passportUrl }: Props) {
  return (
    <Html>
      <Head />
      <Preview>Kaelo needs a clearer proof — {nodeName}</Preview>
      <Tailwind>
        <Body style={{ backgroundColor: '#0a0a0a', fontFamily: 'ui-sans-serif, system-ui, sans-serif', margin: 0 }}>
          <Container style={{ maxWidth: '560px', margin: '0 auto', padding: '40px 20px' }}>
            <Text style={{ color: '#c8a96e', fontSize: '11px', letterSpacing: '0.3em', textTransform: 'uppercase', marginBottom: '8px' }}>
              Atlas Passport
            </Text>

            <Heading style={{ color: '#f5f0e8', fontSize: '24px', fontWeight: 'bold', margin: '0 0 24px' }}>
              Proof not accepted — {nodeName}
            </Heading>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '24px' }}>
              {name.split(' ')[0]}, Kaelo reviewed your submission for <strong style={{ color: '#f5f0e8' }}>{nodeName}</strong> on the {corridorName} but couldn&apos;t stamp it.
            </Text>

            <Section style={{ borderLeft: '2px solid #7c4a4a', paddingLeft: '16px', marginBottom: '24px' }}>
              <Text style={{ color: '#7c4a4a', fontSize: '11px', letterSpacing: '0.2em', textTransform: 'uppercase', marginBottom: '4px' }}>
                Kaelo&apos;s Note
              </Text>
              <Text style={{ color: '#f5f0e8', fontSize: '14px', lineHeight: 1.6, margin: 0, fontStyle: 'italic' }}>
                &quot;{adminNotes}&quot;
              </Text>
            </Section>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '24px' }}>
              Return to the stop and try again. Your passport is still active — this node is open for resubmission.
            </Text>

            <Link
              href={passportUrl}
              style={{ display: 'inline-block', border: '1px solid #c8a96e', color: '#c8a96e', padding: '10px 24px', fontSize: '12px', letterSpacing: '0.15em', textTransform: 'uppercase', textDecoration: 'none', marginBottom: '32px' }}
            >
              Resubmit Proof →
            </Link>

            <Hr style={{ borderColor: '#2a2a2a', margin: '32px 0' }} />
            <Text style={{ color: '#555', fontSize: '12px' }}>— Kaelo</Text>
          </Container>
        </Body>
      </Tailwind>
    </Html>
  )
}

export default CheckInRejectedEmail
