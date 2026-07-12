BEGIN;

DROP SCHEMA IF EXISTS dargres_driver_benchmark CASCADE;
CREATE SCHEMA dargres_driver_benchmark;

CREATE TABLE dargres_driver_benchmark.driver_rows (
  id integer PRIMARY KEY,
  account_id integer NOT NULL,
  score double precision NOT NULL,
  active boolean NOT NULL,
  label text NOT NULL,
  created_at timestamp with time zone NOT NULL
);

INSERT INTO dargres_driver_benchmark.driver_rows (
  id,
  account_id,
  score,
  active,
  label,
  created_at
)
SELECT
  value,
  ((value * 17) % 10000)::integer,
  ((value % 10000)::double precision / 100.0),
  (value % 2 = 0),
  'row-' || lpad(value::text, 6, '0'),
  timestamp with time zone '2020-01-01 00:00:00+00'
    + ((value % 31536000) * interval '1 second')
FROM generate_series(1, 100000) AS source(value);

ANALYZE dargres_driver_benchmark.driver_rows;

COMMIT;
