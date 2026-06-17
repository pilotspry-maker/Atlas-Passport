-- Add referral_code to profiles
-- This is an optional field set at signup and stored from user_metadata.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS referral_code TEXT;
