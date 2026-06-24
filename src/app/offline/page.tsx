// Offline fallback page — shown when navigator is offline and page isn't cached
export default function OfflinePage() {
  return (
    <div className="min-h-screen bg-atlas-black flex flex-col items-center justify-center px-6 text-center">
      <div className="w-16 h-16 rounded-full border border-atlas-gold/30 flex items-center justify-center mb-8">
        <svg
          className="w-8 h-8 text-atlas-gold/50"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={1.5}
            d="M3.75 3.75l16.5 16.5M12 3C7.03 3 3 7.03 3 12s4.03 9 9 9 9-4.03 9-9"
          />
        </svg>
      </div>
      <h1 className="text-2xl font-semibold text-atlas-text mb-3">
        No connection
      </h1>
      <p className="text-atlas-text/50 text-sm max-w-xs leading-relaxed mb-8">
        The corridor is still waiting. Connect to a network and your passport
        will be right where you left it.
      </p>
      <button
        onClick={() => window.location.reload()}
        className="text-sm text-atlas-gold border border-atlas-gold/30 px-6 py-3 rounded-full hover:border-atlas-gold/60 transition-colors"
      >
        Try again
      </button>
    </div>
  )
}
