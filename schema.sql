CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone TEXT,
    role TEXT NOT NULL CHECK (role IN ('admin', 'driver')),
    license_number TEXT,
    license_expiry DATE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.vehicles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_number TEXT UNIQUE NOT NULL,
    vehicle_type TEXT NOT NULL CHECK (vehicle_type IN ('Truck', 'Tractor', 'Pickup', 'Dumper', 'Other')),
    insurance_expiry DATE,
    fitness_expiry DATE,
    permit_expiry DATE,
    last_service_date DATE,
    next_service_date DATE,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'maintenance', 'inactive')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.vehicle_maintenance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE CASCADE,
    service_date DATE NOT NULL,
    description TEXT NOT NULL,
    cost NUMERIC(12,2) DEFAULT 0,
    next_due_date DATE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.duty_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    duty_date DATE NOT NULL,
    driver_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    vehicle_id UUID REFERENCES public.vehicles(id) ON DELETE CASCADE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(duty_date, driver_id)
);

CREATE TABLE public.stations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    normalized_name TEXT UNIQUE NOT NULL,
    created_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.trips (
    id UUID PRIMARY KEY,
    trip_date DATE NOT NULL,
    driver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    vehicle_number TEXT NOT NULL,
    loading_station TEXT NOT NULL,
    unloading_station TEXT NOT NULL,
    via_stations TEXT DEFAULT '',
    goods_name TEXT NOT NULL,
    quantity NUMERIC(12,2) NOT NULL DEFAULT 0,
    unit TEXT NOT NULL DEFAULT 'Ton',
    loading_time TEXT,
    unloading_time TEXT,
    bilty_number TEXT,
    kilometres NUMERIC(10,2),
    diesel_litres NUMERIC(10,2),
    loading_photo_url TEXT,
    unloading_photo_url TEXT,
    bilty_photo_url TEXT,
    notes TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.hisab_entries (
    id UUID PRIMARY KEY,
    entry_date DATE NOT NULL,
    driver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    vehicle_number TEXT,
    entry_type TEXT NOT NULL CHECK (entry_type IN ('Income', 'Advance', 'Expense')),
    category TEXT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    details TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE public.attendance_logs (
    id UUID PRIMARY KEY,
    log_date DATE NOT NULL,
    driver_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('Present', 'Holiday', 'Leave')),
    reason TEXT,
    UNIQUE(log_date, driver_id)
);

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin' AND is_active = TRUE);
$$ LANGUAGE sql SECURITY DEFINER;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vehicle_maintenance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.duty_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hisab_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Profiles access" ON public.profiles FOR SELECT USING (auth.uid() = id OR public.is_admin());
CREATE POLICY "Admin manage profiles" ON public.profiles FOR ALL USING (public.is_admin());
CREATE POLICY "View vehicles" ON public.vehicles FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Admin manage vehicles" ON public.vehicles FOR ALL USING (public.is_admin());
CREATE POLICY "Admin maintenance" ON public.vehicle_maintenance FOR ALL USING (public.is_admin());
CREATE POLICY "Duty view" ON public.duty_assignments FOR SELECT USING (driver_id = auth.uid() OR public.is_admin());
CREATE POLICY "Admin duty" ON public.duty_assignments FOR ALL USING (public.is_admin());
CREATE POLICY "Read stations" ON public.stations FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Insert stations" ON public.stations FOR INSERT WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Admin update stations" ON public.stations FOR UPDATE USING (public.is_admin());
CREATE POLICY "Admin delete stations" ON public.stations FOR DELETE USING (public.is_admin());
CREATE POLICY "Driver own trips" ON public.trips FOR ALL USING (driver_id = auth.uid() OR public.is_admin());
CREATE POLICY "Driver own hisab" ON public.hisab_entries FOR ALL USING (driver_id = auth.uid() OR public.is_admin());
CREATE POLICY "Driver own attendance" ON public.attendance_logs FOR ALL USING (driver_id = auth.uid() OR public.is_admin());

INSERT INTO storage.buckets (id, name, public) VALUES ('trip-photos', 'trip-photos', false) ON CONFLICT (id) DO NOTHING;
CREATE POLICY "Upload photos" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'trip-photos' AND auth.role() = 'authenticated');
CREATE POLICY "View photos" ON storage.objects FOR SELECT USING (bucket_id = 'trip-photos' AND (auth.uid()::text = (storage.foldername(name))[1] OR public.is_admin()));
