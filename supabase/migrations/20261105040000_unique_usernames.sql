-- PipPulse: enforce usernames as unique regardless of letter case or surrounding spaces.
-- Run this migration in the Supabase SQL Editor.
-- Existing duplicate usernames are reported first; resolve them before rerunning.

DO $$
DECLARE
  duplicate_names text;
BEGIN
  SELECT string_agg(username_group, ', ')
  INTO duplicate_names
  FROM (
    SELECT lower(btrim(username)) AS username_group
    FROM public.profiles
    WHERE username IS NOT NULL AND btrim(username) <> ''
    GROUP BY lower(btrim(username))
    HAVING count(*) > 1
  ) duplicates;

  IF duplicate_names IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot enforce unique usernames yet. Duplicate usernames (case-insensitive): %', duplicate_names;
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_ci_unique
ON public.profiles (lower(btrim(username)))
WHERE username IS NOT NULL AND btrim(username) <> '';

-- Used by the sign-up screen to give an early, friendly availability message.
-- The unique index above remains the final protection against simultaneous sign-ups.
CREATE OR REPLACE FUNCTION public.is_username_available(p_username text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $function$
  SELECT
    p_username IS NOT NULL
    AND btrim(p_username) <> ''
    AND NOT EXISTS (
      SELECT 1
      FROM public.profiles
      WHERE username IS NOT NULL
        AND lower(btrim(username)) = lower(btrim(p_username))
    );
$function$;

REVOKE ALL ON FUNCTION public.is_username_available(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_username_available(text) TO anon, authenticated;
