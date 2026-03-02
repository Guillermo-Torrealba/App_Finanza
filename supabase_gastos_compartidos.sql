-- Tabla para gestionar gastos compartidos con amigos
-- Ejecuta esto en Supabase Dashboard → SQL Editor

CREATE TABLE public.gastos_compartidos (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id      uuid REFERENCES auth.users(id) NOT NULL DEFAULT auth.uid(),
  gasto_id     bigint NOT NULL, -- ID del gasto padre en la tabla "gastos"
  persona      text NOT NULL,
  monto        bigint NOT NULL,
  pagado       boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- Habilitar Row Level Security (RLS)
ALTER TABLE public.gastos_compartidos ENABLE ROW LEVEL SECURITY;

-- Crear política de seguridad para que los usuarios solo vean y editen sus propios datos
CREATE POLICY "Users can CRUD own shared expenses"
  ON public.gastos_compartidos
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
