-- ═══════════════════════════════════════════════
-- TRADYOM JOURNAL — SUPABASE SETUP
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor)
-- ═══════════════════════════════════════════════

-- 1. PROFILES TABLE (extends auth.users)
CREATE TABLE public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    email TEXT NOT NULL,
    country TEXT,
    date_of_birth DATE,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Username must be 3-20 chars, alphanumeric + underscores
ALTER TABLE public.profiles ADD CONSTRAINT username_format 
    CHECK (username ~ '^[a-zA-Z0-9_]{3,20}$');

-- Index for username lookups
CREATE INDEX idx_profiles_username ON public.profiles(lower(username));

-- 2. TRADES TABLE
CREATE TABLE public.trades (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    asset_class TEXT NOT NULL DEFAULT 'stocks',
    instrument TEXT NOT NULL,
    direction TEXT, -- LONG, SHORT, null for angel/realestate
    
    -- Common fields
    entry_price NUMERIC,
    exit_price NUMERIC, -- NULL = open position
    date_opened TIMESTAMPTZ NOT NULL DEFAULT now(),
    date_closed TIMESTAMPTZ,
    pnl NUMERIC DEFAULT 0,
    notes TEXT,
    tags TEXT[] DEFAULT '{}',
    emotion TEXT,
    rating INTEGER DEFAULT 0,
    
    -- Stocks
    shares NUMERIC,
    
    -- Options
    option_type TEXT, -- CALL, PUT
    strike NUMERIC,
    expiry DATE,
    premium NUMERIC,
    exit_premium NUMERIC,
    contracts NUMERIC,
    
    -- Forex
    lots NUMERIC,
    pip_value NUMERIC,
    
    -- Commodities
    contract_size NUMERIC,
    
    -- Indices
    point_value NUMERIC,
    
    -- Futures
    tick_size NUMERIC,
    tick_value NUMERIC,
    
    -- Angel / VC
    investment_amount NUMERIC,
    equity_pct NUMERIC,
    valuation NUMERIC,
    exit_valuation NUMERIC,
    deal_status TEXT, -- active, exited, written-off
    
    -- Real Estate
    property_type TEXT,
    purchase_price NUMERIC,
    current_value NUMERIC,
    generates_rent BOOLEAN DEFAULT false,
    monthly_rent NUMERIC,
    monthly_expenses NUMERIC,
    
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index for user lookups
CREATE INDEX idx_trades_user ON public.trades(user_id);
CREATE INDEX idx_trades_user_class ON public.trades(user_id, asset_class);

-- 3. ROW LEVEL SECURITY
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trades ENABLE ROW LEVEL SECURITY;

-- Profiles: users can read/update their own, anyone can check usernames
CREATE POLICY "Users can view own profile" ON public.profiles
    FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON public.profiles
    FOR INSERT WITH CHECK (auth.uid() = id);

-- Public username check (anyone can query usernames to check availability)
CREATE POLICY "Anyone can check usernames" ON public.profiles
    FOR SELECT USING (true);

-- Trades: users can only CRUD their own
CREATE POLICY "Users can view own trades" ON public.trades
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own trades" ON public.trades
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own trades" ON public.trades
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own trades" ON public.trades
    FOR DELETE USING (auth.uid() = user_id);

-- 4. AUTO-UPDATE updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trades_updated_at BEFORE UPDATE ON public.trades
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- 5. FUNCTION: Check username availability (callable from client)
CREATE OR REPLACE FUNCTION public.check_username(uname TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN NOT EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = lower(uname));
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Done! Tables created with RLS policies.
