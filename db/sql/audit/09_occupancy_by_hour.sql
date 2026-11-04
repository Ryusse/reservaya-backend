-- Solo lectura. Ocupación por espacio y hora del día en un rango de fechas (solo reservas confirmadas).
-- Mismo criterio que OccupancyReport: la capacidad de un espacio privado cuenta como 1 unidad;
-- en espacios compartidos cada reserva consume sus cupos. Solo se consideran horas dentro del horario del espacio.
-- Parámetros opcionales: -v from=YYYY-MM-DD -v to=YYYY-MM-DD (por defecto, últimos 30 días hasta hoy)
-- Uso: psql "$DATABASE_URL" -v from=2026-10-01 -v to=2026-10-31 -f db/sql/audit/09_occupancy_by_hour.sql
\if :{?from} \else \set from `date -v-30d +%F 2>/dev/null || date -d '-30 days' +%F` \endif
\if :{?to}   \else \set to   `date +%F` \endif

WITH dias AS (
    SELECT count(*) AS n
    FROM generate_series(:'from'::date, :'to'::date, interval '1 day') AS d
),
horas AS (
    SELECT generate_series(0, 23) AS hora
),
ventana AS (
    SELECT s.id,
           s.name,
           h.hora,
           CASE WHEN s.space_type = 0 THEN 1 ELSE s.capacity END AS unidades,
           GREATEST(0, LEAST(extract(epoch FROM s.end_time), (h.hora + 1) * 3600)
                       - GREATEST(extract(epoch FROM s.start_time), h.hora * 3600)) AS segundos_ventana
    FROM spaces s
    CROSS JOIN horas h
    WHERE s.status = 0 AND s.start_time IS NOT NULL AND s.end_time IS NOT NULL
),
uso AS (
    SELECT r.space_id,
           h.hora,
           sum(
               GREATEST(0, LEAST(extract(epoch FROM r.end_time), (h.hora + 1) * 3600)
                           - GREATEST(extract(epoch FROM r.start_time), h.hora * 3600))
               * CASE WHEN s.space_type = 0 THEN 1 ELSE r.seats_reserved END
           ) AS segundos_usados
    FROM reservations r
    JOIN spaces s ON s.id = r.space_id
    CROSS JOIN horas h
    WHERE r.status = 0
      AND r.date BETWEEN :'from'::date AND :'to'::date
    GROUP BY r.space_id, h.hora
)
SELECT v.name AS espacio,
       v.hora,
       round(
           100.0 * coalesce(u.segundos_usados, 0)
           / NULLIF(v.unidades * v.segundos_ventana * (SELECT n FROM dias), 0),
           2
       ) AS ocupacion_pct
FROM ventana v
LEFT JOIN uso u ON u.space_id = v.id AND u.hora = v.hora
WHERE v.segundos_ventana > 0
ORDER BY v.name, v.hora;
