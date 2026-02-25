-- Metas de Ahorro table
-- Run this in Supabase Dashboard → SQL Editor

CREATE TABLE public.metas_ahorro (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id      uuid REFERENCES auth.users(id) NOT NULL DEFAULT auth.uid(),
  nombre       text NOT NULL,
  emoji        text,
  monto_meta   bigint NOT NULL,
  monto_actual bigint NOT NULL DEFAULT 0,
  fecha_limite date,
  color        text DEFAULT '#009688',
  completada   boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.metas_ahorro ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can CRUD own goals"
  ON public.metas_ahorro
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
