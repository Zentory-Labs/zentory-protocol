-- Add country column to profiles
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS country_code TEXT DEFAULT 'XX';

-- Create index for geo lookups
CREATE INDEX IF NOT EXISTS idx_profiles_country ON public.profiles(country_code);

-- RLS policy: users can only see their own country
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own country"
  ON public.profiles FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "System can update country"
  ON public.profiles FOR UPDATE
  USING (true)
  WITH CHECK (auth.uid() = user_id);
