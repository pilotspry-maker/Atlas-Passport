'use client'

import { useState, useEffect, useCallback } from 'react'
import { useParams, useRouter } from 'next/navigation'
import Link from 'next/link'
import AdminNav from '@/components/admin/AdminNav'
import type { Node } from '@/types/database'

interface CorridorData {
  id: string
  name: string
  description: string | null
  city: string
  country: string
  is_active: boolean
}

const INPUT = 'w-full px-3 py-2 bg-atlas-dark border border-atlas-border text-atlas-text placeholder-atlas-muted text-sm focus:outline-none focus:border-atlas-gold transition-colors'
const BLANK_NODE = { name: '', description: '', address: '', hint: '', latitude: '', longitude: '' }

export default function EditCorridorPage() {
  const { corridorId } = useParams<{ corridorId: string }>()
  const router = useRouter()

  const [corridor, setCorridor] = useState<CorridorData | null>(null)
  const [nodes, setNodes] = useState<Node[]>([])
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  // Node form
  const [addingNode, setAddingNode] = useState(false)
  const [newNode, setNewNode] = useState(BLANK_NODE)
  const [nodeError, setNodeError] = useState<string | null>(null)

  // Inline node editing
  const [editingNodeId, setEditingNodeId] = useState<string | null>(null)
  const [editingNode, setEditingNode] = useState<Partial<typeof BLANK_NODE>>({})

  const load = useCallback(async () => {
    const [cRes, nRes] = await Promise.all([
      fetch(`/api/admin/corridors/${corridorId}`),
      fetch(`/api/admin/nodes?corridor_id=${corridorId}`),
    ])
    const [cData, nData] = await Promise.all([cRes.json(), nRes.json()])
    setCorridor(cData.corridor)
    setNodes(nData.nodes ?? [])
    setLoading(false)
  }, [corridorId])

  // eslint-disable-next-line react-hooks/set-state-in-effect -- setState calls are inside an async useCallback, not synchronous within the effect body
  useEffect(() => { load() }, [load])

  async function saveCorridor(e: React.FormEvent) {
    e.preventDefault()
    if (!corridor) return
    setSaving(true)
    setError(null)

    const res = await fetch(`/api/admin/corridors/${corridorId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(corridor),
    })
    const data = await res.json()
    setSaving(false)
    if (!res.ok) setError(data.error ?? 'Save failed')
    else setCorridor(data.corridor)
  }

  async function addNode(e: React.FormEvent) {
    e.preventDefault()
    if (!newNode.name.trim()) return
    setNodeError(null)

    const res = await fetch('/api/admin/nodes', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ corridor_id: corridorId, ...newNode }),
    })
    const data = await res.json()
    if (!res.ok) { setNodeError(data.error ?? 'Failed'); return }
    setNodes(prev => [...prev, data.node])
    setNewNode(BLANK_NODE)
    setAddingNode(false)
  }

  async function saveNode(nodeId: string) {
    const res = await fetch(`/api/admin/nodes/${nodeId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(editingNode),
    })
    const data = await res.json()
    if (!res.ok) { setNodeError(data.error ?? 'Save failed'); return }
    setNodes(prev => prev.map(n => n.id === nodeId ? data.node : n))
    setEditingNodeId(null)
    setEditingNode({})
  }

  async function deleteNode(nodeId: string) {
    if (!confirm('Delete this stop? This cannot be undone.')) return
    const res = await fetch(`/api/admin/nodes/${nodeId}`, { method: 'DELETE' })
    if (res.ok) setNodes(prev => prev.filter(n => n.id !== nodeId))
  }

  async function toggleNodeActive(node: Node) {
    const res = await fetch(`/api/admin/nodes/${node.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ is_active: !node.is_active }),
    })
    const data = await res.json()
    if (res.ok) setNodes(prev => prev.map(n => n.id === node.id ? data.node : n))
  }

  if (loading) return <div className="py-12 text-atlas-muted text-sm">Loading...</div>
  if (!corridor) return <div className="py-12 text-atlas-muted text-sm">Corridor not found.</div>

  return (
    <div>
      <AdminNav active="corridors" />

      <div className="flex items-center justify-between mb-6">
        <div>
          <Link href="/admin/corridors" className="text-xs text-atlas-muted hover:text-atlas-text uppercase tracking-widest transition-colors">
            ← Corridors
          </Link>
          <h1 className="text-xl font-bold text-atlas-text mt-2">{corridor.name}</h1>
        </div>
      </div>

      <div className="grid md:grid-cols-2 gap-8">
        {/* ── Corridor details ── */}
        <div>
          <h2 className="text-xs uppercase tracking-widest text-atlas-muted mb-4">Corridor Details</h2>
          <form onSubmit={saveCorridor} className="space-y-4">
            <Field label="Name *">
              <input type="text" value={corridor.name} onChange={e => setCorridor(p => p && ({ ...p, name: e.target.value }))} required className={INPUT} />
            </Field>
            <Field label="Description">
              <textarea value={corridor.description ?? ''} onChange={e => setCorridor(p => p && ({ ...p, description: e.target.value }))} rows={3} className={`${INPUT} resize-none`} />
            </Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="City *">
                <input type="text" value={corridor.city} onChange={e => setCorridor(p => p && ({ ...p, city: e.target.value }))} required className={INPUT} />
              </Field>
              <Field label="Country">
                <input type="text" value={corridor.country} onChange={e => setCorridor(p => p && ({ ...p, country: e.target.value }))} className={INPUT} />
              </Field>
            </div>
            <label className="flex items-center gap-3 cursor-pointer">
              <div
                onClick={() => setCorridor(p => p && ({ ...p, is_active: !p.is_active }))}
                className={`w-9 h-5 rounded-full transition-colors relative ${corridor.is_active ? 'bg-atlas-green' : 'bg-atlas-border'}`}
              >
                <div className={`absolute top-0.5 w-4 h-4 rounded-full bg-white transition-transform ${corridor.is_active ? 'translate-x-4' : 'translate-x-0.5'}`} />
              </div>
              <span className="text-sm text-atlas-text-dim">Active</span>
            </label>
            {error && <p className="text-sm text-atlas-red-light">{error}</p>}
            <button type="submit" disabled={saving} className="w-full py-2.5 bg-atlas-gold text-atlas-black text-sm font-semibold uppercase tracking-wider hover:bg-atlas-gold-light transition-colors disabled:opacity-50">
              {saving ? 'Saving...' : 'Save Changes'}
            </button>
          </form>
        </div>

        {/* ── Nodes ── */}
        <div>
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-xs uppercase tracking-widest text-atlas-muted">
              Stops ({nodes.length})
            </h2>
            {!addingNode && (
              <button
                onClick={() => setAddingNode(true)}
                className="text-xs text-atlas-gold hover:text-atlas-gold-light uppercase tracking-widest transition-colors"
              >
                + Add Stop
              </button>
            )}
          </div>

          <div className="space-y-2 mb-4">
            {nodes.map(node => (
              <div key={node.id} className={`border ${node.is_active ? 'border-atlas-border' : 'border-atlas-border/30 opacity-50'} bg-atlas-card`}>
                {editingNodeId === node.id ? (
                  <div className="p-4 space-y-3">
                    <Field label="Name *">
                      <input type="text" value={editingNode.name ?? node.name} onChange={e => setEditingNode(p => ({ ...p, name: e.target.value }))} className={INPUT} />
                    </Field>
                    <Field label="Address">
                      <input type="text" value={editingNode.address ?? node.address ?? ''} onChange={e => setEditingNode(p => ({ ...p, address: e.target.value }))} className={INPUT} />
                    </Field>
                    <Field label="Description">
                      <textarea value={editingNode.description ?? node.description ?? ''} onChange={e => setEditingNode(p => ({ ...p, description: e.target.value }))} rows={2} className={`${INPUT} resize-none`} />
                    </Field>
                    <Field label="Kaelo's Hint">
                      <textarea value={editingNode.hint ?? node.hint ?? ''} onChange={e => setEditingNode(p => ({ ...p, hint: e.target.value }))} rows={2} placeholder="What Kaelo tells the traveller before they arrive..." className={`${INPUT} resize-none`} />
                    </Field>
                    {nodeError && <p className="text-xs text-atlas-red-light">{nodeError}</p>}
                    <div className="flex gap-2">
                      <button onClick={() => saveNode(node.id)} className="flex-1 py-2 bg-atlas-gold text-atlas-black text-xs font-semibold uppercase tracking-wider hover:bg-atlas-gold-light transition-colors">Save</button>
                      <button onClick={() => { setEditingNodeId(null); setEditingNode({}) }} className="flex-1 py-2 border border-atlas-border text-atlas-muted text-xs uppercase tracking-wider hover:text-atlas-text transition-colors">Cancel</button>
                    </div>
                  </div>
                ) : (
                  <div className="flex items-center gap-3 p-3">
                    <div className="w-6 h-6 flex-shrink-0 border border-atlas-border flex items-center justify-center text-xs font-mono text-atlas-muted">
                      {node.sequence}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-atlas-text truncate">{node.name}</p>
                      {node.address && <p className="text-xs text-atlas-muted truncate">{node.address}</p>}
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      <button onClick={() => toggleNodeActive(node)} className="text-xs text-atlas-muted hover:text-atlas-text transition-colors" title={node.is_active ? 'Deactivate' : 'Activate'}>
                        {node.is_active ? '●' : '○'}
                      </button>
                      <button onClick={() => { setEditingNodeId(node.id); setEditingNode({}) }} className="text-xs text-atlas-gold hover:text-atlas-gold-light transition-colors">Edit</button>
                      <button onClick={() => deleteNode(node.id)} className="text-xs text-atlas-red hover:text-atlas-red-light transition-colors">Del</button>
                    </div>
                  </div>
                )}
              </div>
            ))}

            {nodes.length === 0 && !addingNode && (
              <div className="border border-dashed border-atlas-border p-6 text-center text-atlas-muted text-xs">
                No stops yet. Add the first one.
              </div>
            )}
          </div>

          {/* Add node form */}
          {addingNode && (
            <form onSubmit={addNode} className="border border-atlas-gold/30 bg-atlas-gold/5 p-4 space-y-3">
              <p className="text-xs text-atlas-gold uppercase tracking-widest mb-2">New Stop</p>
              <Field label="Name *">
                <input type="text" value={newNode.name} onChange={e => setNewNode(p => ({ ...p, name: e.target.value }))} placeholder="The Archive" required autoFocus className={INPUT} />
              </Field>
              <Field label="Address">
                <input type="text" value={newNode.address} onChange={e => setNewNode(p => ({ ...p, address: e.target.value }))} placeholder="123 Example St" className={INPUT} />
              </Field>
              <Field label="Description">
                <textarea value={newNode.description} onChange={e => setNewNode(p => ({ ...p, description: e.target.value }))} rows={2} className={`${INPUT} resize-none`} />
              </Field>
              <Field label="Kaelo's Hint">
                <textarea value={newNode.hint} onChange={e => setNewNode(p => ({ ...p, hint: e.target.value }))} rows={2} placeholder="What Kaelo whispers to the traveller..." className={`${INPUT} resize-none`} />
              </Field>
              {nodeError && <p className="text-xs text-atlas-red-light">{nodeError}</p>}
              <div className="flex gap-2">
                <button type="submit" className="flex-1 py-2 bg-atlas-gold text-atlas-black text-xs font-semibold uppercase tracking-wider hover:bg-atlas-gold-light transition-colors">Add Stop</button>
                <button type="button" onClick={() => { setAddingNode(false); setNewNode(BLANK_NODE); setNodeError(null) }} className="flex-1 py-2 border border-atlas-border text-atlas-muted text-xs uppercase tracking-wider hover:text-atlas-text transition-colors">Cancel</button>
              </div>
            </form>
          )}
        </div>
      </div>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <label className="block text-xs text-atlas-muted uppercase tracking-widest mb-1.5">{label}</label>
      {children}
    </div>
  )
}
