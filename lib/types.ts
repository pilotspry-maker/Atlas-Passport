export type ApplicationStatus = 'pending' | 'approved' | 'rejected'

export interface Application {
  id: string
  email: string
  full_name: string
  bio: string
  location: string
  discipline: string
  website: string | null
  instagram: string | null
  portfolio_url: string | null
  why_atlas: string
  status: ApplicationStatus
  reviewed_at: string | null
  reviewed_by: string | null
  created_at: string
}

export interface Artist {
  id: string
  user_id: string | null
  full_name: string
  bio: string | null
  location: string | null
  website: string | null
  instagram: string | null
  portfolio_url: string | null
  avatar_url: string | null
  slug: string
  discipline: string | null
  status: ApplicationStatus
  created_at: string
  updated_at: string
}
