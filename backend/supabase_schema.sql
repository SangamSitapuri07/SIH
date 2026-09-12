-- ORCA Phase 2 Supabase PostgreSQL Schema
-- Run this script in your Supabase SQL Editor (https://app.supabase.com/project/_/sql)

-- Enable UUID extension if not enabled
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. USER PROFILES
CREATE TABLE IF NOT EXISTS public.profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL DEFAULT 'Fisherman',
    preferred_language VARCHAR(10) NOT NULL DEFAULT 'en', -- en, hi, te
    preferred_fishing_area TEXT DEFAULT 'Veraval Offshore',
    home_harbour TEXT DEFAULT 'Veraval Harbour',
    vessel_type TEXT DEFAULT 'Motorized Boat',
    vessel_registration TEXT,
    notification_preferences JSONB DEFAULT '{"wave_alerts": true, "wind_alerts": true, "cyclone_alerts": true, "pfz_updates": true}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS for profiles
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own profile"
    ON public.profiles FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own profile"
    ON public.profiles FOR DELETE
    USING (auth.uid() = user_id);

-- 2. SAVED FISHING LOCATIONS
CREATE TABLE IF NOT EXISTS public.saved_locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    category TEXT DEFAULT 'Fishing Area', -- Harbour, Fishing Area, Favorite Spot
    is_favourite BOOLEAN DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_saved_locations_user_id ON public.saved_locations(user_id);

-- RLS for saved_locations
ALTER TABLE public.saved_locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own saved locations"
    ON public.saved_locations FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can manage their own saved locations"
    ON public.saved_locations FOR ALL
    USING (auth.uid() = user_id);

-- 3. ADVISORY HISTORY ARCHIVE
CREATE TABLE IF NOT EXISTS public.advisory_history (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    advisory_id TEXT NOT NULL,
    location_name TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    verdict TEXT NOT NULL, -- GOOD, CAUTION, NO-GO
    headline TEXT NOT NULL,
    headline_hi TEXT,
    headline_te TEXT,
    major_hazards JSONB DEFAULT '[]'::jsonb,
    variables JSONB NOT NULL,
    provenance JSONB NOT NULL,
    advisory_timestamp TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_advisory_history_user_id ON public.advisory_history(user_id);
CREATE INDEX IF NOT EXISTS idx_advisory_history_timestamp ON public.advisory_history(advisory_timestamp DESC);

-- RLS for advisory_history
ALTER TABLE public.advisory_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own advisory history"
    ON public.advisory_history FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own advisory history"
    ON public.advisory_history FOR INSERT
    WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- 4. CATCH & LIVELIHOOD REPORTS
CREATE TABLE IF NOT EXISTS public.catch_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    location_name TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    species TEXT NOT NULL,
    quantity_kg DOUBLE PRECISION NOT NULL,
    catch_date DATE NOT NULL DEFAULT CURRENT_DATE,
    notes TEXT,
    synced_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_catch_reports_user_id ON public.catch_reports(user_id);
CREATE INDEX IF NOT EXISTS idx_catch_reports_date ON public.catch_reports(catch_date DESC);

-- RLS for catch_reports (STRICT OWNERSHIP POLICY)
ALTER TABLE public.catch_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view only their own catch reports"
    ON public.catch_reports FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert catch reports"
    ON public.catch_reports FOR INSERT
    WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

CREATE POLICY "Users can update only their own catch reports"
    ON public.catch_reports FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete only their own catch reports"
    ON public.catch_reports FOR DELETE
    USING (auth.uid() = user_id);

-- 5. SKIPPER FEEDBACK
CREATE TABLE IF NOT EXISTS public.feedback (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    advisory_id TEXT,
    rating INTEGER CHECK (rating >= 1 AND rating <= 5),
    actual_conditions TEXT,
    comment TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS for feedback
ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own feedback"
    ON public.feedback FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert feedback"
    ON public.feedback FOR INSERT
    WITH CHECK (auth.uid() = user_id OR user_id IS NULL);

-- 6. OFFLINE SYNC OPERATIONS QUEUE
CREATE TABLE IF NOT EXISTS public.sync_operations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    operation_type TEXT NOT NULL, -- CREATE, UPDATE, DELETE
    entity_table TEXT NOT NULL, -- saved_locations, catch_reports, profile, feedback
    entity_id TEXT NOT NULL,
    payload JSONB NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending', -- pending, syncing, synced, failed
    attempt_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    synced_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_sync_operations_user_id ON public.sync_operations(user_id);
CREATE INDEX IF NOT EXISTS idx_sync_operations_status ON public.sync_operations(status);

-- RLS for sync_operations (STRICT OWNERSHIP POLICY)
ALTER TABLE public.sync_operations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can select their own sync operations"
    ON public.sync_operations FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own sync operations"
    ON public.sync_operations FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own sync operations"
    ON public.sync_operations FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own sync operations"
    ON public.sync_operations FOR DELETE
    USING (auth.uid() = user_id);

-- Triggers to automatically update updated_at timestamps
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_profiles_updated
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

CREATE TRIGGER on_saved_locations_updated
    BEFORE UPDATE ON public.saved_locations
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();
