-- Ejecuta este script en el SQL Editor de Supabase

-- 1. Crear tabla para almacenar los tokens de webhook
CREATE TABLE IF NOT EXISTS public.webhook_tokens (
    user_id UUID REFERENCES auth.users(id) PRIMARY KEY,
    token TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Habilitar RLS en la tabla webhook_tokens
ALTER TABLE public.webhook_tokens ENABLE ROW LEVEL SECURITY;

-- Políticas para webhook_tokens
CREATE POLICY "Users can view own webhook token" ON public.webhook_tokens
    FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own webhook token" ON public.webhook_tokens
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own webhook token" ON public.webhook_tokens
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own webhook token" ON public.webhook_tokens
    FOR DELETE USING (auth.uid() = user_id);

-- 2. Crear Función RPC (Security Definer) para que el Atajo asigne el Gasto
-- Esta función se salta RLS al ejecutarse con los privilegios del creador (owner), 
-- por lo que es segura al validar el p_token.
CREATE OR REPLACE FUNCTION public.registrar_gasto_webhook(
    p_token TEXT,
    p_monto BIGINT,
    p_comercio TEXT,
    p_tipo TEXT DEFAULT 'Gasto'
) RETURNS JSON AS $$
DECLARE
    v_user_id UUID;
    v_gasto_id BIGINT;
BEGIN
    -- Verificar si existe el token y obtener el UUID
    SELECT user_id INTO v_user_id
    FROM public.webhook_tokens
    WHERE token = p_token;

    -- Si no existe, lanzar excepción
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Token de webhook inválido';
    END IF;

    -- Insertar el gasto
    INSERT INTO public.gastos (
        user_id,
        fecha,
        item,
        monto,
        categoria,
        cuenta,
        tipo
    ) VALUES (
        v_user_id,
        CURRENT_DATE,
        p_comercio,
        p_monto,
        'A revisar', -- Categoría clave para filtrar luego
        'Cta Corriente', -- O una cuenta predeterminada
        p_tipo
    ) RETURNING id INTO v_gasto_id;

    -- Devolver un JSON indicando éxito
    RETURN json_build_object('status', 'success', 'gasto_id', v_gasto_id, 'message', p_tipo || ' guardado correctamente');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
