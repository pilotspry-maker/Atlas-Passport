import Link from 'next/link'
import type { NodeWithCheckIn } from '@/types/database'

interface Props {
  node: NodeWithCheckIn
  passportStatus: 'active' | 'expired' | 'complete'
  passportId: string
}

const STATUS_CONFIG = {
  approved: {
    label: 'STAMPED',
    classes: 'border-atlas-gold text-atlas-gold bg-atlas-gold/5',
    indicator: '✓',
  },
  pending: {
    label: 'PENDING REVIEW',
    classes: 'border-atlas-text-dim text-atlas-text-dim bg-atlas-card',
    indicator: '◉',
  },
  rejected: {
    label: 'REJECTED — RETRY',
    classes: 'border-atlas-red text-atlas-red bg-atlas-red/5',
    indicator: '✕',
  },
  none: {
    label: 'OPEN',
    classes: 'border-atlas-border text-atlas-muted bg-atlas-card',
    indicator: '○',
  },
}

export default function NodeCard({ node, passportStatus, passportId }: Props) {
  const checkInStatus = (node.check_in?.status ?? 'none') as keyof typeof STATUS_CONFIG
  const config = STATUS_CONFIG[checkInStatus]
  const isApproved = checkInStatus === 'approved'
  const isPending = checkInStatus === 'pending'
  const canCheckIn =
    passportStatus === 'active' &&
    (checkInStatus === 'none' || checkInStatus === 'rejected')

  return (
    <div
      className={`border p-5 transition-all ${config.classes} ${
        isApproved ? 'animate-stamp' : ''
      }`}
    >
      <div className="flex items-start justify-between gap-4">
        <div className="flex items-start gap-4 flex-1 min-w-0">
          {/* Sequence number */}
          <div className="w-8 h-8 flex-shrink-0 border border-current flex items-center justify-center text-sm font-bold font-mono">
            {node.sequence}
          </div>

          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              <h3 className="font-semibold text-atlas-text truncate">{node.name}</h3>
              <span className="text-xs uppercase tracking-wider opacity-70 flex-shrink-0">
                {config.label}
              </span>
            </div>

            {node.address && (
              <p className="text-xs text-atlas-muted mb-2 truncate">{node.address}</p>
            )}

            {node.description && (
              <p className="text-sm text-atlas-text-dim line-clamp-2">{node.description}</p>
            )}

            {node.check_in?.admin_notes && checkInStatus === 'rejected' && (
              <div className="mt-2 p-2 border border-atlas-red/30 text-xs text-atlas-text-dim">
                <span className="text-atlas-red">Kaelo: </span>
                {node.check_in.admin_notes}
              </div>
            )}
          </div>
        </div>

        <div className="flex-shrink-0 text-2xl opacity-60">
          {config.indicator}
        </div>
      </div>

      {/* Actions */}
      {canCheckIn && (
        <div className="mt-4 pt-4 border-t border-current/20">
          <Link
            href={`/nodes/${node.id}/checkin?passport=${passportId}`}
            className="inline-block px-4 py-2 text-xs uppercase tracking-widest border border-atlas-gold text-atlas-gold hover:bg-atlas-gold hover:text-atlas-black transition-colors"
          >
            Submit Proof →
          </Link>
        </div>
      )}

      {isPending && (
        <div className="mt-4 pt-4 border-t border-current/20">
          <p className="text-xs text-atlas-text-dim">
            Kaelo is reviewing your submission. You&apos;ll get an email when it&apos;s stamped.
          </p>
        </div>
      )}

      {isApproved && node.check_in?.reviewed_at && (
        <div className="mt-4 pt-4 border-t border-atlas-gold/20">
          <p className="text-xs text-atlas-gold/70 font-mono">
            Stamped {new Date(node.check_in.reviewed_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })}
          </p>
        </div>
      )}
    </div>
  )
}
