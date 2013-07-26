-- Depends on:
--   * CDB_TransformToWebmercator.sql
--   * CDB_TableMetadata.sql
--   * CDB_Quota.sql
--   * _CDB_UserQuotaInBytes() function, installed by rails
--     (user.rebuild_quota_trigger, called by rake task
--      cartodb:db:update_test_quota_trigger)

-- Update the_geom_webmercator
CREATE OR REPLACE FUNCTION _CDB_update_the_geom_webmercator()
RETURNS trigger AS $$
BEGIN
  NEW.the_geom_webmercator := CDB_TransformToWebmercator(NEW.the_geom);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql VOLATILE;

CREATE OR REPLACE FUNCTION _CDB_update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
   NEW.updated_at := now();
   RETURN NEW;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- Ensure a table is a "cartodb" table
-- See https://github.com/CartoDB/cartodb/wiki/CartoDB-user-table
CREATE OR REPLACE FUNCTION CDB_CartodbfyTable(reloid REGCLASS)
RETURNS void 
AS $$
DECLARE
  sql TEXT;
  rec RECORD;
  rec2 RECORD;
  tabinfo RECORD;
  had_column BOOLEAN;
  i INTEGER;
  new_name TEXT;
  quota_in_bytes INT8;
BEGIN

  -- Ensure required fields exist

  -- We need a cartodb_id column
  << cartodb_id_setup >>
  LOOP --{
    had_column := FALSE;
    BEGIN
      sql := 'ALTER TABLE ' || reloid::text || ' ADD cartodb_id SERIAL NOT NULL UNIQUE';
      RAISE NOTICE 'Running %', sql;
      EXECUTE sql;
      EXIT cartodb_id_setup;
    EXCEPTION
    WHEN duplicate_column THEN
      RAISE NOTICE 'Column cartodb_id already exists';
      had_column := TRUE;
    WHEN others THEN
      RAISE EXCEPTION 'Got % (%)', SQLERRM, SQLSTATE;
    END;

    IF had_column THEN

      -- Check data type is an integer
      SELECT t.typname, t.oid, a.attnotnull FROM pg_type t, pg_attribute a
       WHERE a.atttypid = t.oid AND a.attrelid = reloid AND NOT a.attisdropped
         AND a.attname = 'cartodb_id'
      INTO STRICT rec;
      IF rec.oid NOT IN (20,21,23) THEN -- int2, int4, int8 {
        RAISE NOTICE 'Existing cartodb_id field is of invalid type % (need int2, int4 or int8), renaming', rec.typname;
      ELSE -- }{
        sql := 'ALTER TABLE ' || reloid::text || ' ALTER COLUMN cartodb_id SET NOT NULL';
        IF NOT EXISTS ( SELECT c.conname FROM pg_constraint c, pg_attribute a
                      WHERE c.conkey = ARRAY[a.attnum] AND c.conrelid = reloid
                        AND a.attrelid = reloid
                        AND NOT a.attisdropped
                        AND a.attname = 'cartodb_id'
                        AND c.contype = 'u' ) -- unique
        THEN
          sql := sql || ', ADD unique(cartodb_id)';
        END IF;
        BEGIN
          RAISE NOTICE 'Running %', sql;
          EXECUTE sql;
          EXIT cartodb_id_setup;
        EXCEPTION
        WHEN unique_violation OR not_null_violation THEN
          RAISE NOTICE '%, renaming', SQLERRM;
        WHEN others THEN
          RAISE EXCEPTION 'Got % (%)', SQLERRM, SQLSTATE;
        END;
      END IF; -- }


      -- invalid column, need rename and re-create it
      i := 0;
      << rename_column >>
      LOOP --{
        new_name := '_cartodb_id' || i;
        BEGIN
          sql := 'ALTER TABLE ' || reloid::text || ' RENAME COLUMN cartodb_id TO ' || new_name;
          RAISE NOTICE 'Running %', sql;
          EXECUTE sql;
        EXCEPTION
        WHEN duplicate_column THEN
          i := i+1;
          CONTINUE rename_column;
        WHEN others THEN
          RAISE EXCEPTION 'Got % (%)', SQLERRM, SQLSTATE;
        END;
        EXIT rename_column;
      END LOOP; --}
      CONTINUE cartodb_id_setup;

    END IF;
  END LOOP; -- }

  -- We need created_at and updated_at
  FOR rec IN SELECT * FROM ( VALUES ('created_at'), ('updated_at') ) t(cname) LOOP --{
    << column_setup >>
    LOOP --{
      had_column := FALSE;
      BEGIN
        sql := 'ALTER TABLE ' || reloid::text || ' ADD ' || rec.cname
          || ' TIMESTAMPTZ NOT NULL DEFAULT now()';
        RAISE NOTICE 'Running %', sql;
        EXECUTE sql;
        EXIT column_setup;
      EXCEPTION
      WHEN duplicate_column THEN
        RAISE NOTICE 'Column % already exists', rec.cname;
        had_column := TRUE;
      WHEN others THEN
        RAISE EXCEPTION 'Got % (%)', SQLERRM, SQLSTATE;
      END;

      IF had_column THEN

        -- Check data type is a TIMESTAMP WITH TIMEZONE
        SELECT t.typname, t.oid, a.attnotnull FROM pg_type t, pg_attribute a
         WHERE a.atttypid = t.oid AND a.attrelid = reloid AND NOT a.attisdropped
           AND a.attname = rec.cname
        INTO STRICT rec2;
        IF rec2.oid NOT IN (1184) THEN -- timestamptz {
          RAISE NOTICE 'Existing % field is of invalid type % (need timestamptz), renaming', rec.cname, rec2.typname;
        ELSE -- }{
          sql := 'ALTER TABLE ' || reloid::text || ' ALTER ' || rec.cname
            || ' SET NOT NULL, ALTER ' || rec.cname || ' SET DEFAULT now()';
          BEGIN
            RAISE NOTICE 'Running %', sql;
            EXECUTE sql;
            EXIT column_setup;
          EXCEPTION
          WHEN not_null_violation THEN
            RAISE NOTICE '%, renaming', SQLERRM;
          WHEN others THEN
            RAISE EXCEPTION 'Got % (%)', SQLERRM, SQLSTATE;
          END;
        END IF; -- }

        -- invalid column, need rename and re-create it
        i := 0;
        << rename_column >>
        LOOP --{
          new_name := '_' || rec.cname || i;
          BEGIN
            sql := 'ALTER TABLE ' || reloid::text || ' RENAME COLUMN ' || rec.cname || ' TO ' || new_name;
            RAISE NOTICE 'Running %', sql;
            EXECUTE sql;
          EXCEPTION
          WHEN duplicate_column THEN
            i := i+1;
            CONTINUE rename_column;
          WHEN others THEN
            RAISE EXCEPTION 'Got % (%)', SQLERRM, SQLSTATE;
          END;
          EXIT rename_column;
        END LOOP; --}
        CONTINUE column_setup;

      END IF;
    END LOOP; -- }

  END LOOP; -- }

  -- We need the_geom and the_geom_webmercator
  FOR rec IN SELECT * FROM ( VALUES ('the_geom',4326), ('the_geom_webmercator',3857) ) t(cname,csrid) LOOP --{
    << column_setup >>
    LOOP --{
      had_column := FALSE;
      BEGIN
        sql := 'ALTER TABLE ' || reloid::text || ' ADD ' || rec.cname
          || ' GEOMETRY(geometry,' || rec.csrid || ')';
        RAISE NOTICE 'Running %', sql;
        EXECUTE sql;
        sql := 'CREATE INDEX ON ' || reloid::text || ' USING GIST ( ' || rec.cname || ')';
        RAISE NOTICE 'Running %', sql;
        EXECUTE sql;
        EXIT column_setup;
      EXCEPTION
      WHEN duplicate_column THEN
        RAISE NOTICE 'Column % already exists', rec.cname;
        had_column := TRUE;
      WHEN others THEN
        RAISE EXCEPTION 'Got % (%)', SQLERRM, SQLSTATE;
      END;

      IF had_column THEN

        -- Check data type is a GEOMETRY
        SELECT t.typname, t.oid, a.attnotnull FROM pg_type t, pg_attribute a
         WHERE a.atttypid = t.oid AND a.attrelid = reloid AND NOT a.attisdropped
           AND a.attname = rec.cname
        INTO STRICT rec2;
        IF rec2.typname NOT IN ('geometry') THEN -- {
          RAISE NOTICE 'Existing % field is of invalid type % (need geometry), renaming', rec.cname, rec2.typname;
        ELSE -- }{
          -- add gist indices if not there already
          IF NOT EXISTS ( SELECT ir.relname
                          FROM pg_am am, pg_class ir,
                               pg_class c, pg_index i,
                               pg_attribute a
                          WHERE c.oid  = reloid AND i.indrelid = c.oid
                            AND a.attname = rec.cname
                            AND i.indexrelid = ir.oid AND i.indnatts = 1
                            AND i.indkey[0] = a.attnum AND a.attrelid = c.oid
                            AND NOT a.attisdropped AND am.oid = ir.relam
                            AND am.amname = 'gist' )
          THEN
            BEGIN
              sql := 'CREATE INDEX ON ' || reloid::text || ' USING GIST ( ' || rec.cname || ')';
              RAISE NOTICE 'Running %', sql;
              EXECUTE sql;
              EXIT column_setup;
            EXCEPTION
            WHEN others THEN
              RAISE EXCEPTION 'Got % (%)', SQLERRM, SQLSTATE;
            END;
          END IF; -- }
          EXIT column_setup;
        END IF; -- }

        -- invalid column, need rename and re-create it
        i := 0;
        << rename_column >>
        LOOP --{
          new_name := '_' || rec.cname || i;
          BEGIN
            sql := 'ALTER TABLE ' || reloid::text || ' RENAME COLUMN ' || rec.cname || ' TO ' || new_name;
            RAISE NOTICE 'Running %', sql;
            EXECUTE sql;
          EXCEPTION
          WHEN duplicate_column THEN
            i := i+1;
            CONTINUE rename_column;
          WHEN others THEN
            RAISE EXCEPTION 'Got % (%)', SQLERRM, SQLSTATE;
          END;
          EXIT rename_column;
        END LOOP; --}
        CONTINUE column_setup;

      END IF;
    END LOOP; -- }

  END LOOP; -- }

  -- Drop and re-create all triggers

  -- NOTE: drop/create has the side-effect of re-enabling disabled triggers

  -- "track_updates"
  sql := 'DROP TRIGGER IF EXISTS track_updates ON ' || reloid::text;
  EXECUTE sql;
  sql := 'CREATE trigger track_updates AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE ON '
      || reloid::text
      || ' FOR EACH STATEMENT EXECUTE PROCEDURE public.cdb_tablemetadata_trigger()';
  EXECUTE sql;

  -- "update_the_geom_webmercator"
  -- TODO: why _before_ and not after ?
  sql := 'DROP TRIGGER IF EXISTS update_the_geom_webmercator_trigger ON ' || reloid::text;
  EXECUTE sql;
  sql := 'CREATE trigger update_the_geom_webmercator_trigger BEFORE INSERT OR UPDATE ON '
      || reloid::text
      || ' FOR EACH ROW EXECUTE PROCEDURE public._CDB_update_the_geom_webmercator()';
  EXECUTE sql;

  -- "update_updated_at"
  -- TODO: why _before_ and not after ?
  sql := 'DROP TRIGGER IF EXISTS update_updated_at_trigger ON ' || reloid::text;
  EXECUTE sql;
  sql := 'CREATE trigger update_updated_at_trigger BEFORE UPDATE ON '
      || reloid::text
      || ' FOR EACH ROW EXECUTE PROCEDURE public._CDB_update_updated_at()';
  EXECUTE sql;

  -- "test_quota" and "test_quota_per_row"

  SELECT public._CDB_UserQuotaInBytes() INTO quota_in_bytes;

  sql := 'DROP TRIGGER IF EXISTS test_quota ON ' || reloid::text;
  EXECUTE sql;
  sql := 'CREATE TRIGGER test_quota BEFORE UPDATE OR INSERT ON '
      || reloid::text
      || ' EXECUTE PROCEDURE public.CDB_CheckQuota(1, '
      || quota_in_bytes || ')';
  EXECUTE sql;

  sql := 'DROP TRIGGER IF EXISTS test_quota_per_row ON ' || reloid::text;
  EXECUTE sql;
  sql := 'CREATE TRIGGER test_quota_per_row BEFORE UPDATE OR INSERT ON '
      || reloid::text
      || ' FOR EACH ROW EXECUTE PROCEDURE public.CDB_CheckQuota(0.001,'
      || quota_in_bytes || ')';
  EXECUTE sql;
 

END;
$$ LANGUAGE PLPGSQL;
