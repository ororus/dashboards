-- ============================================================
-- Supabase Migration for Tradyom Trading Journal & Auth
-- Run this in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- ═══════════════════════════════════════════════════════════
-- 1. PROFILES TABLE
-- ═══════════════════════════════════════════════════════════
CREATE TABLE public.profiles (
  id          UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email       TEXT NOT NULL,
  username    TEXT NOT NULL UNIQUE,
  country     TEXT,
  date_of_birth DATE,
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- Index for fast username lookups
CREATE UNIQUE INDEX idx_profiles_username_lower ON public.profiles (LOWER(username));

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Users can read their own profile
CREATE POLICY "Users can read own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

-- Users can insert their own profile (on signup)
CREATE POLICY "Users can insert own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- ═══════════════════════════════════════════════════════════
-- 2. USERNAME AVAILABILITY CHECK (public RPC)
-- ═══════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.check_username(uname TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Returns TRUE if username is available, FALSE if taken
  RETURN NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE LOWER(username) = LOWER(uname)
  );
END;
$$;

-- ═══════════════════════════════════════════════════════════
-- 3. TRADES TABLE
-- ═══════════════════════════════════════════════════════════
CREATE TABLE public.trades (
  id               TEXT PRIMARY KEY,
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Core fields
  asset_class      TEXT NOT NULL DEFAULT 'stocks',
  instrument       TEXT,
  direction        TEXT,  -- LONG / SHORT
  date_opened      TIMESTAMPTZ,
  pnl              NUMERIC DEFAULT 0,
  notes            TEXT DEFAULT '',
  tags             TEXT[] DEFAULT '{}',
  emotion          TEXT DEFAULT '',
  rating           INTEGER DEFAULT 0,

  -- Stocks / Indices
  entry_price      NUMERIC,
  exit_price       NUMERIC,
  shares           NUMERIC,

  -- Forex
  lots             NUMERIC,
  pip_value        NUMERIC,

  -- Commodities / Futures
  contracts        NUMERIC,
  contract_size    NUMERIC,
  point_value      NUMERIC,
  tick_size        NUMERIC,
  tick_value       NUMERIC,

  -- Options
  option_type      TEXT,  -- CALL / PUT
  strike           NUMERIC,
  expiry           DATE,
  premium          NUMERIC,
  exit_premium     NUMERIC,

  -- Angel / VC
  investment_amount NUMERIC,
  equity_pct       NUMERIC,
  valuation        NUMERIC,
  exit_valuation   NUMERIC,
  deal_status      TEXT,

  -- Real Estate
  property_type    TEXT,
  purchase_price   NUMERIC,
  current_value    NUMERIC,
  generates_rent   BOOLEAN DEFAULT false,
  monthly_rent     NUMERIC,
  monthly_expenses NUMERIC,

  -- Timestamps
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);

-- Index for fast user queries
CREATE INDEX idx_trades_user_id ON public.trades (user_id);
CREATE INDEX idx_trades_user_date ON public.trades (user_id, date_opened DESC);
CREATE INDEX idx_trades_user_asset ON public.trades (user_id, asset_class);

-- Enable RLS
ALTER TABLE public.trades ENABLE ROW LEVEL SECURITY;

-- Users can only see their own trades
CREATE POLICY "Users can read own trades"
  ON public.trades FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own trades
CREATE POLICY "Users can insert own trades"
  ON public.trades FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own trades
CREATE POLICY "Users can update own trades"
  ON public.trades FOR UPDATE
  USING (auth.uid() = user_id);

-- Users can delete their own trades
CREATE POLICY "Users can delete own trades"
  ON public.trades FOR DELETE
  USING (auth.uid() = user_id);

-- Auto-update updated_at on trade changes
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trades_updated_at
  BEFORE UPDATE ON public.trades
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_updated_at();

-- ═══════════════════════════════════════════════════════════
-- 4. AUTO-CREATE PROFILE ON SIGNUP (trigger)
-- ═══════════════════════════════════════════════════════════
-- Backup: if the client-side profile insert fails,
-- this trigger creates a minimal profile from auth metadata.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, email, username)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'username', SPLIT_PART(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- ═══════════════════════════════════════════════════════════
-- ✅ DONE — Tables: profiles, trades
--          Functions: check_username, handle_updated_at, handle_new_user
--          Policies: full RLS (users see only their own data)
-- ═══════════════════════════════════════════════════════════
