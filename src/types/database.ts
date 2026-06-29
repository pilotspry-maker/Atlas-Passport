export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export interface Database {
  public: {
    Tables: {
      profiles: {
        Row: {
          id: string
          email: string
          full_name: string | null
          is_admin: boolean
          referral_code: string | null
          created_at: string
          updated_at: string
        }
        Insert: {
          id: string
          email: string
          full_name?: string | null
          is_admin?: boolean
          referral_code?: string | null
          created_at?: string
          updated_at?: string
        }
        Update: {
          email?: string
          full_name?: string | null
          is_admin?: boolean
          referral_code?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      corridors: {
        Row: {
          id: string
          name: string
          description: string | null
          city: string
          country: string
          cover_image: string | null
          is_active: boolean
          created_at: string
        }
        Insert: {
          id?: string
          name: string
          description?: string | null
          city: string
          country?: string
          cover_image?: string | null
          is_active?: boolean
          created_at?: string
        }
        Update: {
          name?: string
          description?: string | null
          city?: string
          country?: string
          cover_image?: string | null
          is_active?: boolean
        }
        Relationships: []
      }
      nodes: {
        Row: {
          id: string
          corridor_id: string
          name: string
          description: string | null
          address: string | null
          hint: string | null
          sequence: number
          latitude: number | null
          longitude: number | null
          is_active: boolean
          created_at: string
        }
        Insert: {
          id?: string
          corridor_id: string
          name: string
          description?: string | null
          address?: string | null
          hint?: string | null
          sequence: number
          latitude?: number | null
          longitude?: number | null
          is_active?: boolean
          created_at?: string
        }
        Update: {
          name?: string
          description?: string | null
          address?: string | null
          hint?: string | null
          sequence?: number
          latitude?: number | null
          longitude?: number | null
          is_active?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "nodes_corridor_id_fkey"
            columns: ["corridor_id"]
            isOneToOne: false
            referencedRelation: "corridors"
            referencedColumns: ["id"]
          }
        ]
      }
      passports: {
        Row: {
          id: string
          user_id: string
          corridor_id: string
          status: 'active' | 'expired' | 'complete'
          activated_at: string
          expires_at: string
          completed_at: string | null
          warning_sent_at: string | null
          reward_claimed: boolean
          created_at: string
        }
        Insert: {
          id?: string
          user_id: string
          corridor_id: string
          status?: 'active' | 'expired' | 'complete'
          activated_at?: string
          expires_at?: string
          completed_at?: string | null
          warning_sent_at?: string | null
          reward_claimed?: boolean
          created_at?: string
        }
        Update: {
          status?: 'active' | 'expired' | 'complete'
          completed_at?: string | null
          warning_sent_at?: string | null
          reward_claimed?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "passports_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "passports_corridor_id_fkey"
            columns: ["corridor_id"]
            isOneToOne: false
            referencedRelation: "corridors"
            referencedColumns: ["id"]
          }
        ]
      }
      check_ins: {
        Row: {
          id: string
          passport_id: string
          user_id: string
          node_id: string
          status: 'pending' | 'approved' | 'rejected'
          proof_url: string
          proof_storage_path: string
          notes: string | null
          admin_notes: string | null
          reviewed_by: string | null
          reviewed_at: string | null
          submitted_at: string
          created_at: string
        }
        Insert: {
          id?: string
          passport_id: string
          user_id: string
          node_id: string
          status?: 'pending' | 'approved' | 'rejected'
          proof_url: string
          proof_storage_path: string
          notes?: string | null
          submitted_at?: string
          created_at?: string
        }
        Update: {
          status?: 'pending' | 'approved' | 'rejected'
          admin_notes?: string | null
          reviewed_by?: string | null
          reviewed_at?: string | null
          proof_url?: string
          proof_storage_path?: string
          notes?: string | null
          submitted_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "check_ins_passport_id_fkey"
            columns: ["passport_id"]
            isOneToOne: false
            referencedRelation: "passports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_ins_node_id_fkey"
            columns: ["node_id"]
            isOneToOne: false
            referencedRelation: "nodes"
            referencedColumns: ["id"]
          }
        ]
      }
      rewards: {
        Row: {
          id: string
          corridor_id: string
          title: string
          description: string | null
          redemption_code: string | null
          redemption_url: string | null
          image_url: string | null
          created_at: string
        }
        Insert: {
          id?: string
          corridor_id: string
          title: string
          description?: string | null
          redemption_code?: string | null
          redemption_url?: string | null
          image_url?: string | null
          created_at?: string
        }
        Update: {
          title?: string
          description?: string | null
          redemption_code?: string | null
          redemption_url?: string | null
          image_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "rewards_corridor_id_fkey"
            columns: ["corridor_id"]
            isOneToOne: false
            referencedRelation: "corridors"
            referencedColumns: ["id"]
          }
        ]
      }
    }
    Views: {
      check_ins_player_view: {
        Row: {
          id: string
          passport_id: string
          user_id: string
          node_id: string
          status: 'pending' | 'approved' | 'rejected'
          proof_url: string
          proof_storage_path: string
          notes: string | null
          admin_notes: string | null
          // reviewed_by intentionally excluded — admin-only column hidden by view
          reviewed_at: string | null
          submitted_at: string
          created_at: string
        }
        Insert: never  // views are read-only
        Update: never  // views are read-only
        Relationships: [
          {
            foreignKeyName: "check_ins_passport_id_fkey"
            columns: ["passport_id"]
            isOneToOne: false
            referencedRelation: "passports"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "check_ins_node_id_fkey"
            columns: ["node_id"]
            isOneToOne: false
            referencedRelation: "nodes"
            referencedColumns: ["id"]
          }
        ]
      }
    }
    Functions: Record<never, never>
    Enums: Record<never, never>
    CompositeTypes: Record<never, never>
  }
}

// Convenience row types
export type Profile  = Database['public']['Tables']['profiles']['Row']
export type Corridor = Database['public']['Tables']['corridors']['Row']
export type Node     = Database['public']['Tables']['nodes']['Row']
export type Passport = Database['public']['Tables']['passports']['Row']
export type CheckIn  = Database['public']['Tables']['check_ins']['Row']
export type Reward   = Database['public']['Tables']['rewards']['Row']

// Extended/joined types
export type NodeWithCheckIn = Node & { check_in: CheckIn | null }

export type PassportFull = Passport & {
  corridor: Corridor
  nodes: NodeWithCheckIn[]
  reward: Reward | null
}

export type CheckInFull = CheckIn & {
  node: Node & { corridor: Corridor }
  profile: Profile
  passport: Passport
}
