'use client'

import { useState, useRef } from 'react'
import Image from 'next/image'
import { useRouter } from 'next/navigation'

interface Props {
  passportId: string
  nodeId: string
}

export default function ProofUploader({ passportId, nodeId }: Props) {
  const router = useRouter()
  const fileRef = useRef<HTMLInputElement>(null)
  const [file, setFile] = useState<File | null>(null)
  const [preview, setPreview] = useState<string | null>(null)
  const [notes, setNotes] = useState('')
  const [uploading, setUploading] = useState(false)
  const [progress, setProgress] = useState(0)
  const [error, setError] = useState<string | null>(null)

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const selected = e.target.files?.[0]
    if (!selected) return

    if (!selected.type.startsWith('image/')) {
      setError('Please upload an image file.')
      return
    }

    if (selected.size > 10 * 1024 * 1024) {
      setError('File must be under 10MB.')
      return
    }

    setFile(selected)
    setError(null)
    const reader = new FileReader()
    reader.onload = () => setPreview(reader.result as string)
    reader.readAsDataURL(selected)
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!file) return

    setUploading(true)
    setError(null)
    setProgress(10)

    try {
      // 1. Get signed upload URL
      const uploadRes = await fetch('/api/upload', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          passportId,
          nodeId,
          fileType: file.type,
          fileSize: file.size,
        }),
      })

      if (!uploadRes.ok) {
        const { error: msg } = await uploadRes.json()
        throw new Error(msg ?? 'Failed to get upload URL')
      }

      const { signedUrl, storagePath } = await uploadRes.json()
      setProgress(30)

      // 2. Upload file directly to Supabase Storage
      const putRes = await fetch(signedUrl, {
        method: 'PUT',
        body: file,
        headers: { 'Content-Type': file.type },
      })

      if (!putRes.ok) throw new Error('Upload failed. Try again.')
      setProgress(70)

      // 3. Record check-in
      const checkInRes = await fetch('/api/checkins', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ passportId, nodeId, storagePath, notes }),
      })

      if (!checkInRes.ok) {
        const { error: msg } = await checkInRes.json()
        throw new Error(msg ?? 'Failed to record check-in')
      }

      setProgress(100)
      router.push('/passport?submitted=1')
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Something went wrong')
      setUploading(false)
      setProgress(0)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      {/* File picker */}
      <div>
        <label className="block text-xs text-atlas-muted uppercase tracking-widest mb-3">
          Proof Photo *
        </label>

        {preview ? (
          <div className="relative">
            <div className="relative w-full aspect-[4/3] border border-atlas-border overflow-hidden">
              <Image src={preview} alt="Proof preview" fill className="object-cover" />
            </div>
            <button
              type="button"
              onClick={() => { setPreview(null); setFile(null) }}
              className="mt-2 text-xs text-atlas-muted hover:text-atlas-text transition-colors underline"
            >
              Remove and choose another
            </button>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => fileRef.current?.click()}
            className="w-full aspect-[4/3] border border-dashed border-atlas-border flex flex-col items-center justify-center gap-3 text-atlas-muted hover:border-atlas-gold hover:text-atlas-gold transition-colors"
          >
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1" className="w-10 h-10 opacity-40">
              <path strokeLinecap="round" strokeLinejoin="round" d="M6.827 6.175A2.31 2.31 0 015.186 7.23c-.38.054-.757.112-1.134.175C2.999 7.58 2.25 8.507 2.25 9.574V18a2.25 2.25 0 002.25 2.25h15A2.25 2.25 0 0021.75 18V9.574c0-1.067-.75-1.994-1.802-2.169a47.865 47.865 0 00-1.134-.175 2.31 2.31 0 01-1.64-1.055l-.822-1.316a2.192 2.192 0 00-1.736-1.039 48.774 48.774 0 00-5.232 0 2.192 2.192 0 00-1.736 1.039l-.821 1.316z" />
              <path strokeLinecap="round" strokeLinejoin="round" d="M16.5 12.75a4.5 4.5 0 11-9 0 4.5 4.5 0 019 0zM18.75 10.5h.008v.008h-.008V10.5z" />
            </svg>
            <span className="text-sm">Tap to take photo or upload</span>
            <span className="text-xs opacity-50">JPG, PNG, WEBP — max 10MB</span>
          </button>
        )}

        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          capture="environment"
          onChange={handleFileChange}
          className="hidden"
        />
      </div>

      {/* Optional notes */}
      <div>
        <label htmlFor="notes" className="block text-xs text-atlas-muted uppercase tracking-widest mb-2">
          Note to Kaelo (optional)
        </label>
        <textarea
          id="notes"
          value={notes}
          onChange={e => setNotes(e.target.value)}
          rows={3}
          placeholder="Anything you want Kaelo to know about this stop..."
          maxLength={500}
          className="w-full px-4 py-3 bg-atlas-card border border-atlas-border text-atlas-text placeholder-atlas-muted text-sm resize-none focus:outline-none focus:border-atlas-gold transition-colors"
        />
      </div>

      {error && (
        <p className="text-sm text-atlas-red-light">{error}</p>
      )}

      {/* Progress bar */}
      {uploading && progress > 0 && progress < 100 && (
        <div>
          <div className="h-px bg-atlas-border">
            <div
              className="h-px bg-atlas-gold transition-all duration-300"
              style={{ width: `${progress}%` }}
            />
          </div>
          <p className="text-xs text-atlas-muted mt-1">
            {progress < 30 ? 'Preparing upload...' : progress < 70 ? 'Uploading photo...' : 'Recording check-in...'}
          </p>
        </div>
      )}

      <button
        type="submit"
        disabled={!file || uploading}
        className="w-full py-3 bg-atlas-gold text-atlas-black font-semibold text-sm tracking-wider uppercase hover:bg-atlas-gold-light transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {uploading ? 'Submitting...' : 'Submit Proof'}
      </button>
    </form>
  )
}
