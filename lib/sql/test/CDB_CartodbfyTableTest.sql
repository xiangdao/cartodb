SET client_min_messages TO warning;
\set VERBOSITY terse;

-- t1: table with single non-geometrical column
CREATE TABLE t(a int);
SELECT CDB_CartodbfyTable('t');
SELECT f_table_schema,f_table_name,f_geometry_column,coord_dimension,srid,type
  FROM geometry_columns
  ORDER BY f_table_name,f_geometry_column;
INSERT INTO t(the_geom) values ( CDB_LatLng(2,1) );
SELECT
  't1',
  cartodb_id,
  round(extract(minutes from created_at - now())) as created,
  round(extract(minutes from updated_at - now())) as updated,
  round(st_x(the_geom)) as geom_x,
  round(st_y(the_geom)) as geom_y,
  round(st_x(the_geom_webmercator)) as mercator_x,
  round(st_y(the_geom_webmercator)) as mercator_y
FROM t;


DROP TABLE t;
