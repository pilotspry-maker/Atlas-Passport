import type { NodeWithCheckIn } from '@/types/database'

interface Props {
  nodes: NodeWithCheckIn[]
}

export default function CorridorProgress({ nodes }: Props) {
  const approved = nodes.filter(n => n.check_in?.status === 'approved').length

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <p className="text-xs text-atlas-muted uppercase tracking-widest">Progress</p>
        <p className="text-xs text-atlas-gold font-mono">{approved}/{nodes.length} stamped</p>
      </div>

      <div className="flex items-center gap-2">
        {nodes.map((node, i) => {
          const status = node.check_in?.status ?? 'none'
          return (
            <div key={node.id} className="flex items-center gap-2 flex-1">
              <div className="relative flex-1">
                <div
                  className={`h-px transition-colors ${
                    status === 'approved' ? 'bg-atlas-gold' : 'bg-atlas-border'
                  }`}
                />
                {i === 0 && (
                  <div className="absolute left-0 top-1/2 -translate-y-1/2 -translate-x-1/2">
                    <div className="w-2 h-2 bg-atlas-border rounded-full" />
                  </div>
                )}
              </div>
              <div
                className={`w-8 h-8 flex items-center justify-center text-xs font-bold border transition-all ${
                  status === 'approved'
                    ? 'border-atlas-gold text-atlas-gold bg-atlas-gold/10'
                    : status === 'pending'
                    ? 'border-atlas-text-dim text-atlas-text-dim'
                    : status === 'rejected'
                    ? 'border-atlas-red text-atlas-red'
                    : 'border-atlas-border text-atlas-muted'
                }`}
              >
                {status === 'approved' ? '✓' : node.sequence}
              </div>
              {i < nodes.length - 1 && (
                <div className={`h-px flex-1 transition-colors ${
                  status === 'approved' ? 'bg-atlas-gold' : 'bg-atlas-border'
                }`} />
              )}
            </div>
          )
        })}
      </div>

      {/* Labels */}
      <div className="flex items-start mt-2">
        {nodes.map(node => (
          <div key={node.id} className="flex-1 text-center">
            <p className="text-xs text-atlas-muted truncate px-1">{node.name}</p>
          </div>
        ))}
      </div>
    </div>
  )
}
