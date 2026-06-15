import {
  Body, Container, Head, Heading, Hr, Html, Preview, Text, Link, Tailwind,
} from '@react-email/components'

interface Props {
  name: string
  nodeName: string
  corridorName: string
  sequence: number
  totalNodes: number
  isLastNode: boolean
  passportUrl: string
}

export function CheckInApprovedEmail({ name, nodeName, corridorName, sequence, totalNodes, isLastNode, passportUrl }: Props) {
  return (
    <Html>
      <Head />
      <Preview>Stamp approved — {nodeName}</Preview>
      <Tailwind>
        <Body style={{ backgroundColor: '#0a0a0a', fontFamily: 'ui-sans-serif, system-ui, sans-serif', margin: 0 }}>
          <Container style={{ maxWidth: '560px', margin: '0 auto', padding: '40px 20px' }}>
            <Text style={{ color: '#c8a96e', fontSize: '11px', letterSpacing: '0.3em', textTransform: 'uppercase', marginBottom: '8px' }}>
              Atlas Passport — Stamp Approved
            </Text>

            <Heading style={{ color: '#f5f0e8', fontSize: '24px', fontWeight: 'bold', margin: '0 0 24px' }}>
              {isLastNode ? 'All stamps collected.' : `Stop ${sequence} stamped.`}
            </Heading>

            <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '16px' }}>
              {name.split(' ')[0]}, Kaelo has verified your proof at <strong style={{ color: '#f5f0e8' }}>{nodeName}</strong>.
            </Text>

            {isLastNode ? (
              <>
                <Text style={{ color: '#c8a96e', fontSize: '15px', lineHeight: 1.7, marginBottom: '24px' }}>
                  Every stop on the {corridorName} is stamped. You&apos;ve completed the corridor.
                </Text>
                <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '24px' }}>
                  Your reward is waiting. Check your passport for the details.
                </Text>
              </>
            ) : (
              <Text style={{ color: '#a09888', fontSize: '14px', lineHeight: 1.7, marginBottom: '24px' }}>
                {totalNodes - sequence} {totalNodes - sequence === 1 ? 'stop remains' : 'stops remain'} on the {corridorName}. Keep the momentum.
              </Text>
            )}

            <Link
              href={passportUrl}
              style={{ display: 'inline-block', backgroundColor: '#c8a96e', color: '#0a0a0a', padding: '12px 28px', fontWeight: 'bold', fontSize: '12px', letterSpacing: '0.15em', textTransform: 'uppercase', textDecoration: 'none', marginBottom: '32px' }}
            >
              {isLastNode ? 'Claim Your Reward →' : 'View Passport →'}
            </Link>

            <Hr style={{ borderColor: '#2a2a2a', margin: '32px 0' }} />
            <Text style={{ color: '#555', fontSize: '12px' }}>— Kaelo</Text>
          </Container>
        </Body>
      </Tailwind>
    </Html>
  )
}

export default CheckInApprovedEmail
