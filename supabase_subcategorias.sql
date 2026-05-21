-- Agrega la columna subcategoria a la tabla gastos
-- Ejecuta este comando en el SQL Editor de tu Dashboard en Supabase

ALTER TABLE gastos 
ADD COLUMN IF NOT EXISTS subcategoria TEXT;
