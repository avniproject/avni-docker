--
-- PostgreSQL database dump
--

-- Dumped from database version 10.14 (Ubuntu 10.14-0ubuntu0.18.04.1)
-- Dumped by pg_dump version 12.3 (Ubuntu 12.3-1.pgdg18.04+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: test; Type: SCHEMA; Schema: -; Owner: test
--

CREATE SCHEMA test;

--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: ltree; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS ltree WITH SCHEMA public;


--
-- Name: EXTENSION ltree; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION ltree IS 'data type for hierarchical tree-like structures';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner:
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: concept_name(text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.concept_name(text) RETURNS text
    LANGUAGE sql STABLE STRICT
    AS $_$
SELECT name
FROM concept
WHERE uuid = $1;
$_$;


ALTER FUNCTION public.concept_name(text) OWNER TO openchs;

--
-- Name: create_audit(); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.create_audit() RETURNS integer
    LANGUAGE sql
    AS $$select create_audit(1)$$;


ALTER FUNCTION public.create_audit() OWNER TO openchs;

--
-- Name: create_audit(numeric); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.create_audit(user_id numeric) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE result INTEGER;
BEGIN
  INSERT INTO audit(created_by_id, last_modified_by_id, created_date_time, last_modified_date_time)
  VALUES(user_id, user_id, now(), now()) RETURNING id into result;
  RETURN result;
END $$;


ALTER FUNCTION public.create_audit(user_id numeric) OWNER TO openchs;

--
-- Name: create_db_user(text, text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.create_db_user(inrolname text, inpassword text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
  BEGIN
    IF NOT EXISTS(SELECT rolname FROM pg_roles WHERE rolname = inrolname)
    THEN
      EXECUTE 'CREATE ROLE ' || quote_ident(inrolname) || ' NOINHERIT LOGIN PASSWORD ' || quote_literal(inpassword);
    END IF;
    EXECUTE 'GRANT ' || quote_ident(inrolname) || ' TO openchs';
    PERFORM public.grant_all_on_all(inrolname);
    RETURN 1;
  END
$$;


ALTER FUNCTION public.create_db_user(inrolname text, inpassword text) OWNER TO openchs;

--
-- Name: create_implementation_schema(text, text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.create_implementation_schema(schema_name text, db_user text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
BEGIN
  EXECUTE 'CREATE SCHEMA IF NOT EXISTS "' || schema_name || '" AUTHORIZATION "' || db_user || '"';
  EXECUTE 'GRANT ALL PRIVILEGES ON SCHEMA "' || schema_name || '" TO "' || db_user || '"';
  RETURN 1;
END
$$;


ALTER FUNCTION public.create_implementation_schema(schema_name text, db_user text) OWNER TO openchs;

--
-- Name: create_view(text, text, text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.create_view(schema_name text, view_name text, sql_query text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
BEGIN
--     EXECUTE 'set search_path = ' || ;
    EXECUTE 'DROP VIEW IF EXISTS ' || schema_name || '.' || view_name;
    EXECUTE 'CREATE OR REPLACE VIEW ' || schema_name || '.' || view_name || ' AS ' || sql_query;
    RETURN 1;
END
$$;


ALTER FUNCTION public.create_view(schema_name text, view_name text, sql_query text) OWNER TO openchs;

--
-- Name: deps_restore_dependencies(character varying, character varying); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.deps_restore_dependencies(p_view_schema character varying, p_view_name character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
    v_curr record;
begin
    for v_curr in
        (
            select deps_ddl_to_run
            from deps_saved_ddl
            where deps_view_schema = p_view_schema
              and deps_view_name = p_view_name
            order by deps_id desc
        )
        loop
            execute v_curr.deps_ddl_to_run;
        end loop;
    delete
    from deps_saved_ddl
    where deps_view_schema = p_view_schema
      and deps_view_name = p_view_name;
end;
$$;


ALTER FUNCTION public.deps_restore_dependencies(p_view_schema character varying, p_view_name character varying) OWNER TO openchs;

--
-- Name: deps_save_and_drop_dependencies(character varying, character varying); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.deps_save_and_drop_dependencies(p_view_schema character varying, p_view_name character varying) RETURNS void
    LANGUAGE plpgsql
    AS $$
declare
    v_curr record;
begin
    for v_curr in
        (
            select obj_schema, obj_name, obj_type
            from (
                     with recursive recursive_deps(obj_schema, obj_name, obj_type, depth) as
                                        (
                                            select p_view_schema, p_view_name, null::varchar, 0
                                            union
                                            select dep_schema::varchar,
                                                   dep_name::varchar,
                                                   dep_type::varchar,
                                                   recursive_deps.depth + 1
                                            from (
                                                     select ref_nsp.nspname ref_schema,
                                                            ref_cl.relname  ref_name,
                                                            rwr_cl.relkind  dep_type,
                                                            rwr_nsp.nspname dep_schema,
                                                            rwr_cl.relname  dep_name
                                                     from pg_depend dep
                                                              join pg_class ref_cl on dep.refobjid = ref_cl.oid
                                                              join pg_namespace ref_nsp on ref_cl.relnamespace = ref_nsp.oid
                                                              join pg_rewrite rwr on dep.objid = rwr.oid
                                                              join pg_class rwr_cl on rwr.ev_class = rwr_cl.oid
                                                              join pg_namespace rwr_nsp on rwr_cl.relnamespace = rwr_nsp.oid
                                                     where dep.deptype = 'n'
                                                       and dep.classid = 'pg_rewrite'::regclass
                                                 ) deps
                                                     join recursive_deps
                                                          on deps.ref_schema = recursive_deps.obj_schema and
                                                             deps.ref_name = recursive_deps.obj_name
                                            where (deps.ref_schema != deps.dep_schema or deps.ref_name != deps.dep_name)
                                        )
                     select obj_schema, obj_name, obj_type, depth
                     from recursive_deps
                     where depth > 0
                 ) t
            group by obj_schema, obj_name, obj_type
            order by max(depth) desc
        )
        loop

            insert into deps_saved_ddl(deps_view_schema, deps_view_name, deps_ddl_to_run)
            select p_view_schema,
                   p_view_name,
                   'COMMENT ON ' ||
                   case
                       when c.relkind = 'v' then 'VIEW'
                       when c.relkind = 'm' then 'MATERIALIZED VIEW'
                       else ''
                       end
                       || ' ' || n.nspname || '.' || c.relname || ' IS ''' || replace(d.description, '''', '''''') ||
                   ''';'
            from pg_class c
                     join pg_namespace n on n.oid = c.relnamespace
                     join pg_description d on d.objoid = c.oid and d.objsubid = 0
            where n.nspname = v_curr.obj_schema
              and c.relname = v_curr.obj_name
              and d.description is not null;

            insert into deps_saved_ddl(deps_view_schema, deps_view_name, deps_ddl_to_run)
            select p_view_schema,
                   p_view_name,
                   'COMMENT ON COLUMN ' || n.nspname || '.' || c.relname || '.' || a.attname || ' IS ''' ||
                   replace(d.description, '''', '''''') || ''';'
            from pg_class c
                     join pg_attribute a on c.oid = a.attrelid
                     join pg_namespace n on n.oid = c.relnamespace
                     join pg_description d on d.objoid = c.oid and d.objsubid = a.attnum
            where n.nspname = v_curr.obj_schema
              and c.relname = v_curr.obj_name
              and d.description is not null;

            insert into deps_saved_ddl(deps_view_schema, deps_view_name, deps_ddl_to_run)
            select p_view_schema,
                   p_view_name,
                   'GRANT ' || privilege_type || ' ON ' || table_schema || '.' || table_name || ' TO ' || '"' ||
                   grantee || '"'
            from information_schema.role_table_grants
            where table_schema = v_curr.obj_schema
              and table_name = v_curr.obj_name;

            if v_curr.obj_type = 'v' then
                insert into deps_saved_ddl(deps_view_schema, deps_view_name, deps_ddl_to_run)
                select p_view_schema,
                       p_view_name,
                       'CREATE VIEW ' || v_curr.obj_schema || '.' || v_curr.obj_name || ' AS ' || view_definition
                from information_schema.views
                where table_schema = v_curr.obj_schema
                  and table_name = v_curr.obj_name;
            elsif v_curr.obj_type = 'm' then
                insert into deps_saved_ddl(deps_view_schema, deps_view_name, deps_ddl_to_run)
                select p_view_schema,
                       p_view_name,
                       'CREATE MATERIALIZED VIEW ' || v_curr.obj_schema || '.' || v_curr.obj_name || ' AS ' ||
                       definition
                from pg_matviews
                where schemaname = v_curr.obj_schema
                  and matviewname = v_curr.obj_name;
            end if;

            execute 'DROP ' ||
                    case
                        when v_curr.obj_type = 'v' then 'VIEW'
                        when v_curr.obj_type = 'm' then 'MATERIALIZED VIEW'
                        end
                        || ' ' || v_curr.obj_schema || '.' || v_curr.obj_name;

        end loop;
end;
$$;


ALTER FUNCTION public.deps_save_and_drop_dependencies(p_view_schema character varying, p_view_name character varying) OWNER TO openchs;

--
-- Name: drop_view(text, text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.drop_view(schema_name text, view_name text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE 'set search_path = ' || schema_name;
    EXECUTE 'DROP VIEW IF EXISTS ' || view_name;
    EXECUTE 'reset search_path';
    RETURN 1;
END
$$;


ALTER FUNCTION public.drop_view(schema_name text, view_name text) OWNER TO openchs;

--
-- Name: enable_rls_on_ref_table(text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.enable_rls_on_ref_table(tablename text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    tabl   TEXT := quote_ident(tablename);
    polisy TEXT := quote_ident(tablename || '_orgs') || ' ON ' || tabl || ' ';
BEGIN
    EXECUTE 'DROP POLICY IF EXISTS ' || polisy;
    EXECUTE 'CREATE POLICY ' || polisy || '
            USING (organisation_id IN (SELECT id FROM org_ids UNION SELECT organisation_id from organisation_group_organisation)
            OR organisation_id IN (SELECT organisation_id from organisation_group_organisation))
  WITH CHECK ((organisation_id = (select id
                                  from organisation
                                  where db_user = current_user)))';
    EXECUTE 'ALTER TABLE ' || tabl || ' ENABLE ROW LEVEL SECURITY';
    RETURN 'CREATED POLICY ' || polisy;
END
$$;


ALTER FUNCTION public.enable_rls_on_ref_table(tablename text) OWNER TO openchs;

--
-- Name: enable_rls_on_tx_table(text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.enable_rls_on_tx_table(tablename text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    tabl   TEXT := quote_ident(tablename);
    polisy TEXT := quote_ident(tablename || '_orgs') || ' ON ' || tabl || ' ';
BEGIN
    EXECUTE 'DROP POLICY IF EXISTS ' || polisy;
    EXECUTE 'CREATE POLICY ' || polisy || '
            USING ((organisation_id = (select id from organisation where db_user = current_user)
            OR organisation_id IN (SELECT organisation_id from organisation_group_organisation)))
    WITH CHECK ((organisation_id = (select id from organisation where db_user = current_user)))';
    EXECUTE 'ALTER TABLE ' || tabl || ' ENABLE ROW LEVEL SECURITY';
    RETURN 'CREATED POLICY ' || polisy;
END
$$;


ALTER FUNCTION public.enable_rls_on_tx_table(tablename text) OWNER TO openchs;

--
-- Name: frequency_and_percentage(text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.frequency_and_percentage(frequency_query text) RETURNS TABLE(total bigint, percentage double precision, gender character varying, address_type character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE separator TEXT;
BEGIN
  SELECT md5(random() :: TEXT) :: TEXT
      INTO separator;
  EXECUTE format('CREATE TEMPORARY TABLE query_output_%s (
    uuid         VARCHAR,
    gender_name  VARCHAR,
    address_type VARCHAR,
    address_name VARCHAR
  ) ON COMMIT DROP', separator);

  EXECUTE format('CREATE TEMPORARY TABLE aggregates_%s (
    total        BIGINT,
    percentage   FLOAT,
    gender       VARCHAR,
    address_type VARCHAR
  ) ON COMMIT DROP', separator);

  -- Store filtered query into a temporary variable


  EXECUTE FORMAT('INSERT INTO query_output_%s (uuid, gender_name, address_type, address_name) %s', separator,
                 frequency_query);

  EXECUTE format('INSERT INTO aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid)  total,
      qo.gender_name  gender,
      qo.address_type address_type
    FROM query_output_%s qo
    GROUP BY qo.gender_name, qo.address_type', separator, separator);


  EXECUTE format('INSERT INTO aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid)  total,
      ''Total''         gender,
      qo.address_type address_type
    FROM query_output_%s qo
    GROUP BY qo.address_type', separator, separator);

  EXECUTE format('INSERT INTO aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid)  total,
      qo.gender_name  gender,
      ''All'' address_type
    FROM query_output_%s qo
    GROUP BY qo.gender_name', separator, separator);

  EXECUTE format('INSERT INTO aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid) total,
      ''Total''        gender,
      ''All''          address_type
    FROM query_output_%s qo', separator, separator);

  EXECUTE format('UPDATE aggregates_%s ag1
  SET percentage = coalesce(round(((ag1.total / (SELECT sum(ag2.total)
                                                 FROM aggregates_%s ag2
                                                 WHERE (ag2.address_type = ag1.address_type AND ag2.gender != ''Total'')))
                                   * 100), 2), 100)', separator, separator);

  EXECUTE FORMAT('INSERT INTO aggregates_%s (total, percentage, address_type, gender)
                        SELECT 0, 0, atname, gname from (
                            SELECT DISTINCT type atname,
                            name gname
                          FROM address_level_type_view, gender
                          WHERE name != ''Other''
                          UNION ALL
                          SELECT
                            ''All'' atname,
                            name gname
                          FROM gender
                          WHERE name != ''Other''
                          UNION ALL
                          SELECT DISTINCT
                            type atname,
                            ''Total'' gname
                          FROM address_level_type_view
                          UNION ALL
                          SELECT
                            ''All'' atname,
                            ''Total'' gname) as agt where (atname, gname) not in (select address_type, gender from aggregates_%s)',
                 separator, separator);

  RETURN QUERY EXECUTE format('SELECT *
               FROM aggregates_%s order by address_type, gender', separator);
END
$$;


ALTER FUNCTION public.frequency_and_percentage(frequency_query text) OWNER TO openchs;

--
-- Name: frequency_and_percentage(text, text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.frequency_and_percentage(frequency_query text, denominator_query text) RETURNS TABLE(total bigint, percentage double precision, gender character varying, address_type character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE separator TEXT;
BEGIN
  SELECT md5(random() :: TEXT) :: TEXT
      INTO separator;
  EXECUTE FORMAT('CREATE TEMPORARY TABLE query_output_%s (
    uuid         VARCHAR,
    gender_name  VARCHAR,
    address_type VARCHAR,
    address_name VARCHAR
  ) ON COMMIT DROP', separator);

  EXECUTE FORMAT('CREATE TEMPORARY TABLE denominator_query_output_%s (
    uuid         VARCHAR,
    gender_name  VARCHAR,
    address_type VARCHAR,
    address_name VARCHAR
  ) ON COMMIT DROP', separator);

  EXECUTE format('CREATE TEMPORARY TABLE aggregates_%s (
    total        BIGINT,
    percentage   FLOAT,
    gender       VARCHAR,
    address_type VARCHAR
  ) ON COMMIT DROP', separator);

  EXECUTE FORMAT('CREATE TEMPORARY TABLE denominator_aggregates_%s (
    total        BIGINT,
    gender       VARCHAR,
    address_type VARCHAR
  ) ON COMMIT DROP', separator);
  -- Store filtered query into a temporary variable

  EXECUTE FORMAT('INSERT INTO query_output_%s (uuid, gender_name, address_type, address_name) %s', separator,
                 frequency_query);

  EXECUTE FORMAT('INSERT INTO denominator_query_output_%s (uuid, gender_name, address_type, address_name) %s',
                 separator,
                 denominator_query);

  EXECUTE format('INSERT INTO aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid)  total,
      qo.gender_name  gender,
      qo.address_type address_type
    FROM query_output_%s qo
    GROUP BY qo.gender_name, qo.address_type', separator, separator);

  EXECUTE format('INSERT INTO denominator_aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid)  total,
      qo.gender_name  gender,
      qo.address_type address_type
    FROM denominator_query_output_%s qo
    GROUP BY qo.gender_name, qo.address_type', separator, separator);


  EXECUTE format('INSERT INTO aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid)  total,
      ''Total''         gender,
      qo.address_type address_type
    FROM query_output_%s qo
    GROUP BY qo.address_type', separator, separator);

  EXECUTE format('INSERT INTO denominator_aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid)  total,
      ''Total''         gender,
      qo.address_type address_type
    FROM denominator_query_output_%s qo
    GROUP BY qo.address_type', separator, separator);

  EXECUTE format('INSERT INTO aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid)  total,
      qo.gender_name  gender,
      ''All'' address_type
    FROM query_output_%s qo
    GROUP BY qo.gender_name', separator, separator);

  EXECUTE format('INSERT INTO denominator_aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid)  total,
      qo.gender_name  gender,
      ''All'' address_type
    FROM denominator_query_output_%s qo
    GROUP BY qo.gender_name', separator, separator);

  EXECUTE format('INSERT INTO aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid) total,
      ''Total''        gender,
      ''All''          address_type
    FROM query_output_%s qo', separator, separator);

  EXECUTE format('INSERT INTO denominator_aggregates_%s (total, gender, address_type)
    SELECT
      count(qo.uuid) total,
      ''Total''        gender,
      ''All''          address_type
    FROM denominator_query_output_%s qo', separator, separator);

  EXECUTE FORMAT('UPDATE aggregates_%s ag1
  SET percentage = (SELECT coalesce(round(((ag2.total :: FLOAT / dag1.total) * 100) :: NUMERIC, 2), 100)
                    FROM aggregates_%s ag2
                      INNER JOIN denominator_aggregates_%s dag1
                        ON ag2.address_type = dag1.address_type AND ag2.gender = dag1.gender
                    WHERE ag2.address_type = ag1.address_type AND ag2.gender = ag1.gender
                    LIMIT 1)', separator, separator, separator);

  EXECUTE FORMAT('INSERT INTO aggregates_%s (total, percentage, address_type, gender)
                        SELECT 0, 0, atname, gname from (
                            SELECT DISTINCT type atname,
                            name gname
                          FROM address_level_type_view, gender
                          WHERE name != ''Other''
                          UNION ALL
                          SELECT
                            ''All'' atname,
                            name gname
                          FROM gender
                          WHERE name != ''Other''
                          UNION ALL
                          SELECT DISTINCT
                            type atname,
                            ''Total'' gname
                          FROM address_level_type_view
                          UNION ALL
                          SELECT
                            ''All'' atname,
                            ''Total'' gname) as agt where (atname, gname) not in (select address_type, gender from aggregates_%s)',
                 separator, separator);

  RETURN QUERY EXECUTE format('SELECT *
               FROM aggregates_%s order by address_type, gender', separator);
END
$$;


ALTER FUNCTION public.frequency_and_percentage(frequency_query text, denominator_query text) OWNER TO openchs;

--
-- Name: grant_all_on_all(text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.grant_all_on_all(rolename text) RETURNS text
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE (
        SELECT 'GRANT ALL ON TABLE '
                   || string_agg(format('%I.%I', table_schema, table_name), ',')
                   || ' TO ' || quote_ident(rolename) || ''
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_type = 'BASE TABLE'
    );

    EXECUTE (
        SELECT 'GRANT SELECT ON '
                   || string_agg(format('%I.%I', schemaname, viewname), ',')
                   || ' TO ' || quote_ident(rolename) || ''
        FROM pg_catalog.pg_views
        WHERE schemaname = 'public'
          and viewowner in ('openchs')
    );

    EXECUTE 'GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO ' || quote_ident(rolename) || '';
    EXECUTE 'GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO ' || quote_ident(rolename) || '';
    RETURN 'ALL PERMISSIONS GRANTED TO ' || quote_ident(rolename);
END;
$$;


ALTER FUNCTION public.grant_all_on_all(rolename text) OWNER TO openchs;

--
-- Name: grant_all_on_views(text[], text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.grant_all_on_views(view_names text[], role text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    view_names_string text;
BEGIN
    view_names_string := array_to_string(view_names, ',');
    EXECUTE 'GRANT ALL ON ' || view_names_string || ' TO ' || quote_ident(role) || '';
    RETURN 'EXECUTE GRANT ALL ON ' || view_names_string || ' TO ' || quote_ident(role) || '';
END;
$$;


ALTER FUNCTION public.grant_all_on_views(view_names text[], role text) OWNER TO openchs;

--
-- Name: grant_permission_on_account_admin(text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.grant_permission_on_account_admin(rolename text) RETURNS text
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE 'GRANT ALL ON TABLE account_admin TO ' || quote_ident(rolename) || '';
    RETURN 'PERMISSIONS GRANTED FOR account_admin TO ' || quote_ident(rolename);
END;
$$;


ALTER FUNCTION public.grant_permission_on_account_admin(rolename text) OWNER TO openchs;

--
-- Name: jsonb_object_values_contain(jsonb, text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.jsonb_object_values_contain(obs jsonb, pattern text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  return EXISTS (select true from jsonb_each_text(obs) where value ilike pattern);
END;
$$;


ALTER FUNCTION public.jsonb_object_values_contain(obs jsonb, pattern text) OWNER TO openchs;

--
-- Name: revoke_permissions_on_account(text); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.revoke_permissions_on_account(rolename text) RETURNS text
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE 'REVOKE ALL ON TABLE account FROM ' || quote_ident(rolename) || '';
    RETURN 'ALL ACCOUNT PERMISSIONS REVOKED FROM ' || quote_ident(rolename);
END;
$$;


ALTER FUNCTION public.revoke_permissions_on_account(rolename text) OWNER TO openchs;

--
-- Name: title_lineage_locations_function(); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.title_lineage_locations_function() RETURNS TABLE(lowestpoint_id integer, title_lineage text)
    LANGUAGE sql
    AS $$
select al.id lowestpoint_id, string_agg(alevel_in_lineage.title, ', ' order by lineage.level) title_lineage
from address_level al
         join regexp_split_to_table(al.lineage :: text, '[.]') with ordinality lineage (point_id, level) ON TRUE
         join address_level alevel_in_lineage on alevel_in_lineage.id = lineage.point_id :: int
group by al.id
$$;


ALTER FUNCTION public.title_lineage_locations_function() OWNER TO openchs;

--
-- Name: virtual_catchment_address_mapping_function(); Type: FUNCTION; Schema: public; Owner: openchs
--

CREATE FUNCTION public.virtual_catchment_address_mapping_function() RETURNS TABLE(id bigint, catchment_id integer, addresslevel_id integer)
    LANGUAGE sql
    AS $$
select row_number() OVER ()  AS id,
       cam.catchment_id::int AS catchment_id,
       al.id                 AS addresslevel_id
from address_level al
         left outer join regexp_split_to_table((al.lineage)::text, '[.]'::text) WITH ORDINALITY lineage(point_id, level)
                         ON (true)
         left outer join catchment_address_mapping cam on cam.addresslevel_id = point_id::int
where catchment_id notnull
group by 2, 3
$$;


ALTER FUNCTION public.virtual_catchment_address_mapping_function() OWNER TO openchs;

SET default_tablespace = '';

--
-- Name: account; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.account (
    id integer NOT NULL,
    name character varying(255) NOT NULL
);


ALTER TABLE public.account OWNER TO openchs;

--
-- Name: account_admin; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.account_admin (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    account_id integer NOT NULL,
    admin_id integer NOT NULL
);


ALTER TABLE public.account_admin OWNER TO openchs;

--
-- Name: account_admin_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.account_admin_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.account_admin_id_seq OWNER TO openchs;

--
-- Name: account_admin_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.account_admin_id_seq OWNED BY public.account_admin.id;


--
-- Name: account_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.account_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.account_id_seq OWNER TO openchs;

--
-- Name: account_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.account_id_seq OWNED BY public.account.id;


--
-- Name: address_level; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.address_level (
    id integer NOT NULL,
    title character varying(255) NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    type_id integer,
    lineage public.ltree,
    parent_id integer,
    gps_coordinates point,
    location_properties jsonb,
    CONSTRAINT lineage_parent_consistency CHECK ((((parent_id IS NOT NULL) AND (public.subltree(lineage, 0, public.nlevel(lineage)) OPERATOR(public.~) (concat('*.', parent_id, '.', id))::public.lquery)) OR ((parent_id IS NULL) AND (lineage OPERATOR(public.~) (concat('', id))::public.lquery))))
);


ALTER TABLE public.address_level OWNER TO openchs;

--
-- Name: address_level_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.address_level_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.address_level_id_seq OWNER TO openchs;

--
-- Name: address_level_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.address_level_id_seq OWNED BY public.address_level.id;


--
-- Name: address_level_type; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.address_level_type (
    id integer NOT NULL,
    uuid character varying(255) DEFAULT public.uuid_generate_v4() NOT NULL,
    name character varying(255) NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer NOT NULL,
    version integer NOT NULL,
    audit_id integer,
    level double precision DEFAULT 0,
    parent_id integer
);


ALTER TABLE public.address_level_type OWNER TO openchs;

--
-- Name: address_level_type_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.address_level_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.address_level_type_id_seq OWNER TO openchs;

--
-- Name: address_level_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.address_level_type_id_seq OWNED BY public.address_level_type.id;


--
-- Name: organisation; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.organisation (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    db_user character varying(255) NOT NULL,
    uuid character varying(255) NOT NULL,
    parent_organisation_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    media_directory text,
    username_suffix text,
    account_id integer DEFAULT 1 NOT NULL,
    schema_name character varying(255) NOT NULL
);


ALTER TABLE public.organisation OWNER TO openchs;

--
-- Name: address_level_type_view; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.address_level_type_view AS
 WITH RECURSIVE list_of_orgs(id, parent_organisation_id) AS (
         SELECT organisation.id,
            organisation.parent_organisation_id
           FROM public.organisation
          WHERE ((organisation.db_user)::name = CURRENT_USER)
        UNION ALL
         SELECT o.id,
            o.parent_organisation_id
           FROM public.organisation o,
            list_of_orgs log
          WHERE (o.id = log.parent_organisation_id)
        )
 SELECT al.id,
    al.title,
    al.uuid,
    alt.level,
    al.version,
    al.organisation_id,
    al.audit_id,
    al.is_voided,
    al.type_id,
    alt.name AS type
   FROM ((public.address_level al
     JOIN public.address_level_type alt ON ((al.type_id = alt.id)))
     JOIN list_of_orgs loo ON ((loo.id = al.organisation_id)))
  WHERE (alt.is_voided IS NOT TRUE);


ALTER TABLE public.address_level_type_view OWNER TO openchs;

--
-- Name: form; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.form (
    id integer NOT NULL,
    name character varying(255),
    form_type character varying(255) NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    decision_rule text,
    validation_rule text,
    visit_schedule_rule text,
    checklists_rule text
);


ALTER TABLE public.form OWNER TO openchs;

--
-- Name: form_mapping; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.form_mapping (
    id integer NOT NULL,
    form_id bigint,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    entity_id bigint,
    observations_type_entity_id integer,
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    subject_type_id integer NOT NULL,
    enable_approval boolean DEFAULT false NOT NULL
);


ALTER TABLE public.form_mapping OWNER TO openchs;

--
-- Name: operational_encounter_type; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.operational_encounter_type (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    organisation_id integer NOT NULL,
    encounter_type_id integer NOT NULL,
    version integer NOT NULL,
    audit_id integer,
    name character varying(255),
    is_voided boolean DEFAULT false NOT NULL
);


ALTER TABLE public.operational_encounter_type OWNER TO openchs;

--
-- Name: operational_program; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.operational_program (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    organisation_id integer NOT NULL,
    program_id integer NOT NULL,
    version integer NOT NULL,
    audit_id integer,
    name character varying(255),
    is_voided boolean DEFAULT false NOT NULL,
    program_subject_label text
);


ALTER TABLE public.operational_program OWNER TO openchs;

--
-- Name: all_forms; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.all_forms AS
 SELECT DISTINCT x.organisation_id,
    x.form_id,
    x.form_name
   FROM ( SELECT form.id AS form_id,
            form.name AS form_name,
            m2.organisation_id
           FROM (public.form
             JOIN public.form_mapping m2 ON ((form.id = m2.form_id)))
          WHERE ((NOT form.is_voided) OR (NOT m2.is_voided))
        UNION
         SELECT form.id AS form_id,
            form.name AS form_name,
            oet.organisation_id
           FROM ((public.form
             JOIN public.form_mapping m2 ON (((form.id = m2.form_id) AND (m2.organisation_id = 1))))
             JOIN public.operational_encounter_type oet ON ((oet.encounter_type_id = m2.observations_type_entity_id)))
          WHERE ((NOT form.is_voided) OR (NOT m2.is_voided) OR (NOT oet.is_voided))
        UNION
         SELECT form.id AS form_id,
            form.name AS form_name,
            op.organisation_id
           FROM ((public.form
             JOIN public.form_mapping m2 ON (((form.id = m2.form_id) AND (m2.organisation_id = 1))))
             JOIN public.operational_program op ON ((op.program_id = m2.entity_id)))
          WHERE ((NOT form.is_voided) OR (NOT m2.is_voided) OR (NOT op.is_voided))) x;


ALTER TABLE public.all_forms OWNER TO openchs;

--
-- Name: concept; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.concept (
    id integer NOT NULL,
    data_type character varying(255) NOT NULL,
    high_absolute double precision,
    high_normal double precision,
    low_absolute double precision,
    low_normal double precision,
    name character varying(255) NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    unit character varying(50),
    organisation_id integer DEFAULT 1 NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    audit_id integer,
    key_values jsonb,
    active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.concept OWNER TO openchs;

--
-- Name: concept_answer; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.concept_answer (
    id integer NOT NULL,
    concept_id bigint NOT NULL,
    answer_concept_id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    answer_order double precision NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    abnormal boolean DEFAULT false NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    uniq boolean DEFAULT false NOT NULL,
    audit_id integer
);


ALTER TABLE public.concept_answer OWNER TO openchs;

--
-- Name: form_element; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.form_element (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    display_order double precision NOT NULL,
    is_mandatory boolean DEFAULT false NOT NULL,
    key_values jsonb,
    concept_id bigint NOT NULL,
    form_element_group_id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    type character varying(1024) DEFAULT NULL::character varying,
    valid_format_regex character varying(255),
    valid_format_description_key character varying(255),
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    rule text,
    CONSTRAINT valid_format_check CHECK ((((valid_format_regex IS NULL) AND (valid_format_description_key IS NULL)) OR ((valid_format_regex IS NOT NULL) AND (valid_format_description_key IS NOT NULL))))
);


ALTER TABLE public.form_element OWNER TO openchs;

--
-- Name: form_element_group; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.form_element_group (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    form_id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    display_order double precision DEFAULT '-1'::integer NOT NULL,
    display character varying(100),
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    rule text
);


ALTER TABLE public.form_element_group OWNER TO openchs;

--
-- Name: all_concept_answers; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.all_concept_answers AS
 SELECT DISTINCT all_forms.organisation_id,
    c3.name AS answer_concept_name
   FROM ((((((public.form_element
     JOIN public.form_element_group ON ((form_element.form_element_group_id = form_element_group.id)))
     JOIN public.form ON ((form_element_group.form_id = form.id)))
     JOIN public.concept c2 ON ((form_element.concept_id = c2.id)))
     JOIN public.concept_answer a ON ((c2.id = a.concept_id)))
     JOIN public.concept c3 ON ((a.answer_concept_id = c3.id)))
     JOIN public.all_forms ON ((all_forms.form_id = form.id)))
  WHERE ((NOT form_element.is_voided) OR (NOT form_element_group.is_voided) OR (NOT form.is_voided) OR (NOT c2.is_voided) OR (NOT c2.is_voided) OR (NOT c3.is_voided));


ALTER TABLE public.all_concept_answers OWNER TO openchs;

--
-- Name: all_concepts; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.all_concepts AS
 SELECT DISTINCT all_forms.organisation_id,
    c2.name AS concept_name
   FROM ((((public.form_element
     JOIN public.form_element_group ON ((form_element.form_element_group_id = form_element_group.id)))
     JOIN public.form ON ((form_element_group.form_id = form.id)))
     JOIN public.concept c2 ON ((form_element.concept_id = c2.id)))
     JOIN public.all_forms ON ((all_forms.form_id = form.id)))
  WHERE ((NOT form_element.is_voided) OR (NOT form_element_group.is_voided) OR (NOT form.is_voided) OR (NOT c2.is_voided));


ALTER TABLE public.all_concepts OWNER TO openchs;

--
-- Name: encounter_type; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.encounter_type (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    concept_id bigint,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    encounter_eligibility_check_rule text,
    active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.encounter_type OWNER TO openchs;

--
-- Name: all_encounter_types; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.all_encounter_types AS
 SELECT DISTINCT operational_encounter_type.organisation_id,
    et.name AS encounter_type_name
   FROM (public.operational_encounter_type
     JOIN public.encounter_type et ON ((operational_encounter_type.encounter_type_id = et.id)))
  WHERE ((NOT operational_encounter_type.is_voided) OR (NOT et.is_voided));


ALTER TABLE public.all_encounter_types OWNER TO openchs;

--
-- Name: all_form_element_groups; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.all_form_element_groups AS
 SELECT DISTINCT all_forms.organisation_id,
    form_element_group.name AS form_element_group_name
   FROM ((public.form_element_group
     JOIN public.form ON ((form_element_group.form_id = form.id)))
     JOIN public.all_forms ON ((all_forms.form_id = form.id)))
  WHERE ((NOT form_element_group.is_voided) OR (NOT form.is_voided));


ALTER TABLE public.all_form_element_groups OWNER TO openchs;

--
-- Name: all_form_elements; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.all_form_elements AS
 SELECT DISTINCT all_forms.organisation_id,
    form_element.name AS form_element_name
   FROM (((public.form_element
     JOIN public.form_element_group ON ((form_element.form_element_group_id = form_element_group.id)))
     JOIN public.form ON ((form_element_group.form_id = form.id)))
     JOIN public.all_forms ON ((all_forms.form_id = form.id)))
  WHERE ((NOT form_element.is_voided) OR (NOT form_element_group.is_voided));


ALTER TABLE public.all_form_elements OWNER TO openchs;

--
-- Name: all_operational_encounter_types; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.all_operational_encounter_types AS
 SELECT DISTINCT operational_encounter_type.organisation_id,
    operational_encounter_type.name AS operational_encounter_type_name
   FROM (public.operational_encounter_type
     JOIN public.encounter_type et ON ((operational_encounter_type.encounter_type_id = et.id)))
  WHERE ((NOT operational_encounter_type.is_voided) OR (NOT et.is_voided));


ALTER TABLE public.all_operational_encounter_types OWNER TO openchs;

--
-- Name: program; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.program (
    id smallint NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    version integer NOT NULL,
    colour character varying(20),
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    enrolment_summary_rule text,
    enrolment_eligibility_check_rule text,
    active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.program OWNER TO openchs;

--
-- Name: all_operational_programs; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.all_operational_programs AS
 SELECT DISTINCT operational_program.organisation_id,
    operational_program.name AS operational_program_name
   FROM (public.operational_program
     JOIN public.program p ON ((p.id = operational_program.program_id)))
  WHERE ((NOT operational_program.is_voided) OR (NOT p.is_voided));


ALTER TABLE public.all_operational_programs OWNER TO openchs;

--
-- Name: all_programs; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.all_programs AS
 SELECT DISTINCT operational_program.organisation_id,
    p.name AS program_name
   FROM (public.operational_program
     JOIN public.program p ON ((p.id = operational_program.program_id)))
  WHERE ((NOT operational_program.is_voided) OR (NOT p.is_voided));


ALTER TABLE public.all_programs OWNER TO openchs;

--
-- Name: approval_status; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.approval_status (
    id integer NOT NULL,
    uuid text NOT NULL,
    status text NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    created_date_time timestamp with time zone NOT NULL,
    last_modified_date_time timestamp(3) with time zone NOT NULL
);


ALTER TABLE public.approval_status OWNER TO openchs;

--
-- Name: approval_status_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.approval_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.approval_status_id_seq OWNER TO openchs;

--
-- Name: approval_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.approval_status_id_seq OWNED BY public.approval_status.id;


--
-- Name: audit; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.audit (
    id integer NOT NULL,
    uuid character varying(255),
    created_by_id bigint NOT NULL,
    last_modified_by_id bigint NOT NULL,
    created_date_time timestamp with time zone NOT NULL,
    last_modified_date_time timestamp(3) with time zone NOT NULL
);


ALTER TABLE public.audit OWNER TO openchs;

--
-- Name: audit_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.audit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.audit_id_seq OWNER TO openchs;

--
-- Name: audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.audit_id_seq OWNED BY public.audit.id;


--
-- Name: batch_job_execution; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.batch_job_execution (
    job_execution_id bigint NOT NULL,
    version bigint,
    job_instance_id bigint NOT NULL,
    create_time timestamp without time zone NOT NULL,
    start_time timestamp without time zone,
    end_time timestamp without time zone,
    status character varying(10),
    exit_code character varying(2500),
    exit_message character varying(2500),
    last_updated timestamp without time zone,
    job_configuration_location character varying(2500)
);


ALTER TABLE public.batch_job_execution OWNER TO openchs;

--
-- Name: batch_job_execution_context; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.batch_job_execution_context (
    job_execution_id bigint NOT NULL,
    short_context character varying(2500) NOT NULL,
    serialized_context text
);


ALTER TABLE public.batch_job_execution_context OWNER TO openchs;

--
-- Name: batch_job_execution_params; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.batch_job_execution_params (
    job_execution_id bigint NOT NULL,
    type_cd character varying(6) NOT NULL,
    key_name character varying(100) NOT NULL,
    string_val character varying(250),
    date_val timestamp without time zone,
    long_val bigint,
    double_val double precision,
    identifying character(1) NOT NULL
);


ALTER TABLE public.batch_job_execution_params OWNER TO openchs;

--
-- Name: batch_job_execution_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.batch_job_execution_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.batch_job_execution_seq OWNER TO openchs;

--
-- Name: batch_job_instance; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.batch_job_instance (
    job_instance_id bigint NOT NULL,
    version bigint,
    job_name character varying(100) NOT NULL,
    job_key character varying(32) NOT NULL
);


ALTER TABLE public.batch_job_instance OWNER TO openchs;

--
-- Name: batch_job_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.batch_job_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.batch_job_seq OWNER TO openchs;

--
-- Name: batch_step_execution; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.batch_step_execution (
    step_execution_id bigint NOT NULL,
    version bigint NOT NULL,
    step_name character varying(100) NOT NULL,
    job_execution_id bigint NOT NULL,
    start_time timestamp without time zone NOT NULL,
    end_time timestamp without time zone,
    status character varying(10),
    commit_count bigint,
    read_count bigint,
    filter_count bigint,
    write_count bigint,
    read_skip_count bigint,
    write_skip_count bigint,
    process_skip_count bigint,
    rollback_count bigint,
    exit_code character varying(2500),
    exit_message character varying(2500),
    last_updated timestamp without time zone
);


ALTER TABLE public.batch_step_execution OWNER TO openchs;

--
-- Name: batch_step_execution_context; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.batch_step_execution_context (
    step_execution_id bigint NOT NULL,
    short_context character varying(2500) NOT NULL,
    serialized_context text
);


ALTER TABLE public.batch_step_execution_context OWNER TO openchs;

--
-- Name: batch_step_execution_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.batch_step_execution_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.batch_step_execution_seq OWNER TO openchs;

--
-- Name: catchment; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.catchment (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    type character varying(1024) DEFAULT 'Villages'::character varying NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL
);


ALTER TABLE public.catchment OWNER TO openchs;

--
-- Name: catchment_address_mapping; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.catchment_address_mapping (
    id integer NOT NULL,
    catchment_id bigint NOT NULL,
    addresslevel_id bigint NOT NULL
);


ALTER TABLE public.catchment_address_mapping OWNER TO openchs;

--
-- Name: catchment_address_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.catchment_address_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.catchment_address_mapping_id_seq OWNER TO openchs;

--
-- Name: catchment_address_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.catchment_address_mapping_id_seq OWNED BY public.catchment_address_mapping.id;


--
-- Name: catchment_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.catchment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.catchment_id_seq OWNER TO openchs;

--
-- Name: catchment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.catchment_id_seq OWNED BY public.catchment.id;


--
-- Name: checklist; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.checklist (
    id integer NOT NULL,
    program_enrolment_id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    base_date timestamp with time zone NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    checklist_detail_id integer
);


ALTER TABLE public.checklist OWNER TO openchs;

--
-- Name: checklist_detail; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.checklist_detail (
    id smallint NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    audit_id integer NOT NULL,
    name character varying NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer NOT NULL
);


ALTER TABLE public.checklist_detail OWNER TO openchs;

--
-- Name: checklist_detail_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.checklist_detail_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.checklist_detail_id_seq OWNER TO openchs;

--
-- Name: checklist_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.checklist_detail_id_seq OWNED BY public.checklist_detail.id;


--
-- Name: checklist_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.checklist_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.checklist_id_seq OWNER TO openchs;

--
-- Name: checklist_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.checklist_id_seq OWNED BY public.checklist.id;


--
-- Name: checklist_item; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.checklist_item (
    id integer NOT NULL,
    completion_date timestamp with time zone,
    checklist_id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    observations jsonb,
    checklist_item_detail_id integer
);


ALTER TABLE public.checklist_item OWNER TO openchs;

--
-- Name: checklist_item_detail; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.checklist_item_detail (
    id smallint NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    audit_id integer NOT NULL,
    form_id integer NOT NULL,
    concept_id integer NOT NULL,
    checklist_detail_id integer NOT NULL,
    status jsonb DEFAULT '{}'::jsonb NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer NOT NULL,
    dependent_on integer,
    schedule_on_expiry_of_dependency boolean DEFAULT false NOT NULL,
    min_days_from_start_date smallint,
    min_days_from_dependent integer,
    expires_after integer
);


ALTER TABLE public.checklist_item_detail OWNER TO openchs;

--
-- Name: checklist_item_detail_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.checklist_item_detail_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.checklist_item_detail_id_seq OWNER TO openchs;

--
-- Name: checklist_item_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.checklist_item_detail_id_seq OWNED BY public.checklist_item_detail.id;


--
-- Name: checklist_item_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.checklist_item_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.checklist_item_id_seq OWNER TO openchs;

--
-- Name: checklist_item_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.checklist_item_id_seq OWNED BY public.checklist_item.id;


--
-- Name: comment; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.comment (
    id integer NOT NULL,
    organisation_id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    text text NOT NULL,
    subject_id bigint NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    audit_id bigint NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    comment_thread_id bigint
);


ALTER TABLE public.comment OWNER TO openchs;

--
-- Name: comment_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.comment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.comment_id_seq OWNER TO openchs;

--
-- Name: comment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.comment_id_seq OWNED BY public.comment.id;


--
-- Name: comment_thread; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.comment_thread (
    id integer NOT NULL,
    organisation_id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    status text NOT NULL,
    open_date_time timestamp with time zone,
    resolved_date_time timestamp with time zone,
    is_voided boolean DEFAULT false NOT NULL,
    audit_id bigint NOT NULL,
    version bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.comment_thread OWNER TO openchs;

--
-- Name: comment_thread_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.comment_thread_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.comment_thread_id_seq OWNER TO openchs;

--
-- Name: comment_thread_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.comment_thread_id_seq OWNED BY public.comment_thread.id;


--
-- Name: concept_answer_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.concept_answer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.concept_answer_id_seq OWNER TO openchs;

--
-- Name: concept_answer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.concept_answer_id_seq OWNED BY public.concept_answer.id;


--
-- Name: concept_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.concept_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.concept_id_seq OWNER TO openchs;

--
-- Name: concept_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.concept_id_seq OWNED BY public.concept.id;


--
-- Name: dashboard; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.dashboard (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    is_voided boolean DEFAULT false NOT NULL,
    version integer,
    organisation_id integer NOT NULL,
    audit_id integer
);


ALTER TABLE public.dashboard OWNER TO openchs;

--
-- Name: dashboard_card_mapping; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.dashboard_card_mapping (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    dashboard_id bigint NOT NULL,
    card_id bigint NOT NULL,
    display_order double precision DEFAULT '-1'::integer NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    version integer,
    organisation_id integer NOT NULL,
    audit_id integer
);


ALTER TABLE public.dashboard_card_mapping OWNER TO openchs;

--
-- Name: dashboard_card_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.dashboard_card_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.dashboard_card_mapping_id_seq OWNER TO openchs;

--
-- Name: dashboard_card_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.dashboard_card_mapping_id_seq OWNED BY public.dashboard_card_mapping.id;


--
-- Name: dashboard_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.dashboard_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.dashboard_id_seq OWNER TO openchs;

--
-- Name: dashboard_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.dashboard_id_seq OWNED BY public.dashboard.id;


--
-- Name: dashboard_section; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.dashboard_section (
    id integer NOT NULL,
    uuid text NOT NULL,
    name text,
    description text,
    dashboard_id bigint NOT NULL,
    view_type text NOT NULL,
    display_order double precision DEFAULT '-1'::integer NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    version integer,
    organisation_id bigint NOT NULL,
    audit_id bigint,
    CONSTRAINT dashboard_section_check CHECK ((((name IS NOT NULL) AND (description IS NOT NULL)) OR (view_type = 'Default'::text)))
);


ALTER TABLE public.dashboard_section OWNER TO openchs;

--
-- Name: dashboard_section_card_mapping; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.dashboard_section_card_mapping (
    id integer NOT NULL,
    uuid text NOT NULL,
    dashboard_section_id bigint NOT NULL,
    card_id bigint NOT NULL,
    display_order double precision DEFAULT '-1'::integer NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    version integer,
    organisation_id bigint NOT NULL,
    audit_id bigint
);


ALTER TABLE public.dashboard_section_card_mapping OWNER TO openchs;

--
-- Name: dashboard_section_card_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.dashboard_section_card_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.dashboard_section_card_mapping_id_seq OWNER TO openchs;

--
-- Name: dashboard_section_card_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.dashboard_section_card_mapping_id_seq OWNED BY public.dashboard_section_card_mapping.id;


--
-- Name: dashboard_section_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.dashboard_section_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.dashboard_section_id_seq OWNER TO openchs;

--
-- Name: dashboard_section_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.dashboard_section_id_seq OWNED BY public.dashboard_section.id;


--
-- Name: decision_concept; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.decision_concept (
    id integer NOT NULL,
    concept_id bigint NOT NULL,
    form_id bigint NOT NULL
);


ALTER TABLE public.decision_concept OWNER TO openchs;

--
-- Name: decision_concept_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.decision_concept_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.decision_concept_id_seq OWNER TO openchs;

--
-- Name: decision_concept_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.decision_concept_id_seq OWNED BY public.decision_concept.id;


--
-- Name: deps_saved_ddl; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.deps_saved_ddl (
    deps_id integer NOT NULL,
    deps_view_schema character varying(255),
    deps_view_name character varying(255),
    deps_ddl_to_run text
);


ALTER TABLE public.deps_saved_ddl OWNER TO openchs;

--
-- Name: deps_saved_ddl_deps_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.deps_saved_ddl_deps_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.deps_saved_ddl_deps_id_seq OWNER TO openchs;

--
-- Name: deps_saved_ddl_deps_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.deps_saved_ddl_deps_id_seq OWNED BY public.deps_saved_ddl.deps_id;


--
-- Name: encounter; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.encounter (
    id integer NOT NULL,
    observations jsonb NOT NULL,
    encounter_date_time timestamp with time zone,
    encounter_type_id integer NOT NULL,
    individual_id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    audit_id integer,
    encounter_location point,
    earliest_visit_date_time timestamp with time zone,
    max_visit_date_time timestamp with time zone,
    cancel_date_time timestamp with time zone,
    cancel_observations jsonb,
    cancel_location point,
    name text,
    legacy_id character varying
);


ALTER TABLE public.encounter OWNER TO openchs;

--
-- Name: encounter_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.encounter_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.encounter_id_seq OWNER TO openchs;

--
-- Name: encounter_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.encounter_id_seq OWNED BY public.encounter.id;


--
-- Name: encounter_type_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.encounter_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.encounter_type_id_seq OWNER TO openchs;

--
-- Name: encounter_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.encounter_type_id_seq OWNED BY public.encounter_type.id;


--
-- Name: entity_approval_status; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.entity_approval_status (
    id integer NOT NULL,
    uuid text NOT NULL,
    entity_id bigint NOT NULL,
    entity_type text NOT NULL,
    approval_status_id bigint NOT NULL,
    approval_status_comment text,
    organisation_id bigint NOT NULL,
    auto_approved boolean DEFAULT false NOT NULL,
    audit_id bigint NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    status_date_time timestamp with time zone NOT NULL
);


ALTER TABLE public.entity_approval_status OWNER TO openchs;

--
-- Name: entity_approval_status_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.entity_approval_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.entity_approval_status_id_seq OWNER TO openchs;

--
-- Name: entity_approval_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.entity_approval_status_id_seq OWNED BY public.entity_approval_status.id;


--
-- Name: facility; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.facility (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    address_id bigint,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer NOT NULL,
    version integer NOT NULL,
    audit_id integer
);


ALTER TABLE public.facility OWNER TO openchs;

--
-- Name: facility_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.facility_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.facility_id_seq OWNER TO openchs;

--
-- Name: facility_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.facility_id_seq OWNED BY public.facility.id;


--
-- Name: form_element_group_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.form_element_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.form_element_group_id_seq OWNER TO openchs;

--
-- Name: form_element_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.form_element_group_id_seq OWNED BY public.form_element_group.id;


--
-- Name: form_element_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.form_element_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.form_element_id_seq OWNER TO openchs;

--
-- Name: form_element_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.form_element_id_seq OWNED BY public.form_element.id;


--
-- Name: form_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.form_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.form_id_seq OWNER TO openchs;

--
-- Name: form_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.form_id_seq OWNED BY public.form.id;


--
-- Name: form_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.form_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.form_mapping_id_seq OWNER TO openchs;

--
-- Name: form_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.form_mapping_id_seq OWNED BY public.form_mapping.id;


--
-- Name: gender; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.gender (
    id smallint NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    concept_id bigint,
    version integer NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer NOT NULL
);


ALTER TABLE public.gender OWNER TO openchs;

--
-- Name: gender_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.gender_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.gender_id_seq OWNER TO openchs;

--
-- Name: gender_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.gender_id_seq OWNED BY public.gender.id;


--
-- Name: group_dashboard; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.group_dashboard (
    id integer NOT NULL,
    uuid text NOT NULL,
    organisation_id bigint NOT NULL,
    is_primary_dashboard boolean DEFAULT false NOT NULL,
    audit_id bigint NOT NULL,
    version bigint DEFAULT 0 NOT NULL,
    group_id bigint NOT NULL,
    dashboard_id bigint NOT NULL,
    is_voided boolean DEFAULT false NOT NULL
);


ALTER TABLE public.group_dashboard OWNER TO openchs;

--
-- Name: group_dashboard_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.group_dashboard_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.group_dashboard_id_seq OWNER TO openchs;

--
-- Name: group_dashboard_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.group_dashboard_id_seq OWNED BY public.group_dashboard.id;


--
-- Name: group_privilege; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.group_privilege (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    group_id integer NOT NULL,
    privilege_id integer NOT NULL,
    subject_type_id integer,
    program_id integer,
    program_encounter_type_id integer,
    encounter_type_id integer,
    checklist_detail_id integer,
    allow boolean DEFAULT false NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    version integer,
    organisation_id integer NOT NULL,
    audit_id integer
);


ALTER TABLE public.group_privilege OWNER TO openchs;

--
-- Name: group_privilege_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.group_privilege_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.group_privilege_id_seq OWNER TO openchs;

--
-- Name: group_privilege_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.group_privilege_id_seq OWNED BY public.group_privilege.id;


--
-- Name: group_role; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.group_role (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    group_subject_type_id integer NOT NULL,
    role text,
    member_subject_type_id integer NOT NULL,
    is_primary boolean DEFAULT false NOT NULL,
    maximum_number_of_members integer NOT NULL,
    minimum_number_of_members integer NOT NULL,
    organisation_id integer NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    version integer
);


ALTER TABLE public.group_role OWNER TO openchs;

--
-- Name: group_role_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.group_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.group_role_id_seq OWNER TO openchs;

--
-- Name: group_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.group_role_id_seq OWNED BY public.group_role.id;


--
-- Name: group_subject; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.group_subject (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    group_subject_id integer NOT NULL,
    member_subject_id integer NOT NULL,
    group_role_id integer NOT NULL,
    membership_start_date timestamp with time zone,
    membership_end_date timestamp with time zone,
    organisation_id integer NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    version integer
);


ALTER TABLE public.group_subject OWNER TO openchs;

--
-- Name: group_subject_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.group_subject_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.group_subject_id_seq OWNER TO openchs;

--
-- Name: group_subject_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.group_subject_id_seq OWNED BY public.group_subject.id;


--
-- Name: groups; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.groups (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    version integer,
    organisation_id integer NOT NULL,
    audit_id integer,
    has_all_privileges boolean DEFAULT false NOT NULL
);


ALTER TABLE public.groups OWNER TO openchs;

--
-- Name: groups_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.groups_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.groups_id_seq OWNER TO openchs;

--
-- Name: groups_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.groups_id_seq OWNED BY public.groups.id;


--
-- Name: identifier_assignment; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.identifier_assignment (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    identifier_source_id integer NOT NULL,
    identifier text NOT NULL,
    assignment_order integer NOT NULL,
    assigned_to_user_id integer NOT NULL,
    individual_id integer,
    program_enrolment_id integer,
    version integer NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer NOT NULL
);


ALTER TABLE public.identifier_assignment OWNER TO openchs;

--
-- Name: identifier_assignment_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.identifier_assignment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.identifier_assignment_id_seq OWNER TO openchs;

--
-- Name: identifier_assignment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.identifier_assignment_id_seq OWNED BY public.identifier_assignment.id;


--
-- Name: identifier_source; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.identifier_source (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    type text NOT NULL,
    catchment_id integer,
    facility_id integer,
    minimum_balance integer DEFAULT 20 NOT NULL,
    batch_generation_size integer DEFAULT 100 NOT NULL,
    options jsonb DEFAULT '{}'::jsonb NOT NULL,
    version integer NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer NOT NULL,
    min_length integer DEFAULT 0 NOT NULL,
    max_length integer DEFAULT 0 NOT NULL
);


ALTER TABLE public.identifier_source OWNER TO openchs;

--
-- Name: identifier_source_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.identifier_source_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.identifier_source_id_seq OWNER TO openchs;

--
-- Name: identifier_source_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.identifier_source_id_seq OWNED BY public.identifier_source.id;


--
-- Name: identifier_user_assignment; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.identifier_user_assignment (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    identifier_source_id integer NOT NULL,
    assigned_to_user_id integer NOT NULL,
    identifier_start text NOT NULL,
    identifier_end text NOT NULL,
    last_assigned_identifier text,
    version integer NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer NOT NULL
);


ALTER TABLE public.identifier_user_assignment OWNER TO openchs;

--
-- Name: identifier_user_assignment_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.identifier_user_assignment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.identifier_user_assignment_id_seq OWNER TO openchs;

--
-- Name: identifier_user_assignment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.identifier_user_assignment_id_seq OWNED BY public.identifier_user_assignment.id;


--
-- Name: individual; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.individual (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    address_id bigint,
    observations jsonb,
    version integer NOT NULL,
    date_of_birth date,
    date_of_birth_verified boolean NOT NULL,
    gender_id bigint,
    registration_date date DEFAULT '2017-01-01'::date NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    first_name character varying(256),
    last_name character varying(256),
    is_voided boolean DEFAULT false NOT NULL,
    audit_id integer,
    facility_id bigint,
    registration_location point,
    subject_type_id integer NOT NULL,
    legacy_id character varying
);


ALTER TABLE public.individual OWNER TO openchs;

--
-- Name: individual_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.individual_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.individual_id_seq OWNER TO openchs;

--
-- Name: individual_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.individual_id_seq OWNED BY public.individual.id;


--
-- Name: program_enrolment; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.program_enrolment (
    id integer NOT NULL,
    program_id smallint NOT NULL,
    individual_id bigint NOT NULL,
    program_outcome_id smallint,
    observations jsonb,
    program_exit_observations jsonb,
    enrolment_date_time timestamp with time zone NOT NULL,
    program_exit_date_time timestamp with time zone,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    enrolment_location point,
    exit_location point,
    legacy_id character varying
);


ALTER TABLE public.program_enrolment OWNER TO openchs;

--
-- Name: individual_program_enrolment_search_view; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.individual_program_enrolment_search_view AS
 SELECT progralalise.individual_id,
    string_agg(progralalise.programname, ','::text) AS program_name
   FROM ( SELECT pe.individual_id,
            concat(op.name, ':', prog.colour) AS programname
           FROM ((public.program_enrolment pe
             JOIN public.program prog ON ((prog.id = pe.program_id)))
             JOIN public.operational_program op ON (((prog.id = op.program_id) AND (pe.organisation_id = op.organisation_id))))
          WHERE ((pe.program_exit_date_time IS NULL) AND (pe.is_voided = false))
          GROUP BY pe.individual_id, op.name, prog.colour) progralalise
  GROUP BY progralalise.individual_id;


ALTER TABLE public.individual_program_enrolment_search_view OWNER TO openchs;

--
-- Name: individual_relation; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.individual_relation (
    id smallint NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer NOT NULL,
    version integer NOT NULL,
    audit_id integer
);


ALTER TABLE public.individual_relation OWNER TO openchs;

--
-- Name: individual_relation_gender_mapping; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.individual_relation_gender_mapping (
    id smallint NOT NULL,
    uuid character varying(255) NOT NULL,
    relation_id smallint NOT NULL,
    gender_id smallint NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer NOT NULL,
    version integer NOT NULL,
    audit_id integer
);


ALTER TABLE public.individual_relation_gender_mapping OWNER TO openchs;

--
-- Name: individual_relation_gender_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.individual_relation_gender_mapping_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.individual_relation_gender_mapping_id_seq OWNER TO openchs;

--
-- Name: individual_relation_gender_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.individual_relation_gender_mapping_id_seq OWNED BY public.individual_relation_gender_mapping.id;


--
-- Name: individual_relation_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.individual_relation_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.individual_relation_id_seq OWNER TO openchs;

--
-- Name: individual_relation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.individual_relation_id_seq OWNED BY public.individual_relation.id;


--
-- Name: individual_relationship; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.individual_relationship (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    individual_a_id bigint NOT NULL,
    individual_b_id bigint NOT NULL,
    relationship_type_id smallint NOT NULL,
    enter_date_time timestamp with time zone,
    exit_date_time timestamp with time zone,
    exit_observations jsonb,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer NOT NULL,
    version integer NOT NULL,
    audit_id integer
);


ALTER TABLE public.individual_relationship OWNER TO openchs;

--
-- Name: individual_relationship_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.individual_relationship_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.individual_relationship_id_seq OWNER TO openchs;

--
-- Name: individual_relationship_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.individual_relationship_id_seq OWNED BY public.individual_relationship.id;


--
-- Name: individual_relationship_type; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.individual_relationship_type (
    id smallint NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    individual_a_is_to_b_relation_id smallint NOT NULL,
    individual_b_is_to_a_relation_id smallint NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer NOT NULL,
    version integer NOT NULL,
    audit_id integer
);


ALTER TABLE public.individual_relationship_type OWNER TO openchs;

--
-- Name: individual_relationship_type_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.individual_relationship_type_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.individual_relationship_type_id_seq OWNER TO openchs;

--
-- Name: individual_relationship_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.individual_relationship_type_id_seq OWNED BY public.individual_relationship_type.id;


--
-- Name: individual_relative; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.individual_relative (
    id smallint NOT NULL,
    uuid character varying(255) NOT NULL,
    individual_id bigint NOT NULL,
    relative_individual_id bigint NOT NULL,
    relation_id smallint NOT NULL,
    enter_date_time timestamp with time zone,
    exit_date_time timestamp with time zone,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id integer NOT NULL,
    version integer NOT NULL,
    audit_id integer
);


ALTER TABLE public.individual_relative OWNER TO openchs;

--
-- Name: individual_relative_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.individual_relative_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.individual_relative_id_seq OWNER TO openchs;

--
-- Name: individual_relative_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.individual_relative_id_seq OWNED BY public.individual_relative.id;


--
-- Name: location_location_mapping; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.location_location_mapping (
    id integer NOT NULL,
    location_id bigint,
    parent_location_id bigint,
    version integer NOT NULL,
    audit_id bigint,
    uuid character varying(255) NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id bigint
);


ALTER TABLE public.location_location_mapping OWNER TO openchs;

--
-- Name: location_location_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.location_location_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.location_location_mapping_id_seq OWNER TO openchs;

--
-- Name: location_location_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.location_location_mapping_id_seq OWNED BY public.location_location_mapping.id;


--
-- Name: msg91_config; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.msg91_config (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    auth_key character varying(255) NOT NULL,
    otp_sms_template_id character varying(255) NOT NULL,
    otp_length smallint,
    organisation_id integer NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    version integer
);


ALTER TABLE public.msg91_config OWNER TO openchs;

--
-- Name: msg91_config_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.msg91_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.msg91_config_id_seq OWNER TO openchs;

--
-- Name: msg91_config_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.msg91_config_id_seq OWNED BY public.msg91_config.id;


--
-- Name: news; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.news (
    id integer NOT NULL,
    organisation_id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    title text NOT NULL,
    content text,
    contenthtml text,
    hero_image text,
    published_date timestamp with time zone,
    is_voided boolean DEFAULT false NOT NULL,
    audit_id bigint NOT NULL,
    version bigint DEFAULT 0 NOT NULL
);


ALTER TABLE public.news OWNER TO openchs;

--
-- Name: news_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.news_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.news_id_seq OWNER TO openchs;

--
-- Name: news_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.news_id_seq OWNED BY public.news.id;


--
-- Name: non_applicable_form_element; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.non_applicable_form_element (
    id integer NOT NULL,
    organisation_id bigint,
    form_element_id bigint,
    is_voided boolean DEFAULT false NOT NULL,
    version integer DEFAULT 0 NOT NULL,
    audit_id integer,
    uuid character varying(255) NOT NULL
);


ALTER TABLE public.non_applicable_form_element OWNER TO openchs;

--
-- Name: non_applicable_form_element_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.non_applicable_form_element_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.non_applicable_form_element_id_seq OWNER TO openchs;

--
-- Name: non_applicable_form_element_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.non_applicable_form_element_id_seq OWNED BY public.non_applicable_form_element.id;


--
-- Name: operational_encounter_type_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.operational_encounter_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.operational_encounter_type_id_seq OWNER TO openchs;

--
-- Name: operational_encounter_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.operational_encounter_type_id_seq OWNED BY public.operational_encounter_type.id;


--
-- Name: operational_program_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.operational_program_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.operational_program_id_seq OWNER TO openchs;

--
-- Name: operational_program_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.operational_program_id_seq OWNED BY public.operational_program.id;


--
-- Name: operational_subject_type; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.operational_subject_type (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    subject_type_id integer NOT NULL,
    organisation_id bigint NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    audit_id bigint NOT NULL,
    version integer DEFAULT 1
);


ALTER TABLE public.operational_subject_type OWNER TO openchs;

--
-- Name: operational_subject_type_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.operational_subject_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.operational_subject_type_id_seq OWNER TO openchs;

--
-- Name: operational_subject_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.operational_subject_type_id_seq OWNED BY public.operational_subject_type.id;


--
-- Name: org_ids; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.org_ids WITH (security_barrier='true') AS
 WITH RECURSIVE list_of_orgs(id, parent_organisation_id) AS (
         SELECT organisation.id,
            organisation.parent_organisation_id
           FROM public.organisation
          WHERE ((organisation.db_user)::name = CURRENT_USER)
        UNION ALL
         SELECT o.id,
            o.parent_organisation_id
           FROM public.organisation o,
            list_of_orgs log
          WHERE (o.id = log.parent_organisation_id)
        )
 SELECT list_of_orgs.id
   FROM list_of_orgs;


ALTER TABLE public.org_ids OWNER TO openchs;

--
-- Name: organisation_config; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.organisation_config (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    organisation_id bigint NOT NULL,
    settings jsonb,
    audit_id bigint,
    version integer DEFAULT 1,
    is_voided boolean DEFAULT false,
    worklist_updation_rule text
);


ALTER TABLE public.organisation_config OWNER TO openchs;

--
-- Name: organisation_config_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.organisation_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.organisation_config_id_seq OWNER TO openchs;

--
-- Name: organisation_config_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.organisation_config_id_seq OWNED BY public.organisation_config.id;


--
-- Name: organisation_group; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.organisation_group (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    db_user character varying(255) NOT NULL,
    account_id integer NOT NULL
);


ALTER TABLE public.organisation_group OWNER TO openchs;

--
-- Name: organisation_group_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.organisation_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.organisation_group_id_seq OWNER TO openchs;

--
-- Name: organisation_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.organisation_group_id_seq OWNED BY public.organisation_group.id;


--
-- Name: organisation_group_organisation; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.organisation_group_organisation (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    organisation_group_id integer NOT NULL,
    organisation_id integer NOT NULL
);


ALTER TABLE public.organisation_group_organisation OWNER TO openchs;

--
-- Name: organisation_group_organisation_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.organisation_group_organisation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.organisation_group_organisation_id_seq OWNER TO openchs;

--
-- Name: organisation_group_organisation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.organisation_group_organisation_id_seq OWNED BY public.organisation_group_organisation.id;


--
-- Name: organisation_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.organisation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.organisation_id_seq OWNER TO openchs;

--
-- Name: organisation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.organisation_id_seq OWNED BY public.organisation.id;


--
-- Name: platform_translation; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.platform_translation (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    translation_json jsonb NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    platform character varying(255) NOT NULL,
    language character varying(255),
    version integer NOT NULL,
    audit_id integer NOT NULL
);


ALTER TABLE public.platform_translation OWNER TO openchs;

--
-- Name: platform_translation_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.platform_translation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.platform_translation_id_seq OWNER TO openchs;

--
-- Name: platform_translation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.platform_translation_id_seq OWNED BY public.platform_translation.id;


--
-- Name: privilege; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.privilege (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    entity_type character varying(255) NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    created_date_time timestamp with time zone,
    last_modified_date_time timestamp(3) with time zone
);


ALTER TABLE public.privilege OWNER TO openchs;

--
-- Name: privilege_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.privilege_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.privilege_id_seq OWNER TO openchs;

--
-- Name: privilege_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.privilege_id_seq OWNED BY public.privilege.id;


--
-- Name: program_encounter; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.program_encounter (
    id integer NOT NULL,
    observations jsonb NOT NULL,
    earliest_visit_date_time timestamp with time zone,
    encounter_date_time timestamp with time zone,
    program_enrolment_id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    encounter_type_id integer DEFAULT 1 NOT NULL,
    name character varying(255),
    max_visit_date_time timestamp with time zone,
    organisation_id integer DEFAULT 1 NOT NULL,
    cancel_date_time timestamp with time zone,
    cancel_observations jsonb,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    encounter_location point,
    cancel_location point,
    legacy_id character varying,
    CONSTRAINT program_encounter_cannot_cancel_and_perform_check CHECK (((encounter_date_time IS NULL) OR (cancel_date_time IS NULL)))
);


ALTER TABLE public.program_encounter OWNER TO openchs;

--
-- Name: program_encounter_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.program_encounter_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.program_encounter_id_seq OWNER TO openchs;

--
-- Name: program_encounter_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.program_encounter_id_seq OWNED BY public.program_encounter.id;


--
-- Name: program_enrolment_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.program_enrolment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.program_enrolment_id_seq OWNER TO openchs;

--
-- Name: program_enrolment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.program_enrolment_id_seq OWNED BY public.program_enrolment.id;


--
-- Name: program_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.program_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.program_id_seq OWNER TO openchs;

--
-- Name: program_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.program_id_seq OWNED BY public.program.id;


--
-- Name: program_organisation_config; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.program_organisation_config (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    program_id bigint NOT NULL,
    organisation_id bigint NOT NULL,
    visit_schedule jsonb,
    version integer NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL
);


ALTER TABLE public.program_organisation_config OWNER TO openchs;

--
-- Name: program_organisation_config_at_risk_concept; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.program_organisation_config_at_risk_concept (
    id integer NOT NULL,
    program_organisation_config_id integer NOT NULL,
    concept_id integer NOT NULL
);


ALTER TABLE public.program_organisation_config_at_risk_concept OWNER TO openchs;

--
-- Name: program_organisation_config_at_risk_concept_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.program_organisation_config_at_risk_concept_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.program_organisation_config_at_risk_concept_id_seq OWNER TO openchs;

--
-- Name: program_organisation_config_at_risk_concept_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.program_organisation_config_at_risk_concept_id_seq OWNED BY public.program_organisation_config_at_risk_concept.id;


--
-- Name: program_organisation_config_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.program_organisation_config_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.program_organisation_config_id_seq OWNER TO openchs;

--
-- Name: program_organisation_config_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.program_organisation_config_id_seq OWNED BY public.program_organisation_config.id;


--
-- Name: program_outcome; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.program_outcome (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    version integer NOT NULL,
    organisation_id integer DEFAULT 1 NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL
);


ALTER TABLE public.program_outcome OWNER TO openchs;

--
-- Name: program_outcome_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.program_outcome_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.program_outcome_id_seq OWNER TO openchs;

--
-- Name: program_outcome_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.program_outcome_id_seq OWNED BY public.program_outcome.id;


--
-- Name: report_card; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.report_card (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    name character varying(255) NOT NULL,
    query text,
    description text,
    colour character varying(20),
    is_voided boolean DEFAULT false NOT NULL,
    version integer,
    organisation_id integer NOT NULL,
    audit_id integer,
    standard_report_card_type_id bigint,
    icon_file_s3_key text,
    CONSTRAINT report_card_optional_standard_report_card_type CHECK (((standard_report_card_type_id IS NOT NULL) OR (query IS NOT NULL)))
);


ALTER TABLE public.report_card OWNER TO openchs;

--
-- Name: report_card_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.report_card_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.report_card_id_seq OWNER TO openchs;

--
-- Name: report_card_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.report_card_id_seq OWNED BY public.report_card.id;


--
-- Name: rule; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.rule (
    id smallint NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    audit_id integer NOT NULL,
    type character varying NOT NULL,
    rule_dependency_id integer,
    name character varying NOT NULL,
    fn_name character varying NOT NULL,
    data jsonb,
    organisation_id integer NOT NULL,
    execution_order double precision DEFAULT 10000.0 NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    entity jsonb NOT NULL
);


ALTER TABLE public.rule OWNER TO openchs;

--
-- Name: rule_dependency; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.rule_dependency (
    id smallint NOT NULL,
    uuid character varying(255) NOT NULL,
    version integer NOT NULL,
    audit_id integer NOT NULL,
    checksum character varying NOT NULL,
    code text NOT NULL,
    organisation_id integer NOT NULL,
    is_voided boolean DEFAULT false NOT NULL
);


ALTER TABLE public.rule_dependency OWNER TO openchs;

--
-- Name: rule_dependency_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.rule_dependency_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.rule_dependency_id_seq OWNER TO openchs;

--
-- Name: rule_dependency_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.rule_dependency_id_seq OWNED BY public.rule_dependency.id;


--
-- Name: rule_failure_log; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.rule_failure_log (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    form_id character varying(255) NOT NULL,
    rule_type character varying(255) NOT NULL,
    entity_type character varying(255) NOT NULL,
    entity_id character varying(255) NOT NULL,
    error_message character varying(255) NOT NULL,
    stacktrace text NOT NULL,
    source character varying(255) NOT NULL,
    audit_id integer,
    is_voided boolean DEFAULT false NOT NULL,
    version integer NOT NULL,
    organisation_id bigint NOT NULL
);


ALTER TABLE public.rule_failure_log OWNER TO openchs;

--
-- Name: rule_failure_log_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.rule_failure_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.rule_failure_log_id_seq OWNER TO openchs;

--
-- Name: rule_failure_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.rule_failure_log_id_seq OWNED BY public.rule_failure_log.id;


--
-- Name: rule_failure_telemetry; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.rule_failure_telemetry (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    user_id integer NOT NULL,
    organisation_id bigint NOT NULL,
    version integer DEFAULT 1,
    rule_uuid character varying(255) NOT NULL,
    individual_uuid character varying(255) NOT NULL,
    error_message character varying(255) NOT NULL,
    stacktrace text NOT NULL,
    error_date_time timestamp with time zone,
    close_date_time timestamp with time zone,
    is_closed boolean DEFAULT false NOT NULL,
    audit_id bigint
);


ALTER TABLE public.rule_failure_telemetry OWNER TO openchs;

--
-- Name: rule_failure_telemetry_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.rule_failure_telemetry_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.rule_failure_telemetry_id_seq OWNER TO openchs;

--
-- Name: rule_failure_telemetry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.rule_failure_telemetry_id_seq OWNED BY public.rule_failure_telemetry.id;


--
-- Name: rule_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.rule_id_seq
    AS smallint
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.rule_id_seq OWNER TO openchs;

--
-- Name: rule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.rule_id_seq OWNED BY public.rule.id;


--
-- Name: schema_version; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.schema_version (
    installed_rank integer NOT NULL,
    version character varying(50),
    description character varying(200) NOT NULL,
    type character varying(20) NOT NULL,
    script character varying(1000) NOT NULL,
    checksum integer,
    installed_by character varying(100) NOT NULL,
    installed_on timestamp without time zone DEFAULT now() NOT NULL,
    execution_time integer NOT NULL,
    success boolean NOT NULL
);


ALTER TABLE public.schema_version OWNER TO openchs;

--
-- Name: standard_report_card_type; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.standard_report_card_type (
    id integer NOT NULL,
    uuid text NOT NULL,
    name text NOT NULL,
    description text,
    is_voided boolean DEFAULT false NOT NULL,
    created_date_time timestamp with time zone NOT NULL,
    last_modified_date_time timestamp(3) with time zone NOT NULL
);


ALTER TABLE public.standard_report_card_type OWNER TO openchs;

--
-- Name: standard_report_card_type_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.standard_report_card_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.standard_report_card_type_id_seq OWNER TO openchs;

--
-- Name: standard_report_card_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.standard_report_card_type_id_seq OWNED BY public.standard_report_card_type.id;


--
-- Name: subject_migration; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.subject_migration (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    individual_id integer NOT NULL,
    old_address_level_id integer NOT NULL,
    new_address_level_id integer NOT NULL,
    organisation_id integer NOT NULL,
    audit_id integer NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    version integer NOT NULL
);


ALTER TABLE public.subject_migration OWNER TO openchs;

--
-- Name: subject_migration_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.subject_migration_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.subject_migration_id_seq OWNER TO openchs;

--
-- Name: subject_migration_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.subject_migration_id_seq OWNED BY public.subject_migration.id;


--
-- Name: subject_type; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.subject_type (
    id integer NOT NULL,
    uuid character varying(255),
    name character varying(255) NOT NULL,
    organisation_id bigint NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    audit_id bigint NOT NULL,
    version integer DEFAULT 1,
    is_group boolean DEFAULT false NOT NULL,
    is_household boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    type character varying(255),
    subject_summary_rule text,
    allow_empty_location boolean DEFAULT false NOT NULL,
    unique_name boolean DEFAULT false NOT NULL,
    valid_first_name_regex text,
    valid_first_name_description_key text,
    valid_last_name_regex text,
    valid_last_name_description_key text,
    icon_file_s3_key text
);


ALTER TABLE public.subject_type OWNER TO openchs;

--
-- Name: subject_type_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.subject_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.subject_type_id_seq OWNER TO openchs;

--
-- Name: subject_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.subject_type_id_seq OWNED BY public.subject_type.id;


--
-- Name: sync_telemetry; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.sync_telemetry (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    user_id integer NOT NULL,
    organisation_id bigint NOT NULL,
    version integer DEFAULT 1,
    sync_status character varying(255) NOT NULL,
    sync_start_time timestamp with time zone NOT NULL,
    sync_end_time timestamp with time zone,
    entity_status jsonb,
    device_name character varying(255),
    android_version character varying(255),
    app_version character varying(255),
    device_info jsonb,
    sync_source text
);


ALTER TABLE public.sync_telemetry OWNER TO openchs;

--
-- Name: sync_telemetry_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.sync_telemetry_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.sync_telemetry_id_seq OWNER TO openchs;

--
-- Name: sync_telemetry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.sync_telemetry_id_seq OWNED BY public.sync_telemetry.id;


--
-- Name: title_lineage_locations_view; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.title_lineage_locations_view AS
 SELECT title_lineage_locations_function.lowestpoint_id,
    title_lineage_locations_function.title_lineage
   FROM public.title_lineage_locations_function() title_lineage_locations_function(lowestpoint_id, title_lineage);


ALTER TABLE public.title_lineage_locations_view OWNER TO openchs;

--
-- Name: translation; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.translation (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    organisation_id bigint NOT NULL,
    audit_id bigint NOT NULL,
    version integer DEFAULT 1,
    translation_json jsonb NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    language character varying(255)
);


ALTER TABLE public.translation OWNER TO openchs;

--
-- Name: translation_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.translation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.translation_id_seq OWNER TO openchs;

--
-- Name: translation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.translation_id_seq OWNED BY public.translation.id;


--
-- Name: user_facility_mapping; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.user_facility_mapping (
    id integer NOT NULL,
    version integer DEFAULT 1 NOT NULL,
    audit_id bigint NOT NULL,
    uuid character varying(255) NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    organisation_id bigint NOT NULL,
    facility_id bigint NOT NULL,
    user_id bigint NOT NULL
);


ALTER TABLE public.user_facility_mapping OWNER TO openchs;

--
-- Name: user_facility_mapping_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.user_facility_mapping_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.user_facility_mapping_id_seq OWNER TO openchs;

--
-- Name: user_facility_mapping_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.user_facility_mapping_id_seq OWNED BY public.user_facility_mapping.id;


--
-- Name: user_group; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.user_group (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    user_id integer NOT NULL,
    group_id integer NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    version integer,
    organisation_id integer NOT NULL,
    audit_id integer
);


ALTER TABLE public.user_group OWNER TO openchs;

--
-- Name: user_group_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.user_group_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.user_group_id_seq OWNER TO openchs;

--
-- Name: user_group_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.user_group_id_seq OWNED BY public.user_group.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.users (
    id integer NOT NULL,
    uuid character varying(255) NOT NULL,
    username character varying(255) NOT NULL,
    organisation_id integer,
    created_by_id bigint DEFAULT 1 NOT NULL,
    last_modified_by_id bigint DEFAULT 1 NOT NULL,
    created_date_time timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_modified_date_time timestamp(3) with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    is_voided boolean DEFAULT false NOT NULL,
    catchment_id integer,
    is_org_admin boolean DEFAULT false NOT NULL,
    operating_individual_scope character varying(255) NOT NULL,
    settings jsonb,
    email character varying(320),
    phone_number character varying(32),
    disabled_in_cognito boolean DEFAULT false,
    name character varying(255),
    CONSTRAINT users_check CHECK ((((operating_individual_scope)::text <> 'ByCatchment'::text) OR (catchment_id IS NOT NULL)))
);


ALTER TABLE public.users OWNER TO openchs;

--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.users_id_seq OWNER TO openchs;

--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: video; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.video (
    id integer NOT NULL,
    version integer DEFAULT 1,
    audit_id bigint NOT NULL,
    uuid character varying(255),
    organisation_id bigint NOT NULL,
    title character varying(255) NOT NULL,
    file_path character varying(255) NOT NULL,
    description character varying(255),
    duration integer,
    is_voided boolean DEFAULT false NOT NULL
);


ALTER TABLE public.video OWNER TO openchs;

--
-- Name: video_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.video_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.video_id_seq OWNER TO openchs;

--
-- Name: video_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.video_id_seq OWNED BY public.video.id;


--
-- Name: video_telemetric; Type: TABLE; Schema: public; Owner: openchs
--

CREATE TABLE public.video_telemetric (
    id integer NOT NULL,
    uuid character varying(255),
    video_start_time double precision NOT NULL,
    video_end_time double precision NOT NULL,
    player_open_time timestamp with time zone NOT NULL,
    player_close_time timestamp with time zone NOT NULL,
    video_id integer NOT NULL,
    user_id integer NOT NULL,
    created_datetime timestamp with time zone NOT NULL,
    organisation_id integer NOT NULL,
    is_voided boolean DEFAULT false NOT NULL
);


ALTER TABLE public.video_telemetric OWNER TO openchs;

--
-- Name: video_telemetric_id_seq; Type: SEQUENCE; Schema: public; Owner: openchs
--

CREATE SEQUENCE public.video_telemetric_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.video_telemetric_id_seq OWNER TO openchs;

--
-- Name: video_telemetric_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: openchs
--

ALTER SEQUENCE public.video_telemetric_id_seq OWNED BY public.video_telemetric.id;


--
-- Name: virtual_catchment_address_mapping_table; Type: VIEW; Schema: public; Owner: openchs
--

CREATE VIEW public.virtual_catchment_address_mapping_table AS
 SELECT virtual_catchment_address_mapping_function.id,
    virtual_catchment_address_mapping_function.catchment_id,
    virtual_catchment_address_mapping_function.addresslevel_id
   FROM public.virtual_catchment_address_mapping_function() virtual_catchment_address_mapping_function(id, catchment_id, addresslevel_id);


ALTER TABLE public.virtual_catchment_address_mapping_table OWNER TO openchs;

--
-- Name: account id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.account ALTER COLUMN id SET DEFAULT nextval('public.account_id_seq'::regclass);


--
-- Name: account_admin id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.account_admin ALTER COLUMN id SET DEFAULT nextval('public.account_admin_id_seq'::regclass);


--
-- Name: address_level id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level ALTER COLUMN id SET DEFAULT nextval('public.address_level_id_seq'::regclass);


--
-- Name: address_level_type id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level_type ALTER COLUMN id SET DEFAULT nextval('public.address_level_type_id_seq'::regclass);


--
-- Name: approval_status id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.approval_status ALTER COLUMN id SET DEFAULT nextval('public.approval_status_id_seq'::regclass);


--
-- Name: audit id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.audit ALTER COLUMN id SET DEFAULT nextval('public.audit_id_seq'::regclass);


--
-- Name: catchment id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.catchment ALTER COLUMN id SET DEFAULT nextval('public.catchment_id_seq'::regclass);


--
-- Name: catchment_address_mapping id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.catchment_address_mapping ALTER COLUMN id SET DEFAULT nextval('public.catchment_address_mapping_id_seq'::regclass);


--
-- Name: checklist id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist ALTER COLUMN id SET DEFAULT nextval('public.checklist_id_seq'::regclass);


--
-- Name: checklist_detail id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_detail ALTER COLUMN id SET DEFAULT nextval('public.checklist_detail_id_seq'::regclass);


--
-- Name: checklist_item id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item ALTER COLUMN id SET DEFAULT nextval('public.checklist_item_id_seq'::regclass);


--
-- Name: checklist_item_detail id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item_detail ALTER COLUMN id SET DEFAULT nextval('public.checklist_item_detail_id_seq'::regclass);


--
-- Name: comment id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.comment ALTER COLUMN id SET DEFAULT nextval('public.comment_id_seq'::regclass);


--
-- Name: comment_thread id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.comment_thread ALTER COLUMN id SET DEFAULT nextval('public.comment_thread_id_seq'::regclass);


--
-- Name: concept id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept ALTER COLUMN id SET DEFAULT nextval('public.concept_id_seq'::regclass);


--
-- Name: concept_answer id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept_answer ALTER COLUMN id SET DEFAULT nextval('public.concept_answer_id_seq'::regclass);


--
-- Name: dashboard id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard ALTER COLUMN id SET DEFAULT nextval('public.dashboard_id_seq'::regclass);


--
-- Name: dashboard_card_mapping id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_card_mapping ALTER COLUMN id SET DEFAULT nextval('public.dashboard_card_mapping_id_seq'::regclass);


--
-- Name: dashboard_section id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section ALTER COLUMN id SET DEFAULT nextval('public.dashboard_section_id_seq'::regclass);


--
-- Name: dashboard_section_card_mapping id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section_card_mapping ALTER COLUMN id SET DEFAULT nextval('public.dashboard_section_card_mapping_id_seq'::regclass);


--
-- Name: decision_concept id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.decision_concept ALTER COLUMN id SET DEFAULT nextval('public.decision_concept_id_seq'::regclass);


--
-- Name: deps_saved_ddl deps_id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.deps_saved_ddl ALTER COLUMN deps_id SET DEFAULT nextval('public.deps_saved_ddl_deps_id_seq'::regclass);


--
-- Name: encounter id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter ALTER COLUMN id SET DEFAULT nextval('public.encounter_id_seq'::regclass);


--
-- Name: encounter_type id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter_type ALTER COLUMN id SET DEFAULT nextval('public.encounter_type_id_seq'::regclass);


--
-- Name: entity_approval_status id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.entity_approval_status ALTER COLUMN id SET DEFAULT nextval('public.entity_approval_status_id_seq'::regclass);


--
-- Name: facility id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.facility ALTER COLUMN id SET DEFAULT nextval('public.facility_id_seq'::regclass);


--
-- Name: form id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form ALTER COLUMN id SET DEFAULT nextval('public.form_id_seq'::regclass);


--
-- Name: form_element id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element ALTER COLUMN id SET DEFAULT nextval('public.form_element_id_seq'::regclass);


--
-- Name: form_element_group id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element_group ALTER COLUMN id SET DEFAULT nextval('public.form_element_group_id_seq'::regclass);


--
-- Name: form_mapping id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_mapping ALTER COLUMN id SET DEFAULT nextval('public.form_mapping_id_seq'::regclass);


--
-- Name: gender id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.gender ALTER COLUMN id SET DEFAULT nextval('public.gender_id_seq'::regclass);


--
-- Name: group_dashboard id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_dashboard ALTER COLUMN id SET DEFAULT nextval('public.group_dashboard_id_seq'::regclass);


--
-- Name: group_privilege id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_privilege ALTER COLUMN id SET DEFAULT nextval('public.group_privilege_id_seq'::regclass);


--
-- Name: group_role id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_role ALTER COLUMN id SET DEFAULT nextval('public.group_role_id_seq'::regclass);


--
-- Name: group_subject id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_subject ALTER COLUMN id SET DEFAULT nextval('public.group_subject_id_seq'::regclass);


--
-- Name: groups id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.groups ALTER COLUMN id SET DEFAULT nextval('public.groups_id_seq'::regclass);


--
-- Name: identifier_assignment id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_assignment ALTER COLUMN id SET DEFAULT nextval('public.identifier_assignment_id_seq'::regclass);


--
-- Name: identifier_source id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_source ALTER COLUMN id SET DEFAULT nextval('public.identifier_source_id_seq'::regclass);


--
-- Name: identifier_user_assignment id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_user_assignment ALTER COLUMN id SET DEFAULT nextval('public.identifier_user_assignment_id_seq'::regclass);


--
-- Name: individual id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual ALTER COLUMN id SET DEFAULT nextval('public.individual_id_seq'::regclass);


--
-- Name: individual_relation id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relation ALTER COLUMN id SET DEFAULT nextval('public.individual_relation_id_seq'::regclass);


--
-- Name: individual_relation_gender_mapping id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relation_gender_mapping ALTER COLUMN id SET DEFAULT nextval('public.individual_relation_gender_mapping_id_seq'::regclass);


--
-- Name: individual_relationship id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relationship ALTER COLUMN id SET DEFAULT nextval('public.individual_relationship_id_seq'::regclass);


--
-- Name: individual_relationship_type id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relationship_type ALTER COLUMN id SET DEFAULT nextval('public.individual_relationship_type_id_seq'::regclass);


--
-- Name: individual_relative id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relative ALTER COLUMN id SET DEFAULT nextval('public.individual_relative_id_seq'::regclass);


--
-- Name: location_location_mapping id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.location_location_mapping ALTER COLUMN id SET DEFAULT nextval('public.location_location_mapping_id_seq'::regclass);


--
-- Name: msg91_config id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.msg91_config ALTER COLUMN id SET DEFAULT nextval('public.msg91_config_id_seq'::regclass);


--
-- Name: news id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.news ALTER COLUMN id SET DEFAULT nextval('public.news_id_seq'::regclass);


--
-- Name: non_applicable_form_element id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.non_applicable_form_element ALTER COLUMN id SET DEFAULT nextval('public.non_applicable_form_element_id_seq'::regclass);


--
-- Name: operational_encounter_type id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_encounter_type ALTER COLUMN id SET DEFAULT nextval('public.operational_encounter_type_id_seq'::regclass);


--
-- Name: operational_program id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_program ALTER COLUMN id SET DEFAULT nextval('public.operational_program_id_seq'::regclass);


--
-- Name: operational_subject_type id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_subject_type ALTER COLUMN id SET DEFAULT nextval('public.operational_subject_type_id_seq'::regclass);


--
-- Name: organisation id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation ALTER COLUMN id SET DEFAULT nextval('public.organisation_id_seq'::regclass);


--
-- Name: organisation_config id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_config ALTER COLUMN id SET DEFAULT nextval('public.organisation_config_id_seq'::regclass);


--
-- Name: organisation_group id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_group ALTER COLUMN id SET DEFAULT nextval('public.organisation_group_id_seq'::regclass);


--
-- Name: organisation_group_organisation id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_group_organisation ALTER COLUMN id SET DEFAULT nextval('public.organisation_group_organisation_id_seq'::regclass);


--
-- Name: platform_translation id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.platform_translation ALTER COLUMN id SET DEFAULT nextval('public.platform_translation_id_seq'::regclass);


--
-- Name: privilege id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.privilege ALTER COLUMN id SET DEFAULT nextval('public.privilege_id_seq'::regclass);


--
-- Name: program id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program ALTER COLUMN id SET DEFAULT nextval('public.program_id_seq'::regclass);


--
-- Name: program_encounter id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_encounter ALTER COLUMN id SET DEFAULT nextval('public.program_encounter_id_seq'::regclass);


--
-- Name: program_enrolment id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_enrolment ALTER COLUMN id SET DEFAULT nextval('public.program_enrolment_id_seq'::regclass);


--
-- Name: program_organisation_config id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_organisation_config ALTER COLUMN id SET DEFAULT nextval('public.program_organisation_config_id_seq'::regclass);


--
-- Name: program_organisation_config_at_risk_concept id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_organisation_config_at_risk_concept ALTER COLUMN id SET DEFAULT nextval('public.program_organisation_config_at_risk_concept_id_seq'::regclass);


--
-- Name: program_outcome id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_outcome ALTER COLUMN id SET DEFAULT nextval('public.program_outcome_id_seq'::regclass);


--
-- Name: report_card id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.report_card ALTER COLUMN id SET DEFAULT nextval('public.report_card_id_seq'::regclass);


--
-- Name: rule id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule ALTER COLUMN id SET DEFAULT nextval('public.rule_id_seq'::regclass);


--
-- Name: rule_dependency id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule_dependency ALTER COLUMN id SET DEFAULT nextval('public.rule_dependency_id_seq'::regclass);


--
-- Name: rule_failure_log id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule_failure_log ALTER COLUMN id SET DEFAULT nextval('public.rule_failure_log_id_seq'::regclass);


--
-- Name: rule_failure_telemetry id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule_failure_telemetry ALTER COLUMN id SET DEFAULT nextval('public.rule_failure_telemetry_id_seq'::regclass);


--
-- Name: standard_report_card_type id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.standard_report_card_type ALTER COLUMN id SET DEFAULT nextval('public.standard_report_card_type_id_seq'::regclass);


--
-- Name: subject_migration id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.subject_migration ALTER COLUMN id SET DEFAULT nextval('public.subject_migration_id_seq'::regclass);


--
-- Name: subject_type id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.subject_type ALTER COLUMN id SET DEFAULT nextval('public.subject_type_id_seq'::regclass);


--
-- Name: sync_telemetry id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.sync_telemetry ALTER COLUMN id SET DEFAULT nextval('public.sync_telemetry_id_seq'::regclass);


--
-- Name: translation id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.translation ALTER COLUMN id SET DEFAULT nextval('public.translation_id_seq'::regclass);


--
-- Name: user_facility_mapping id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.user_facility_mapping ALTER COLUMN id SET DEFAULT nextval('public.user_facility_mapping_id_seq'::regclass);


--
-- Name: user_group id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.user_group ALTER COLUMN id SET DEFAULT nextval('public.user_group_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: video id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.video ALTER COLUMN id SET DEFAULT nextval('public.video_id_seq'::regclass);


--
-- Name: video_telemetric id; Type: DEFAULT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.video_telemetric ALTER COLUMN id SET DEFAULT nextval('public.video_telemetric_id_seq'::regclass);


--
-- Data for Name: account; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.account (id, name) FROM stdin;
1	default
\.


--
-- Data for Name: account_admin; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.account_admin (id, name, account_id, admin_id) FROM stdin;
1	Samanvay	1	1
\.


--
-- Data for Name: address_level; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.address_level (id, title, uuid, version, organisation_id, audit_id, is_voided, type_id, lineage, parent_id, gps_coordinates, location_properties) FROM stdin;
1	Uttarakhand	a09bbfc4-5b23-4d5b-b683-48039bdaa7b4	0	2	91	f	1	1	\N	\N	\N
\.


--
-- Data for Name: address_level_type; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.address_level_type (id, uuid, name, is_voided, organisation_id, version, audit_id, level, parent_id) FROM stdin;
1	5b090e45-25b8-4240-8c80-cec3fc3b397c	State	f	2	0	90	1	\N
\.


--
-- Data for Name: approval_status; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.approval_status (id, uuid, status, is_voided, created_date_time, last_modified_date_time) FROM stdin;
1	e7e3cdc6-510c-43e3-81d7-85450ce66ba0	Pending	f	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.092+05:30
2	db5ce7a3-0b21-4f5b-807c-814dd96ebc1d	Approved	f	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.093+05:30
3	2c2cdf95-ed0d-4328-9431-14d65a6e82e6	Rejected	f	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.094+05:30
\.


--
-- Data for Name: audit; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.audit (id, uuid, created_by_id, last_modified_by_id, created_date_time, last_modified_date_time) FROM stdin;
1	483be0b2-b6ba-40e0-8bf7-91cb33c6e284	1	1	2021-11-14 16:23:08.170571+05:30	2021-11-14 10:53:09.899+05:30
2	7038d549-4a3b-4600-b856-f6f3d123fbd8	1	1	2021-11-14 16:23:08.170571+05:30	2021-11-14 10:53:09.899+05:30
3	09e1b06f-26be-4f7a-8121-5dba3a11b684	1	1	2021-11-14 16:23:08.170571+05:30	2021-11-14 10:53:09.899+05:30
4	d56700ea-fac8-4255-8403-7f8f3b755335	1	1	2021-11-14 16:23:08.170571+05:30	2021-11-14 10:53:09.899+05:30
5	fd630fa3-7122-40b5-9a4c-12bfe7a314e0	1	1	2021-11-14 16:23:08.170571+05:30	2021-11-14 10:53:09.899+05:30
6	f6532996-a377-48f4-aafc-2e044ad9b1e2	1	1	2021-11-14 16:23:08.170571+05:30	2021-11-14 10:53:09.899+05:30
7	e033664f-458c-4698-8090-152ee7fb4cd7	1	1	2021-11-14 16:23:08.170571+05:30	2021-11-14 10:53:09.899+05:30
8	ad7d1d14-54fd-45a2-86b7-ea329b744484	1	1	2021-11-14 16:23:08.170571+05:30	2021-11-14 10:53:09.899+05:30
9	840de9fb-e565-4d7d-b751-90335ba20490	1	1	2021-11-14 16:23:08.170571+05:30	2021-11-14 10:53:09.899+05:30
10	188ad77e-fe46-4328-b0e2-98f3a05c554c	1	1	2021-11-14 16:23:08.170571+05:30	2021-11-14 10:53:09.899+05:30
11	5fed2907-df3a-4867-aef5-c87f4c78a31a	1	1	2021-11-14 16:23:08.170571+05:30	2021-11-14 10:53:09.899+05:30
12	ade34813-dbfb-44a9-bed0-534cecbaccf2	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
13	7a12cef2-febd-44e4-91f9-c6b8945d5962	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
14	0fdf6781-698a-4b7a-bcc9-f622e078c41d	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
15	30ce916b-557d-4cd4-a3fd-b3154a8b594c	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
16	f8b7576e-01bc-46d2-a01e-40b260e8e8ed	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
17	89619c86-e603-4856-af49-bd6b2658f176	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
18	9c303777-2e18-4d54-9ae1-53cab97893e7	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
19	1b0789e2-b017-4cfb-817a-9e0cddd2509e	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
20	b7c4a7f6-0b40-4bdc-a489-7d0b9c82d6e3	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
21	6b5114c9-2d57-47b6-ad3e-1846c264c229	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
22	7d1d6931-7af9-4e10-9ece-dd1e44bb4574	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
23	aae67acd-c1e1-494b-b286-e87e544a3cb4	1	1	2021-11-14 16:23:08.395598+05:30	2021-11-14 10:53:09.899+05:30
24	c4ab0751-5b59-4dda-bc9a-4c2088c34f10	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
25	50357d3f-674b-40e3-82e3-dbea0100924b	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
26	48053ccf-d22a-4e52-b38d-9ba00ea17ab5	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
27	bcd2273e-09a5-484d-a5ed-be425a86944f	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
28	4be076f9-f99a-4d19-b806-17e1da29280a	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
29	dd5c3255-e0c1-48dd-9815-bee3ec9c03d0	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
30	830585a0-de1c-41f7-94c8-f003926f5bf9	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
31	d98c51be-b928-431b-acc5-b35dc47a3bee	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
32	e2ca259e-2993-4cef-8f37-9b26ddf39962	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
33	ac12b0f4-4b07-4fcc-95d0-b32430bab2a1	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
34	d3fb028a-e9c3-450b-965e-4309bd86f414	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
35	b47f4b3d-5571-4bcf-8942-cb67a61f7735	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
36	f76141b5-6bb7-4892-bf69-11c6b4dfedc1	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
37	93b29ce9-cfa6-4882-8a82-c34779525aa9	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
38	916b476d-c09c-4628-8673-cfe4db6785c5	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
39	d7b67bd6-0ec3-4f1e-9112-d5b957cabde6	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
40	b90ee1ce-b5bb-4b0a-b6cc-76384971acfb	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
41	0bdcb7d3-cc2b-4a2c-8726-c7080587cf7f	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
42	083b3393-9f46-4ab1-b544-456d3db602ed	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
43	6dc70f3d-51b4-4dee-a2d5-6a7a52beff16	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
44	8103bdf8-b22a-4f4b-b226-52436c205bed	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
45	5564fbbb-ccca-4ebe-bb15-909c9ebd19f1	1	1	2021-11-14 16:23:08.438957+05:30	2021-11-14 10:53:09.899+05:30
46	7e876220-20b4-4c17-87b7-0e235926f7a6	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
47	91fd32f2-0261-46a1-92e4-4c201247c9a3	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
48	eeb49484-a07d-49f7-bb4b-932b713fbc66	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
49	5a77c22b-a24f-456e-84a3-9bd12e104f73	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
50	334ea293-fd10-4dab-92f3-04ce153e27aa	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
51	0ab14ce3-cbdb-4cb7-8601-353bebe408c9	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
52	4809d13f-4ab1-49d7-aa57-ee71a821bc3f	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
53	a081882c-6775-4caa-98cd-9720a0d11dfc	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
54	4474c0f3-9d35-4622-a65a-5688f633a274	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
55	82691c26-c042-48d4-972b-664bcb348fc4	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
56	0d0b0e92-79d4-49c1-b33b-cf0508ea550c	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
57	8c382726-92be-4e3e-8b6e-2b032c5cd6a8	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
58	f6e6f570-aaaf-4069-a14d-e2649e9710d7	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
59	2eb6adbc-5a55-46f8-925e-f3061fd16e29	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
60	7c97fe3b-c2e8-437d-a43b-1e6d4357a8d1	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
61	1896f28c-cace-4034-bf29-c0ab42a4c41e	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
62	f2916111-b753-4004-85d5-a63856ce4462	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
63	ec90bb6f-2ccb-4e4c-be01-ae95cc441b98	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
64	ac49854a-776d-4311-9b13-c536b97e0c48	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
65	90de5a8a-cbbc-4bab-8019-edf3f1d02317	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
66	0dff0a2b-ac07-4c31-8338-c32af05b31fc	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
67	db89d727-3c3e-45fc-a18d-a58c3098d5ca	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
68	50a3aa9e-04be-465f-be7b-22e0ab8e500e	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
69	29b20f70-6b3e-481e-96cf-c4fe0e2d46c1	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
70	1d9c019a-9350-44f9-9ef9-a699f0d94a13	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
71	1db2a945-0692-481e-a68c-aaf7cc246d64	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
72	d84d15c2-3d09-416e-8c26-9709ce3c90da	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
73	99ad5750-bdf8-40e6-964c-01cf806707b7	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
74	89d85d58-de14-4249-b9bb-61d4abb94b77	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
75	2a6a496c-6063-4383-8857-0c10a831d85c	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
85	\N	1	1	2021-11-14 10:58:04.886+05:30	2021-11-14 10:58:04.886+05:30
76	3731d4b6-80f4-410b-baf7-2c0fcc38fe1f	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
77	765bc1ed-441a-414d-b62a-672103b35c95	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
78	8458bbe3-aa87-4c7c-b5e2-a139e01bd88f	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
79	1724ff11-95c5-42c2-b697-f40f1105d696	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
80	28edbf6e-98eb-4218-8950-01d97be476da	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
81	ace301c1-2815-42c1-943e-c7b44f64b376	1	1	2021-11-14 16:23:08.495153+05:30	2021-11-14 10:53:09.899+05:30
82	\N	1	1	2021-11-14 10:53:10.101586+05:30	2021-11-14 10:53:10.102+05:30
83	\N	1	1	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:12.563+05:30
84	\N	1	1	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:12.563+05:30
86	\N	1	1	2021-11-14 10:58:04.902+05:30	2021-11-14 10:58:04.902+05:30
87	\N	1	1	2021-11-14 10:58:04.904+05:30	2021-11-14 10:58:04.904+05:30
88	\N	1	1	2021-11-14 10:58:04.912+05:30	2021-11-14 10:58:04.912+05:30
131	\N	1	1	2021-11-14 11:03:21.568+05:30	2021-11-14 11:03:58.794+05:30
132	\N	1	1	2021-11-14 11:03:21.583+05:30	2021-11-14 11:03:58.794+05:30
537	\N	1	1	2021-11-14 11:04:55.992+05:30	2021-11-14 11:04:55.992+05:30
90	\N	1	1	2021-11-14 10:58:22.061+05:30	2021-11-14 10:58:22.061+05:30
91	\N	1	1	2021-11-14 10:58:31.897+05:30	2021-11-14 10:58:31.949+05:30
92	\N	1	1	2021-11-14 10:58:38.489+05:30	2021-11-14 10:58:38.489+05:30
93	\N	1	1	2021-11-14 10:59:13.872+05:30	2021-11-14 10:59:13.872+05:30
94	\N	1	1	2021-11-14 10:59:40.342+05:30	2021-11-14 10:59:40.342+05:30
95	\N	1	1	2021-11-14 10:59:40.35+05:30	2021-11-14 10:59:40.35+05:30
97	\N	1	1	2021-11-14 10:59:40.398+05:30	2021-11-14 10:59:40.398+05:30
540	\N	1	1	2021-11-14 11:05:51.59+05:30	2021-11-14 11:05:51.59+05:30
99	\N	1	1	2021-11-14 11:00:05.297+05:30	2021-11-14 11:00:05.297+05:30
100	\N	1	1	2021-11-14 11:00:05.301+05:30	2021-11-14 11:00:05.301+05:30
98	\N	1	1	2021-11-14 11:00:05.278+05:30	2021-11-14 11:00:05.304+05:30
101	\N	1	1	2021-11-14 11:00:05.309+05:30	2021-11-14 11:00:05.309+05:30
103	\N	1	1	2021-11-14 11:00:05.336+05:30	2021-11-14 11:00:05.336+05:30
546	\N	1	1	2021-11-14 11:06:27.434+05:30	2021-11-14 11:06:27.434+05:30
547	\N	1	1	2021-11-14 11:06:27.458+05:30	2021-11-14 11:06:27.458+05:30
106	\N	1	1	2021-11-14 11:03:21.431+05:30	2021-11-14 11:03:21.431+05:30
107	\N	1	1	2021-11-14 11:03:21.434+05:30	2021-11-14 11:03:21.434+05:30
548	\N	1	1	2021-11-14 11:06:27.459+05:30	2021-11-14 11:06:27.459+05:30
109	\N	1	1	2021-11-14 11:03:21.463+05:30	2021-11-14 11:03:21.463+05:30
110	\N	1	1	2021-11-14 11:03:21.466+05:30	2021-11-14 11:03:21.466+05:30
111	\N	1	1	2021-11-14 11:03:21.469+05:30	2021-11-14 11:03:21.469+05:30
112	\N	1	1	2021-11-14 11:03:21.472+05:30	2021-11-14 11:03:21.472+05:30
113	\N	1	1	2021-11-14 11:03:21.474+05:30	2021-11-14 11:03:21.474+05:30
114	\N	1	1	2021-11-14 11:03:21.477+05:30	2021-11-14 11:03:21.477+05:30
115	\N	1	1	2021-11-14 11:03:21.479+05:30	2021-11-14 11:03:21.479+05:30
116	\N	1	1	2021-11-14 11:03:21.482+05:30	2021-11-14 11:03:21.482+05:30
117	\N	1	1	2021-11-14 11:03:21.485+05:30	2021-11-14 11:03:21.485+05:30
118	\N	1	1	2021-11-14 11:03:21.488+05:30	2021-11-14 11:03:21.488+05:30
119	\N	1	1	2021-11-14 11:03:21.491+05:30	2021-11-14 11:03:21.491+05:30
120	\N	1	1	2021-11-14 11:03:21.493+05:30	2021-11-14 11:03:21.493+05:30
121	\N	1	1	2021-11-14 11:03:21.496+05:30	2021-11-14 11:03:21.496+05:30
122	\N	1	1	2021-11-14 11:03:21.499+05:30	2021-11-14 11:03:21.499+05:30
123	\N	1	1	2021-11-14 11:03:21.502+05:30	2021-11-14 11:03:21.502+05:30
549	\N	1	1	2021-11-14 11:06:27.461+05:30	2021-11-14 11:06:27.461+05:30
550	\N	1	1	2021-11-14 11:06:33.387+05:30	2021-11-14 11:06:33.387+05:30
551	\N	1	1	2021-11-14 11:06:33.395+05:30	2021-11-14 11:06:33.395+05:30
552	\N	1	1	2021-11-14 11:06:33.4+05:30	2021-11-14 11:06:33.4+05:30
553	\N	1	1	2021-11-14 11:06:33.423+05:30	2021-11-14 11:06:33.423+05:30
96	\N	1	1	2021-11-14 10:59:40.359+05:30	2021-11-14 11:06:33.428+05:30
558	\N	1	1	2021-11-14 11:07:56.343+05:30	2021-11-14 11:07:56.343+05:30
559	\N	1	1	2021-11-14 11:07:56.343+05:30	2021-11-14 11:07:56.343+05:30
102	\N	1	1	2021-11-14 11:00:05.314+05:30	2021-11-14 11:08:05.332+05:30
585	\N	1	1	2021-11-14 11:10:13.901+05:30	2021-11-14 11:10:13.901+05:30
586	\N	1	1	2021-11-14 11:10:13.903+05:30	2021-11-14 11:10:13.903+05:30
587	\N	1	1	2021-11-14 11:10:13.904+05:30	2021-11-14 11:10:13.904+05:30
588	\N	1	1	2021-11-14 11:10:41.575+05:30	2021-11-14 11:10:41.575+05:30
589	\N	1	1	2021-11-14 11:10:41.579+05:30	2021-11-14 11:10:41.579+05:30
590	\N	1	1	2021-11-14 11:10:41.584+05:30	2021-11-14 11:10:41.584+05:30
591	\N	1	1	2021-11-14 11:10:41.607+05:30	2021-11-14 11:10:41.607+05:30
592	\N	1	1	2021-11-14 11:11:31.789+05:30	2021-11-14 11:11:31.789+05:30
593	\N	1	1	2021-11-14 11:11:54.284+05:30	2021-11-14 11:11:54.284+05:30
594	\N	1	1	2021-11-14 11:12:20.545+05:30	2021-11-14 11:12:20.545+05:30
595	\N	1	1	2021-11-14 11:12:43.734+05:30	2021-11-14 11:12:43.734+05:30
596	\N	1	1	2021-11-14 11:13:49.045+05:30	2021-11-14 11:13:49.045+05:30
597	\N	1	1	2021-11-14 11:13:49.048+05:30	2021-11-14 11:13:49.048+05:30
598	\N	1	1	2021-11-14 11:13:49.049+05:30	2021-11-14 11:13:49.049+05:30
599	\N	1	1	2021-11-14 11:13:55.849+05:30	2021-11-14 11:13:55.849+05:30
600	\N	1	1	2021-11-14 11:13:55.852+05:30	2021-11-14 11:13:55.852+05:30
601	\N	1	1	2021-11-14 11:13:55.855+05:30	2021-11-14 11:13:55.855+05:30
602	\N	1	1	2021-11-14 11:13:55.858+05:30	2021-11-14 11:13:55.858+05:30
603	\N	1	1	2021-11-14 11:13:55.861+05:30	2021-11-14 11:13:55.861+05:30
604	\N	1	1	2021-11-14 11:13:55.885+05:30	2021-11-14 11:13:55.885+05:30
605	\N	1	1	2021-11-14 11:14:09.981+05:30	2021-11-14 11:14:09.981+05:30
606	\N	1	1	2021-11-14 11:14:09.985+05:30	2021-11-14 11:14:09.985+05:30
608	\N	1	1	2021-11-14 11:14:10.018+05:30	2021-11-14 11:14:10.018+05:30
609	\N	1	1	2021-11-14 11:14:10.022+05:30	2021-11-14 11:14:10.022+05:30
610	\N	1	1	2021-11-14 11:14:10.037+05:30	2021-11-14 11:14:10.037+05:30
611	\N	1	1	2021-11-14 11:14:45.814+05:30	2021-11-14 11:14:45.814+05:30
612	\N	1	1	2021-11-14 11:14:45.817+05:30	2021-11-14 11:14:45.817+05:30
613	\N	1	1	2021-11-14 11:14:45.84+05:30	2021-11-14 11:14:45.84+05:30
607	\N	1	1	2021-11-14 11:14:09.991+05:30	2021-11-14 11:14:45.844+05:30
538	\N	1	1	2021-11-14 11:05:51.587+05:30	2021-11-14 11:05:51.587+05:30
554	\N	1	1	2021-11-14 11:07:05.174+05:30	2021-11-14 11:07:05.174+05:30
556	\N	1	1	2021-11-14 11:07:56.342+05:30	2021-11-14 11:07:56.342+05:30
560	\N	1	1	2021-11-14 11:07:56.345+05:30	2021-11-14 11:07:56.345+05:30
561	\N	1	1	2021-11-14 11:07:56.404+05:30	2021-11-14 11:07:56.404+05:30
562	\N	1	1	2021-11-14 11:07:56.407+05:30	2021-11-14 11:07:56.407+05:30
563	\N	1	1	2021-11-14 11:07:56.41+05:30	2021-11-14 11:07:56.41+05:30
564	\N	1	1	2021-11-14 11:07:56.412+05:30	2021-11-14 11:07:56.412+05:30
565	\N	1	1	2021-11-14 11:07:56.414+05:30	2021-11-14 11:07:56.414+05:30
566	\N	1	1	2021-11-14 11:07:56.416+05:30	2021-11-14 11:07:56.416+05:30
567	\N	1	1	2021-11-14 11:07:56.417+05:30	2021-11-14 11:07:56.417+05:30
568	\N	1	1	2021-11-14 11:08:05.3+05:30	2021-11-14 11:08:05.3+05:30
569	\N	1	1	2021-11-14 11:08:05.302+05:30	2021-11-14 11:08:05.302+05:30
570	\N	1	1	2021-11-14 11:08:05.327+05:30	2021-11-14 11:08:05.327+05:30
577	\N	1	1	2021-11-14 11:08:55.408+05:30	2021-11-14 11:08:55.408+05:30
578	\N	1	1	2021-11-14 11:08:55.414+05:30	2021-11-14 11:08:55.414+05:30
580	\N	1	1	2021-11-14 11:08:55.456+05:30	2021-11-14 11:08:55.456+05:30
581	\N	1	1	2021-11-14 11:08:55.464+05:30	2021-11-14 11:08:55.464+05:30
582	\N	1	1	2021-11-14 11:08:55.49+05:30	2021-11-14 11:08:55.49+05:30
579	\N	1	1	2021-11-14 11:08:55.42+05:30	2021-11-14 11:13:55.889+05:30
721	\N	2	2	2021-11-14 11:32:59.286+05:30	2021-11-14 11:32:59.286+05:30
722	\N	2	2	2021-11-14 11:32:59.326+05:30	2021-11-14 11:32:59.326+05:30
723	\N	2	2	2021-11-14 11:32:59.365+05:30	2021-11-14 11:32:59.365+05:30
724	\N	2	2	2021-11-14 11:32:59.405+05:30	2021-11-14 11:32:59.405+05:30
725	\N	2	2	2021-11-14 11:32:59.443+05:30	2021-11-14 11:32:59.443+05:30
726	\N	2	2	2021-11-14 11:32:59.482+05:30	2021-11-14 11:32:59.482+05:30
727	\N	2	2	2021-11-14 11:32:59.519+05:30	2021-11-14 11:32:59.519+05:30
728	\N	2	2	2021-11-14 11:32:59.553+05:30	2021-11-14 11:32:59.553+05:30
729	\N	2	2	2021-11-14 11:32:59.587+05:30	2021-11-14 11:32:59.587+05:30
730	\N	2	2	2021-11-14 11:32:59.62+05:30	2021-11-14 11:32:59.62+05:30
731	\N	2	2	2021-11-14 11:32:59.654+05:30	2021-11-14 11:32:59.654+05:30
732	\N	2	2	2021-11-14 11:32:59.688+05:30	2021-11-14 11:32:59.688+05:30
733	\N	2	2	2021-11-14 11:32:59.722+05:30	2021-11-14 11:32:59.722+05:30
734	\N	2	2	2021-11-14 11:32:59.757+05:30	2021-11-14 11:32:59.757+05:30
735	\N	2	2	2021-11-14 11:32:59.795+05:30	2021-11-14 11:32:59.795+05:30
736	\N	2	2	2021-11-14 11:32:59.835+05:30	2021-11-14 11:32:59.835+05:30
737	\N	2	2	2021-11-14 11:32:59.873+05:30	2021-11-14 11:32:59.873+05:30
738	\N	2	2	2021-11-14 11:32:59.907+05:30	2021-11-14 11:32:59.907+05:30
739	\N	2	2	2021-11-14 11:32:59.941+05:30	2021-11-14 11:32:59.941+05:30
740	\N	2	2	2021-11-14 11:32:59.975+05:30	2021-11-14 11:32:59.975+05:30
741	\N	2	2	2021-11-14 11:33:00.01+05:30	2021-11-14 11:33:00.01+05:30
742	\N	2	2	2021-11-14 11:33:00.044+05:30	2021-11-14 11:33:00.044+05:30
743	\N	2	2	2021-11-14 11:33:00.08+05:30	2021-11-14 11:33:00.08+05:30
744	\N	2	2	2021-11-14 11:33:00.117+05:30	2021-11-14 11:33:00.117+05:30
745	\N	2	2	2021-11-14 11:33:00.165+05:30	2021-11-14 11:33:00.165+05:30
746	\N	2	2	2021-11-14 11:33:00.206+05:30	2021-11-14 11:33:00.206+05:30
747	\N	2	2	2021-11-14 11:33:00.245+05:30	2021-11-14 11:33:00.245+05:30
748	\N	2	2	2021-11-14 11:33:00.281+05:30	2021-11-14 11:33:00.281+05:30
749	\N	2	2	2021-11-14 11:33:00.314+05:30	2021-11-14 11:33:00.314+05:30
750	\N	2	2	2021-11-14 11:33:00.352+05:30	2021-11-14 11:33:00.352+05:30
751	\N	2	2	2021-11-14 11:33:00.393+05:30	2021-11-14 11:33:00.393+05:30
752	\N	2	2	2021-11-14 11:33:00.427+05:30	2021-11-14 11:33:00.427+05:30
753	\N	2	2	2021-11-14 11:33:00.461+05:30	2021-11-14 11:33:00.461+05:30
754	\N	2	2	2021-11-14 11:33:00.494+05:30	2021-11-14 11:33:00.494+05:30
755	\N	2	2	2021-11-14 11:33:00.528+05:30	2021-11-14 11:33:00.528+05:30
756	\N	2	2	2021-11-14 11:33:00.562+05:30	2021-11-14 11:33:00.562+05:30
757	\N	2	2	2021-11-14 11:33:00.596+05:30	2021-11-14 11:33:00.596+05:30
758	\N	2	2	2021-11-14 11:33:00.63+05:30	2021-11-14 11:33:00.63+05:30
759	\N	2	2	2021-11-14 11:33:00.664+05:30	2021-11-14 11:33:00.664+05:30
760	\N	2	2	2021-11-14 11:33:00.698+05:30	2021-11-14 11:33:00.698+05:30
761	\N	2	2	2021-11-14 11:33:00.732+05:30	2021-11-14 11:33:00.732+05:30
762	\N	2	2	2021-11-14 11:33:00.766+05:30	2021-11-14 11:33:00.766+05:30
763	\N	2	2	2021-11-14 11:33:00.801+05:30	2021-11-14 11:33:00.801+05:30
764	\N	2	2	2021-11-14 11:33:00.834+05:30	2021-11-14 11:33:00.834+05:30
765	\N	2	2	2021-11-14 11:33:00.868+05:30	2021-11-14 11:33:00.868+05:30
766	\N	2	2	2021-11-14 11:33:00.903+05:30	2021-11-14 11:33:00.903+05:30
767	\N	2	2	2021-11-14 11:33:00.938+05:30	2021-11-14 11:33:00.938+05:30
768	\N	2	2	2021-11-14 11:33:00.975+05:30	2021-11-14 11:33:00.975+05:30
769	\N	2	2	2021-11-14 11:33:01.012+05:30	2021-11-14 11:33:01.012+05:30
770	\N	2	2	2021-11-14 11:33:01.055+05:30	2021-11-14 11:33:01.055+05:30
771	\N	2	2	2021-11-14 11:33:01.097+05:30	2021-11-14 11:33:01.097+05:30
772	\N	2	2	2021-11-14 11:33:01.138+05:30	2021-11-14 11:33:01.138+05:30
773	\N	2	2	2021-11-14 11:33:01.176+05:30	2021-11-14 11:33:01.176+05:30
774	\N	2	2	2021-11-14 11:33:01.209+05:30	2021-11-14 11:33:01.209+05:30
775	\N	2	2	2021-11-14 11:33:01.242+05:30	2021-11-14 11:33:01.242+05:30
776	\N	2	2	2021-11-14 11:33:01.276+05:30	2021-11-14 11:33:01.276+05:30
777	\N	2	2	2021-11-14 11:33:01.309+05:30	2021-11-14 11:33:01.309+05:30
778	\N	2	2	2021-11-14 11:33:01.348+05:30	2021-11-14 11:33:01.348+05:30
779	\N	2	2	2021-11-14 11:33:01.388+05:30	2021-11-14 11:33:01.388+05:30
780	\N	2	2	2021-11-14 11:33:01.433+05:30	2021-11-14 11:33:01.433+05:30
781	\N	2	2	2021-11-14 11:33:01.475+05:30	2021-11-14 11:33:01.475+05:30
782	\N	2	2	2021-11-14 11:33:01.512+05:30	2021-11-14 11:33:01.512+05:30
783	\N	2	2	2021-11-14 11:33:01.551+05:30	2021-11-14 11:33:01.551+05:30
784	\N	2	2	2021-11-14 11:33:01.59+05:30	2021-11-14 11:33:01.59+05:30
785	\N	2	2	2021-11-14 11:33:01.628+05:30	2021-11-14 11:33:01.628+05:30
786	\N	2	2	2021-11-14 11:33:01.663+05:30	2021-11-14 11:33:01.663+05:30
787	\N	2	2	2021-11-14 11:33:01.703+05:30	2021-11-14 11:33:01.703+05:30
788	\N	2	2	2021-11-14 11:33:01.744+05:30	2021-11-14 11:33:01.744+05:30
789	\N	2	2	2021-11-14 11:33:01.8+05:30	2021-11-14 11:33:01.8+05:30
790	\N	2	2	2021-11-14 11:33:01.839+05:30	2021-11-14 11:33:01.839+05:30
791	\N	2	2	2021-11-14 11:33:01.88+05:30	2021-11-14 11:33:01.88+05:30
792	\N	2	2	2021-11-14 11:33:01.921+05:30	2021-11-14 11:33:01.921+05:30
793	\N	2	2	2021-11-14 11:33:01.959+05:30	2021-11-14 11:33:01.959+05:30
794	\N	2	2	2021-11-14 11:33:01.997+05:30	2021-11-14 11:33:01.997+05:30
795	\N	2	2	2021-11-14 11:33:02.033+05:30	2021-11-14 11:33:02.033+05:30
796	\N	2	2	2021-11-14 11:33:02.072+05:30	2021-11-14 11:33:02.072+05:30
797	\N	2	2	2021-11-14 11:33:02.11+05:30	2021-11-14 11:33:02.11+05:30
798	\N	2	2	2021-11-14 11:33:02.154+05:30	2021-11-14 11:33:02.154+05:30
799	\N	2	2	2021-11-14 11:33:02.194+05:30	2021-11-14 11:33:02.194+05:30
859	\N	2	2	2021-11-14 11:50:31.253+05:30	2021-11-14 11:50:31.253+05:30
860	\N	2	2	2021-11-14 11:50:31.304+05:30	2021-11-14 11:50:31.304+05:30
861	\N	2	2	2021-11-14 11:50:31.351+05:30	2021-11-14 11:50:31.351+05:30
862	\N	2	2	2021-11-14 11:50:31.389+05:30	2021-11-14 11:50:31.389+05:30
863	\N	2	2	2021-11-14 11:50:31.427+05:30	2021-11-14 11:50:31.427+05:30
864	\N	2	2	2021-11-14 11:50:31.463+05:30	2021-11-14 11:50:31.463+05:30
865	\N	2	2	2021-11-14 11:50:31.5+05:30	2021-11-14 11:50:31.5+05:30
866	\N	2	2	2021-11-14 11:50:31.536+05:30	2021-11-14 11:50:31.536+05:30
867	\N	2	2	2021-11-14 11:50:31.571+05:30	2021-11-14 11:50:31.571+05:30
868	\N	2	2	2021-11-14 11:50:31.604+05:30	2021-11-14 11:50:31.604+05:30
869	\N	2	2	2021-11-14 11:50:31.637+05:30	2021-11-14 11:50:31.637+05:30
870	\N	2	2	2021-11-14 11:50:31.67+05:30	2021-11-14 11:50:31.67+05:30
871	\N	2	2	2021-11-14 11:50:31.76+05:30	2021-11-14 11:50:31.76+05:30
872	\N	2	2	2021-11-14 11:50:31.802+05:30	2021-11-14 11:50:31.802+05:30
873	\N	2	2	2021-11-14 11:50:31.837+05:30	2021-11-14 11:50:31.837+05:30
874	\N	2	2	2021-11-14 11:50:31.871+05:30	2021-11-14 11:50:31.871+05:30
875	\N	2	2	2021-11-14 11:50:31.904+05:30	2021-11-14 11:50:31.904+05:30
876	\N	2	2	2021-11-14 11:50:31.937+05:30	2021-11-14 11:50:31.937+05:30
877	\N	2	2	2021-11-14 11:50:31.972+05:30	2021-11-14 11:50:31.972+05:30
878	\N	2	2	2021-11-14 11:50:32.006+05:30	2021-11-14 11:50:32.006+05:30
539	\N	1	1	2021-11-14 11:05:51.588+05:30	2021-11-14 11:05:51.588+05:30
541	\N	1	1	2021-11-14 11:05:51.613+05:30	2021-11-14 11:05:51.613+05:30
542	\N	1	1	2021-11-14 11:05:51.615+05:30	2021-11-14 11:05:51.615+05:30
543	\N	1	1	2021-11-14 11:05:51.616+05:30	2021-11-14 11:05:51.616+05:30
544	\N	1	1	2021-11-14 11:05:51.618+05:30	2021-11-14 11:05:51.618+05:30
545	\N	1	1	2021-11-14 11:06:27.433+05:30	2021-11-14 11:06:27.433+05:30
555	\N	1	1	2021-11-14 11:07:56.331+05:30	2021-11-14 11:07:56.331+05:30
614	\N	1	1	2021-11-14 11:16:37.338+05:30	2021-11-14 11:16:37.338+05:30
615	\N	1	1	2021-11-14 11:16:37.342+05:30	2021-11-14 11:16:37.342+05:30
617	\N	1	1	2021-11-14 11:16:37.375+05:30	2021-11-14 11:16:37.375+05:30
618	\N	1	1	2021-11-14 11:16:37.38+05:30	2021-11-14 11:16:37.38+05:30
619	\N	1	1	2021-11-14 11:16:37.405+05:30	2021-11-14 11:16:37.405+05:30
620	\N	1	1	2021-11-14 11:17:20.715+05:30	2021-11-14 11:17:20.715+05:30
621	\N	1	1	2021-11-14 11:17:20.717+05:30	2021-11-14 11:17:20.717+05:30
622	\N	1	1	2021-11-14 11:17:20.718+05:30	2021-11-14 11:17:20.718+05:30
623	\N	1	1	2021-11-14 11:18:01.331+05:30	2021-11-14 11:18:01.331+05:30
624	\N	1	1	2021-11-14 11:18:01.332+05:30	2021-11-14 11:18:01.332+05:30
625	\N	1	1	2021-11-14 11:18:01.334+05:30	2021-11-14 11:18:01.334+05:30
626	\N	1	1	2021-11-14 11:18:13.97+05:30	2021-11-14 11:18:13.97+05:30
627	\N	1	1	2021-11-14 11:18:13.974+05:30	2021-11-14 11:18:13.974+05:30
628	\N	1	1	2021-11-14 11:18:13.995+05:30	2021-11-14 11:18:13.995+05:30
616	\N	1	1	2021-11-14 11:16:37.347+05:30	2021-11-14 11:18:13.999+05:30
629	\N	1	1	2021-11-14 11:18:41.028+05:30	2021-11-14 11:18:41.028+05:30
630	\N	1	1	2021-11-14 11:18:41.031+05:30	2021-11-14 11:18:41.031+05:30
632	\N	1	1	2021-11-14 11:18:41.059+05:30	2021-11-14 11:18:41.059+05:30
633	\N	1	1	2021-11-14 11:18:41.063+05:30	2021-11-14 11:18:41.063+05:30
634	\N	1	1	2021-11-14 11:18:41.084+05:30	2021-11-14 11:18:41.084+05:30
631	\N	1	1	2021-11-14 11:18:41.036+05:30	2021-11-14 11:19:42.434+05:30
800	\N	2	2	2021-11-14 11:41:03.107+05:30	2021-11-14 11:41:03.107+05:30
801	\N	2	2	2021-11-14 11:41:03.149+05:30	2021-11-14 11:41:03.149+05:30
802	\N	2	2	2021-11-14 11:41:03.191+05:30	2021-11-14 11:41:03.191+05:30
803	\N	2	2	2021-11-14 11:41:03.231+05:30	2021-11-14 11:41:03.231+05:30
804	\N	2	2	2021-11-14 11:41:03.268+05:30	2021-11-14 11:41:03.268+05:30
805	\N	2	2	2021-11-14 11:41:03.305+05:30	2021-11-14 11:41:03.305+05:30
806	\N	2	2	2021-11-14 11:41:03.339+05:30	2021-11-14 11:41:03.339+05:30
807	\N	2	2	2021-11-14 11:41:03.372+05:30	2021-11-14 11:41:03.372+05:30
808	\N	2	2	2021-11-14 11:41:03.406+05:30	2021-11-14 11:41:03.406+05:30
809	\N	2	2	2021-11-14 11:41:03.438+05:30	2021-11-14 11:41:03.438+05:30
810	\N	2	2	2021-11-14 11:41:03.471+05:30	2021-11-14 11:41:03.471+05:30
811	\N	2	2	2021-11-14 11:41:03.503+05:30	2021-11-14 11:41:03.503+05:30
812	\N	2	2	2021-11-14 11:41:03.535+05:30	2021-11-14 11:41:03.535+05:30
813	\N	2	2	2021-11-14 11:41:03.568+05:30	2021-11-14 11:41:03.568+05:30
814	\N	2	2	2021-11-14 11:41:03.601+05:30	2021-11-14 11:41:03.601+05:30
815	\N	2	2	2021-11-14 11:41:03.633+05:30	2021-11-14 11:41:03.633+05:30
816	\N	2	2	2021-11-14 11:41:03.666+05:30	2021-11-14 11:41:03.666+05:30
817	\N	2	2	2021-11-14 11:41:03.698+05:30	2021-11-14 11:41:03.698+05:30
818	\N	2	2	2021-11-14 11:41:03.731+05:30	2021-11-14 11:41:03.731+05:30
819	\N	2	2	2021-11-14 11:41:03.763+05:30	2021-11-14 11:41:03.763+05:30
820	\N	2	2	2021-11-14 11:44:31.789+05:30	2021-11-14 11:44:31.789+05:30
821	\N	2	2	2021-11-14 11:44:31.842+05:30	2021-11-14 11:44:31.842+05:30
822	\N	2	2	2021-11-14 11:44:31.893+05:30	2021-11-14 11:44:31.893+05:30
823	\N	2	2	2021-11-14 11:44:31.938+05:30	2021-11-14 11:44:31.938+05:30
824	\N	2	2	2021-11-14 11:44:31.978+05:30	2021-11-14 11:44:31.978+05:30
825	\N	2	2	2021-11-14 11:44:32.023+05:30	2021-11-14 11:44:32.023+05:30
826	\N	2	2	2021-11-14 11:44:32.074+05:30	2021-11-14 11:44:32.074+05:30
827	\N	2	2	2021-11-14 11:44:32.114+05:30	2021-11-14 11:44:32.114+05:30
828	\N	2	2	2021-11-14 11:44:32.149+05:30	2021-11-14 11:44:32.149+05:30
829	\N	2	2	2021-11-14 11:44:32.183+05:30	2021-11-14 11:44:32.183+05:30
830	\N	2	2	2021-11-14 11:44:32.218+05:30	2021-11-14 11:44:32.218+05:30
831	\N	2	2	2021-11-14 11:44:32.284+05:30	2021-11-14 11:44:32.284+05:30
832	\N	2	2	2021-11-14 11:44:32.325+05:30	2021-11-14 11:44:32.325+05:30
833	\N	2	2	2021-11-14 11:44:32.363+05:30	2021-11-14 11:44:32.363+05:30
834	\N	2	2	2021-11-14 11:44:32.402+05:30	2021-11-14 11:44:32.402+05:30
835	\N	2	2	2021-11-14 11:44:32.442+05:30	2021-11-14 11:44:32.442+05:30
836	\N	2	2	2021-11-14 11:44:32.48+05:30	2021-11-14 11:44:32.48+05:30
837	\N	2	2	2021-11-14 11:44:32.518+05:30	2021-11-14 11:44:32.518+05:30
838	\N	2	2	2021-11-14 11:44:32.553+05:30	2021-11-14 11:44:32.553+05:30
839	\N	2	2	2021-11-14 11:46:50.184+05:30	2021-11-14 11:46:50.184+05:30
840	\N	2	2	2021-11-14 11:46:50.238+05:30	2021-11-14 11:46:50.238+05:30
841	\N	2	2	2021-11-14 11:46:50.269+05:30	2021-11-14 11:46:50.269+05:30
842	\N	2	2	2021-11-14 11:46:50.301+05:30	2021-11-14 11:46:50.301+05:30
843	\N	2	2	2021-11-14 11:46:50.343+05:30	2021-11-14 11:46:50.343+05:30
844	\N	2	2	2021-11-14 11:46:50.373+05:30	2021-11-14 11:46:50.373+05:30
845	\N	2	2	2021-11-14 11:46:50.403+05:30	2021-11-14 11:46:50.403+05:30
846	\N	2	2	2021-11-14 11:46:50.432+05:30	2021-11-14 11:46:50.432+05:30
847	\N	2	2	2021-11-14 11:46:50.467+05:30	2021-11-14 11:46:50.467+05:30
848	\N	2	2	2021-11-14 11:46:50.5+05:30	2021-11-14 11:46:50.5+05:30
849	\N	2	2	2021-11-14 11:46:50.529+05:30	2021-11-14 11:46:50.529+05:30
850	\N	2	2	2021-11-14 11:46:50.559+05:30	2021-11-14 11:46:50.559+05:30
851	\N	2	2	2021-11-14 11:46:50.589+05:30	2021-11-14 11:46:50.589+05:30
852	\N	2	2	2021-11-14 11:46:50.619+05:30	2021-11-14 11:46:50.619+05:30
853	\N	2	2	2021-11-14 11:46:50.648+05:30	2021-11-14 11:46:50.648+05:30
854	\N	2	2	2021-11-14 11:46:50.677+05:30	2021-11-14 11:46:50.677+05:30
855	\N	2	2	2021-11-14 11:46:50.707+05:30	2021-11-14 11:46:50.707+05:30
856	\N	2	2	2021-11-14 11:46:50.739+05:30	2021-11-14 11:46:50.739+05:30
857	\N	2	2	2021-11-14 11:46:50.772+05:30	2021-11-14 11:46:50.772+05:30
858	\N	2	2	2021-11-14 11:46:50.803+05:30	2021-11-14 11:46:50.803+05:30
879	\N	2	2	2021-11-14 11:50:32.04+05:30	2021-11-14 11:50:32.04+05:30
880	\N	2	2	2021-11-14 11:50:32.075+05:30	2021-11-14 11:50:32.075+05:30
881	\N	2	2	2021-11-14 11:50:32.128+05:30	2021-11-14 11:50:32.128+05:30
882	\N	2	2	2021-11-14 11:50:32.177+05:30	2021-11-14 11:50:32.177+05:30
883	\N	2	2	2021-11-14 11:50:32.212+05:30	2021-11-14 11:50:32.212+05:30
884	\N	2	2	2021-11-14 11:50:32.289+05:30	2021-11-14 11:50:32.289+05:30
885	\N	2	2	2021-11-14 11:50:32.328+05:30	2021-11-14 11:50:32.328+05:30
886	\N	2	2	2021-11-14 11:50:32.363+05:30	2021-11-14 11:50:32.363+05:30
887	\N	2	2	2021-11-14 11:50:32.397+05:30	2021-11-14 11:50:32.397+05:30
888	\N	2	2	2021-11-14 11:53:17.954+05:30	2021-11-14 11:53:17.954+05:30
889	\N	2	2	2021-11-14 11:53:17.99+05:30	2021-11-14 11:53:17.99+05:30
890	\N	2	2	2021-11-14 11:53:18.023+05:30	2021-11-14 11:53:18.023+05:30
891	\N	2	2	2021-11-14 11:53:18.053+05:30	2021-11-14 11:53:18.053+05:30
892	\N	2	2	2021-11-14 11:53:18.081+05:30	2021-11-14 11:53:18.081+05:30
893	\N	2	2	2021-11-14 11:53:18.109+05:30	2021-11-14 11:53:18.109+05:30
894	\N	2	2	2021-11-14 11:53:18.139+05:30	2021-11-14 11:53:18.139+05:30
895	\N	2	2	2021-11-14 11:53:18.168+05:30	2021-11-14 11:53:18.168+05:30
896	\N	2	2	2021-11-14 11:53:18.197+05:30	2021-11-14 11:53:18.197+05:30
897	\N	2	2	2021-11-14 11:53:18.225+05:30	2021-11-14 11:53:18.225+05:30
898	\N	2	2	2021-11-14 11:53:18.254+05:30	2021-11-14 11:53:18.254+05:30
899	\N	2	2	2021-11-14 11:53:18.282+05:30	2021-11-14 11:53:18.282+05:30
900	\N	2	2	2021-11-14 11:53:18.31+05:30	2021-11-14 11:53:18.31+05:30
901	\N	2	2	2021-11-14 11:53:18.338+05:30	2021-11-14 11:53:18.338+05:30
902	\N	2	2	2021-11-14 11:53:18.366+05:30	2021-11-14 11:53:18.366+05:30
903	\N	2	2	2021-11-14 11:53:18.397+05:30	2021-11-14 11:53:18.397+05:30
904	\N	2	2	2021-11-14 11:53:18.426+05:30	2021-11-14 11:53:18.426+05:30
905	\N	2	2	2021-11-14 11:53:18.454+05:30	2021-11-14 11:53:18.454+05:30
906	\N	2	2	2021-11-14 11:53:18.482+05:30	2021-11-14 11:53:18.482+05:30
907	\N	2	2	2021-11-14 11:53:18.51+05:30	2021-11-14 11:53:18.51+05:30
908	\N	2	2	2021-11-14 11:55:39.6+05:30	2021-11-14 11:55:39.6+05:30
909	\N	2	2	2021-11-14 11:55:39.635+05:30	2021-11-14 11:55:39.635+05:30
910	\N	2	2	2021-11-14 11:55:39.678+05:30	2021-11-14 11:55:39.678+05:30
911	\N	2	2	2021-11-14 11:55:39.706+05:30	2021-11-14 11:55:39.706+05:30
557	\N	1	1	2021-11-14 11:07:56.341+05:30	2021-11-14 11:07:56.341+05:30
571	\N	1	1	2021-11-14 11:08:39.685+05:30	2021-11-14 11:08:39.685+05:30
572	\N	1	1	2021-11-14 11:08:39.691+05:30	2021-11-14 11:08:39.691+05:30
574	\N	1	1	2021-11-14 11:08:39.728+05:30	2021-11-14 11:08:39.728+05:30
575	\N	1	1	2021-11-14 11:08:39.732+05:30	2021-11-14 11:08:39.732+05:30
576	\N	1	1	2021-11-14 11:08:39.751+05:30	2021-11-14 11:08:39.751+05:30
583	\N	1	1	2021-11-14 11:09:17.434+05:30	2021-11-14 11:09:17.434+05:30
584	\N	1	1	2021-11-14 11:09:42.661+05:30	2021-11-14 11:09:42.661+05:30
573	\N	1	1	2021-11-14 11:08:39.697+05:30	2021-11-14 11:10:41.613+05:30
635	\N	1	1	2021-11-14 11:19:12.384+05:30	2021-11-14 11:19:12.384+05:30
636	\N	1	1	2021-11-14 11:19:12.387+05:30	2021-11-14 11:19:12.387+05:30
637	\N	1	1	2021-11-14 11:19:12.389+05:30	2021-11-14 11:19:12.389+05:30
89	\N	1	1	2021-11-14 10:58:04.92+05:30	2021-11-14 11:03:26.145+05:30
456	\N	1	1	2021-11-14 11:03:26.159+05:30	2021-11-14 11:03:26.159+05:30
457	\N	1	1	2021-11-14 11:03:26.174+05:30	2021-11-14 11:03:26.174+05:30
458	\N	1	1	2021-11-14 11:03:26.177+05:30	2021-11-14 11:03:26.177+05:30
459	\N	1	1	2021-11-14 11:03:26.181+05:30	2021-11-14 11:03:26.181+05:30
460	\N	1	1	2021-11-14 11:03:26.184+05:30	2021-11-14 11:03:26.184+05:30
461	\N	1	1	2021-11-14 11:03:26.188+05:30	2021-11-14 11:03:26.188+05:30
462	\N	1	1	2021-11-14 11:03:26.191+05:30	2021-11-14 11:03:26.191+05:30
463	\N	1	1	2021-11-14 11:03:26.194+05:30	2021-11-14 11:03:26.194+05:30
464	\N	1	1	2021-11-14 11:03:26.197+05:30	2021-11-14 11:03:26.197+05:30
465	\N	1	1	2021-11-14 11:03:26.202+05:30	2021-11-14 11:03:26.202+05:30
466	\N	1	1	2021-11-14 11:03:26.205+05:30	2021-11-14 11:03:26.205+05:30
467	\N	1	1	2021-11-14 11:03:26.209+05:30	2021-11-14 11:03:26.209+05:30
468	\N	1	1	2021-11-14 11:03:26.213+05:30	2021-11-14 11:03:26.213+05:30
469	\N	1	1	2021-11-14 11:03:26.218+05:30	2021-11-14 11:03:26.218+05:30
470	\N	1	1	2021-11-14 11:03:26.221+05:30	2021-11-14 11:03:26.221+05:30
471	\N	1	1	2021-11-14 11:03:26.225+05:30	2021-11-14 11:03:26.225+05:30
472	\N	1	1	2021-11-14 11:03:26.228+05:30	2021-11-14 11:03:26.228+05:30
473	\N	1	1	2021-11-14 11:03:26.232+05:30	2021-11-14 11:03:26.232+05:30
474	\N	1	1	2021-11-14 11:03:26.235+05:30	2021-11-14 11:03:26.235+05:30
475	\N	1	1	2021-11-14 11:03:26.24+05:30	2021-11-14 11:03:26.24+05:30
476	\N	1	1	2021-11-14 11:03:26.243+05:30	2021-11-14 11:03:26.243+05:30
477	\N	1	1	2021-11-14 11:03:26.247+05:30	2021-11-14 11:03:26.247+05:30
478	\N	1	1	2021-11-14 11:03:26.25+05:30	2021-11-14 11:03:26.25+05:30
479	\N	1	1	2021-11-14 11:03:26.256+05:30	2021-11-14 11:03:26.256+05:30
480	\N	1	1	2021-11-14 11:03:26.259+05:30	2021-11-14 11:03:26.259+05:30
481	\N	1	1	2021-11-14 11:03:26.262+05:30	2021-11-14 11:03:26.262+05:30
482	\N	1	1	2021-11-14 11:03:26.265+05:30	2021-11-14 11:03:26.265+05:30
483	\N	1	1	2021-11-14 11:03:26.269+05:30	2021-11-14 11:03:26.269+05:30
484	\N	1	1	2021-11-14 11:03:26.272+05:30	2021-11-14 11:03:26.272+05:30
485	\N	1	1	2021-11-14 11:03:26.275+05:30	2021-11-14 11:03:26.275+05:30
486	\N	1	1	2021-11-14 11:03:26.278+05:30	2021-11-14 11:03:26.278+05:30
487	\N	1	1	2021-11-14 11:03:26.282+05:30	2021-11-14 11:03:26.282+05:30
488	\N	1	1	2021-11-14 11:03:26.285+05:30	2021-11-14 11:03:26.285+05:30
489	\N	1	1	2021-11-14 11:03:26.289+05:30	2021-11-14 11:03:26.289+05:30
490	\N	1	1	2021-11-14 11:03:26.292+05:30	2021-11-14 11:03:26.292+05:30
491	\N	1	1	2021-11-14 11:03:26.296+05:30	2021-11-14 11:03:26.296+05:30
492	\N	1	1	2021-11-14 11:03:26.299+05:30	2021-11-14 11:03:26.299+05:30
493	\N	1	1	2021-11-14 11:03:26.304+05:30	2021-11-14 11:03:26.304+05:30
494	\N	1	1	2021-11-14 11:03:26.307+05:30	2021-11-14 11:03:26.307+05:30
495	\N	1	1	2021-11-14 11:03:26.311+05:30	2021-11-14 11:03:26.311+05:30
496	\N	1	1	2021-11-14 11:03:26.314+05:30	2021-11-14 11:03:26.314+05:30
497	\N	1	1	2021-11-14 11:03:26.319+05:30	2021-11-14 11:03:26.319+05:30
498	\N	1	1	2021-11-14 11:03:26.321+05:30	2021-11-14 11:03:26.321+05:30
499	\N	1	1	2021-11-14 11:03:26.326+05:30	2021-11-14 11:03:26.326+05:30
500	\N	1	1	2021-11-14 11:03:26.329+05:30	2021-11-14 11:03:26.329+05:30
501	\N	1	1	2021-11-14 11:03:26.336+05:30	2021-11-14 11:03:26.336+05:30
502	\N	1	1	2021-11-14 11:03:26.338+05:30	2021-11-14 11:03:26.338+05:30
503	\N	1	1	2021-11-14 11:03:26.339+05:30	2021-11-14 11:03:26.339+05:30
504	\N	1	1	2021-11-14 11:03:26.342+05:30	2021-11-14 11:03:26.342+05:30
505	\N	1	1	2021-11-14 11:03:26.349+05:30	2021-11-14 11:03:26.349+05:30
506	\N	1	1	2021-11-14 11:03:26.351+05:30	2021-11-14 11:03:26.351+05:30
507	\N	1	1	2021-11-14 11:03:26.353+05:30	2021-11-14 11:03:26.353+05:30
508	\N	1	1	2021-11-14 11:03:26.355+05:30	2021-11-14 11:03:26.355+05:30
509	\N	1	1	2021-11-14 11:03:26.362+05:30	2021-11-14 11:03:26.362+05:30
510	\N	1	1	2021-11-14 11:03:26.364+05:30	2021-11-14 11:03:26.364+05:30
511	\N	1	1	2021-11-14 11:03:26.366+05:30	2021-11-14 11:03:26.366+05:30
512	\N	1	1	2021-11-14 11:03:26.388+05:30	2021-11-14 11:03:26.388+05:30
513	\N	1	1	2021-11-14 11:03:26.394+05:30	2021-11-14 11:03:26.394+05:30
514	\N	1	1	2021-11-14 11:03:26.399+05:30	2021-11-14 11:03:26.399+05:30
515	\N	1	1	2021-11-14 11:03:26.404+05:30	2021-11-14 11:03:26.404+05:30
516	\N	1	1	2021-11-14 11:03:26.409+05:30	2021-11-14 11:03:26.409+05:30
517	\N	1	1	2021-11-14 11:03:26.414+05:30	2021-11-14 11:03:26.414+05:30
518	\N	1	1	2021-11-14 11:03:26.419+05:30	2021-11-14 11:03:26.419+05:30
519	\N	1	1	2021-11-14 11:03:26.424+05:30	2021-11-14 11:03:26.424+05:30
520	\N	1	1	2021-11-14 11:03:26.429+05:30	2021-11-14 11:03:26.429+05:30
521	\N	1	1	2021-11-14 11:03:26.434+05:30	2021-11-14 11:03:26.434+05:30
522	\N	1	1	2021-11-14 11:03:26.44+05:30	2021-11-14 11:03:26.44+05:30
523	\N	1	1	2021-11-14 11:03:26.445+05:30	2021-11-14 11:03:26.445+05:30
524	\N	1	1	2021-11-14 11:03:26.45+05:30	2021-11-14 11:03:26.45+05:30
525	\N	1	1	2021-11-14 11:03:26.456+05:30	2021-11-14 11:03:26.456+05:30
526	\N	1	1	2021-11-14 11:03:26.461+05:30	2021-11-14 11:03:26.461+05:30
527	\N	1	1	2021-11-14 11:03:26.467+05:30	2021-11-14 11:03:26.467+05:30
528	\N	1	1	2021-11-14 11:03:26.472+05:30	2021-11-14 11:03:26.472+05:30
529	\N	1	1	2021-11-14 11:03:26.477+05:30	2021-11-14 11:03:26.477+05:30
530	\N	1	1	2021-11-14 11:03:26.483+05:30	2021-11-14 11:03:26.483+05:30
531	\N	1	1	2021-11-14 11:03:26.488+05:30	2021-11-14 11:03:26.488+05:30
532	\N	1	1	2021-11-14 11:03:26.493+05:30	2021-11-14 11:03:26.493+05:30
533	\N	1	1	2021-11-14 11:03:26.499+05:30	2021-11-14 11:03:26.499+05:30
534	\N	1	1	2021-11-14 11:03:26.505+05:30	2021-11-14 11:03:26.505+05:30
535	\N	1	1	2021-11-14 11:03:26.51+05:30	2021-11-14 11:03:26.51+05:30
638	\N	1	1	2021-11-14 11:19:39.128+05:30	2021-11-14 11:19:39.128+05:30
454	\N	1	1	2021-11-14 11:03:26.105+05:30	2021-11-14 11:03:51.413+05:30
639	\N	1	1	2021-11-14 11:19:42.409+05:30	2021-11-14 11:19:42.409+05:30
640	\N	1	1	2021-11-14 11:19:42.411+05:30	2021-11-14 11:19:42.411+05:30
641	\N	1	1	2021-11-14 11:19:42.43+05:30	2021-11-14 11:19:42.43+05:30
912	\N	2	2	2021-11-14 11:55:39.741+05:30	2021-11-14 11:55:39.741+05:30
913	\N	2	2	2021-11-14 11:55:39.777+05:30	2021-11-14 11:55:39.777+05:30
914	\N	2	2	2021-11-14 11:55:39.814+05:30	2021-11-14 11:55:39.814+05:30
915	\N	2	2	2021-11-14 11:55:39.868+05:30	2021-11-14 11:55:39.868+05:30
916	\N	2	2	2021-11-14 11:55:39.93+05:30	2021-11-14 11:55:39.93+05:30
917	\N	2	2	2021-11-14 11:55:39.995+05:30	2021-11-14 11:55:39.995+05:30
918	\N	2	2	2021-11-14 11:55:40.045+05:30	2021-11-14 11:55:40.045+05:30
919	\N	2	2	2021-11-14 11:55:40.1+05:30	2021-11-14 11:55:40.1+05:30
920	\N	2	2	2021-11-14 11:55:40.151+05:30	2021-11-14 11:55:40.151+05:30
921	\N	2	2	2021-11-14 11:55:40.2+05:30	2021-11-14 11:55:40.2+05:30
922	\N	2	2	2021-11-14 11:55:40.247+05:30	2021-11-14 11:55:40.247+05:30
923	\N	2	2	2021-11-14 11:55:40.296+05:30	2021-11-14 11:55:40.296+05:30
924	\N	2	2	2021-11-14 11:55:40.341+05:30	2021-11-14 11:55:40.341+05:30
925	\N	2	2	2021-11-14 11:55:40.391+05:30	2021-11-14 11:55:40.391+05:30
926	\N	2	2	2021-11-14 11:55:40.438+05:30	2021-11-14 11:55:40.438+05:30
927	\N	2	2	2021-11-14 11:55:40.491+05:30	2021-11-14 11:55:40.491+05:30
928	\N	2	2	2021-11-14 11:55:40.53+05:30	2021-11-14 11:55:40.53+05:30
929	\N	2	2	2021-11-14 11:55:40.568+05:30	2021-11-14 11:55:40.568+05:30
930	\N	2	2	2021-11-14 11:55:40.604+05:30	2021-11-14 11:55:40.604+05:30
931	\N	2	2	2021-11-14 11:55:40.645+05:30	2021-11-14 11:55:40.645+05:30
932	\N	2	2	2021-11-14 11:55:40.68+05:30	2021-11-14 11:55:40.68+05:30
933	\N	2	2	2021-11-14 11:55:40.721+05:30	2021-11-14 11:55:40.721+05:30
934	\N	2	2	2021-11-14 11:55:40.753+05:30	2021-11-14 11:55:40.753+05:30
935	\N	2	2	2021-11-14 11:55:40.783+05:30	2021-11-14 11:55:40.783+05:30
936	\N	2	2	2021-11-14 11:55:40.818+05:30	2021-11-14 11:55:40.818+05:30
937	\N	2	2	2021-11-14 11:55:40.846+05:30	2021-11-14 11:55:40.846+05:30
938	\N	2	2	2021-11-14 11:55:40.871+05:30	2021-11-14 11:55:40.871+05:30
939	\N	2	2	2021-11-14 11:55:40.902+05:30	2021-11-14 11:55:40.902+05:30
\.


--
-- Data for Name: batch_job_execution; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.batch_job_execution (job_execution_id, version, job_instance_id, create_time, start_time, end_time, status, exit_code, exit_message, last_updated, job_configuration_location) FROM stdin;
1	2	1	2021-11-14 11:03:21.082	2021-11-14 11:03:21.114	2021-11-14 11:03:26.544	COMPLETED	COMPLETED		2021-11-14 11:03:27.221	\N
2	2	2	2021-11-14 11:31:25.093	2021-11-14 11:31:25.106	2021-11-14 11:31:28.761	COMPLETED	COMPLETED		2021-11-14 11:31:28.856	\N
3	2	3	2021-11-14 11:32:59.043	2021-11-14 11:32:59.051	2021-11-14 11:33:02.213	COMPLETED	COMPLETED		2021-11-14 11:33:02.328	\N
4	2	4	2021-11-14 11:41:02.895	2021-11-14 11:41:02.905	2021-11-14 11:41:03.778	COMPLETED	COMPLETED		2021-11-14 11:41:03.882	\N
5	2	5	2021-11-14 11:44:31.542	2021-11-14 11:44:31.551	2021-11-14 11:44:32.577	COMPLETED	COMPLETED		2021-11-14 11:44:32.936	\N
6	2	6	2021-11-14 11:46:49.995	2021-11-14 11:46:50.004	2021-11-14 11:46:50.819	COMPLETED	COMPLETED		2021-11-14 11:46:50.92	\N
7	2	7	2021-11-14 11:50:31.009	2021-11-14 11:50:31.021	2021-11-14 11:50:32.414	COMPLETED	COMPLETED		2021-11-14 11:50:32.671	\N
8	2	8	2021-11-14 11:53:17.705	2021-11-14 11:53:17.717	2021-11-14 11:53:18.526	COMPLETED	COMPLETED		2021-11-14 11:53:18.617	\N
9	2	9	2021-11-14 11:55:39.351	2021-11-14 11:55:39.362	2021-11-14 11:55:40.923	COMPLETED	COMPLETED		2021-11-14 11:55:41.015	\N
\.


--
-- Data for Name: batch_job_execution_context; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.batch_job_execution_context (job_execution_id, short_context, serialized_context) FROM stdin;
1	{}	\N
2	{}	\N
3	{}	\N
4	{}	\N
5	{}	\N
6	{}	\N
7	{}	\N
8	{}	\N
9	{}	\N
\.


--
-- Data for Name: batch_job_execution_params; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.batch_job_execution_params (job_execution_id, type_cd, key_name, string_val, date_val, long_val, double_val, identifying) FROM stdin;
1	STRING	organisationUUID	0512d373-d0ee-4bb1-a603-170c754cd4e5	1970-01-01 05:30:00	0	0	Y
1	STRING	uuid	ab3e79c2-a88a-40bc-9cf4-a4e1b7af3bb1	1970-01-01 05:30:00	0	0	Y
1	STRING	fileName	IHMP.zip	1970-01-01 05:30:00	0	0	N
1	STRING	s3Key	bulkuploads/input/test/ab3e79c2-a88a-40bc-9cf4-a4e1b7af3bb1-IHMP.zip	1970-01-01 05:30:00	0	0	N
1	LONG	noOfLines		1970-01-01 05:30:00	0	0	N
1	LONG	userId		1970-01-01 05:30:00	1	0	N
1	STRING	type	metadataZip	1970-01-01 05:30:00	0	0	N
2	STRING	organisationUUID	0512d373-d0ee-4bb1-a603-170c754cd4e5	1970-01-01 05:30:00	0	0	Y
2	STRING	uuid	fa4a7f81-f497-4933-9021-6874b60d6e01	1970-01-01 05:30:00	0	0	Y
2	STRING	fileName	Demo data uploads - Person.csv	1970-01-01 05:30:00	0	0	N
2	STRING	s3Key	bulkuploads/input/test/fa4a7f81-f497-4933-9021-6874b60d6e01-Demo_data_uploads_-_Person.csv	1970-01-01 05:30:00	0	0	N
2	LONG	noOfLines		1970-01-01 05:30:00	80	0	N
2	LONG	userId		1970-01-01 05:30:00	1	0	N
2	STRING	type	Subject---Person	1970-01-01 05:30:00	0	0	N
3	STRING	organisationUUID	0512d373-d0ee-4bb1-a603-170c754cd4e5	1970-01-01 05:30:00	0	0	Y
3	STRING	uuid	dc516deb-c4f7-47d4-8821-b111a6e8549d	1970-01-01 05:30:00	0	0	Y
3	STRING	fileName	Demo data uploads - Person.csv	1970-01-01 05:30:00	0	0	N
3	STRING	s3Key	bulkuploads/input/test/dc516deb-c4f7-47d4-8821-b111a6e8549d-Demo_data_uploads_-_Person.csv	1970-01-01 05:30:00	0	0	N
3	LONG	noOfLines		1970-01-01 05:30:00	80	0	N
3	LONG	userId		1970-01-01 05:30:00	2	0	N
3	STRING	type	Subject---Person	1970-01-01 05:30:00	0	0	N
4	STRING	organisationUUID	0512d373-d0ee-4bb1-a603-170c754cd4e5	1970-01-01 05:30:00	0	0	Y
4	STRING	uuid	4ef55803-a487-4258-92a2-623530994ca3	1970-01-01 05:30:00	0	0	Y
4	STRING	fileName	Demo data uploads - Household.csv	1970-01-01 05:30:00	0	0	N
4	STRING	s3Key	bulkuploads/input/test/4ef55803-a487-4258-92a2-623530994ca3-Demo_data_uploads_-_Household.csv	1970-01-01 05:30:00	0	0	N
4	LONG	noOfLines		1970-01-01 05:30:00	21	0	N
4	LONG	userId		1970-01-01 05:30:00	2	0	N
4	STRING	type	Subject---Household	1970-01-01 05:30:00	0	0	N
5	STRING	organisationUUID	0512d373-d0ee-4bb1-a603-170c754cd4e5	1970-01-01 05:30:00	0	0	Y
5	STRING	uuid	dc938eac-f109-4e25-a36c-e40053d5644a	1970-01-01 05:30:00	0	0	Y
5	STRING	fileName	Demo data uploads - Pregnancy.csv	1970-01-01 05:30:00	0	0	N
5	STRING	s3Key	bulkuploads/input/test/dc938eac-f109-4e25-a36c-e40053d5644a-Demo_data_uploads_-_Pregnancy.csv	1970-01-01 05:30:00	0	0	N
5	LONG	noOfLines		1970-01-01 05:30:00	20	0	N
5	LONG	userId		1970-01-01 05:30:00	2	0	N
5	STRING	type	ProgramEnrolment---Pregnancy---Person	1970-01-01 05:30:00	0	0	N
6	STRING	organisationUUID	0512d373-d0ee-4bb1-a603-170c754cd4e5	1970-01-01 05:30:00	0	0	Y
6	STRING	uuid	bb4593a9-0d44-4fc8-9862-d8be72064fbc	1970-01-01 05:30:00	0	0	Y
6	STRING	fileName	Demo data uploads - Child.csv	1970-01-01 05:30:00	0	0	N
6	STRING	s3Key	bulkuploads/input/test/bb4593a9-0d44-4fc8-9862-d8be72064fbc-Demo_data_uploads_-_Child.csv	1970-01-01 05:30:00	0	0	N
6	LONG	noOfLines		1970-01-01 05:30:00	21	0	N
6	LONG	userId		1970-01-01 05:30:00	2	0	N
6	STRING	type	ProgramEnrolment---Child---Person	1970-01-01 05:30:00	0	0	N
7	STRING	organisationUUID	0512d373-d0ee-4bb1-a603-170c754cd4e5	1970-01-01 05:30:00	0	0	Y
7	STRING	uuid	8200165d-32f5-4aec-8668-5dd47f966839	1970-01-01 05:30:00	0	0	Y
7	STRING	fileName	Demo data uploads - Anc followup.csv	1970-01-01 05:30:00	0	0	N
7	STRING	s3Key	bulkuploads/input/test/8200165d-32f5-4aec-8668-5dd47f966839-Demo_data_uploads_-_Anc_followup.csv	1970-01-01 05:30:00	0	0	N
7	LONG	noOfLines		1970-01-01 05:30:00	30	0	N
7	LONG	userId		1970-01-01 05:30:00	2	0	N
7	STRING	type	ProgramEncounter---ANC followup---Person	1970-01-01 05:30:00	0	0	N
8	STRING	organisationUUID	0512d373-d0ee-4bb1-a603-170c754cd4e5	1970-01-01 05:30:00	0	0	Y
8	STRING	uuid	13c6db80-b2a8-43fe-a9a0-0d5b6757adee	1970-01-01 05:30:00	0	0	Y
8	STRING	fileName	Demo data uploads - Survey encounter.csv	1970-01-01 05:30:00	0	0	N
8	STRING	s3Key	bulkuploads/input/test/13c6db80-b2a8-43fe-a9a0-0d5b6757adee-Demo_data_uploads_-_Survey_encounter.csv	1970-01-01 05:30:00	0	0	N
8	LONG	noOfLines		1970-01-01 05:30:00	21	0	N
8	LONG	userId		1970-01-01 05:30:00	2	0	N
8	STRING	type	Encounter---Survey---Household	1970-01-01 05:30:00	0	0	N
9	STRING	organisationUUID	0512d373-d0ee-4bb1-a603-170c754cd4e5	1970-01-01 05:30:00	0	0	Y
9	STRING	uuid	a1edd1d9-eeb0-4dc6-8c4f-19f11e3a4c7f	1970-01-01 05:30:00	0	0	Y
9	STRING	fileName	Demo data uploads - Child followup.csv	1970-01-01 05:30:00	0	0	N
9	STRING	s3Key	bulkuploads/input/test/a1edd1d9-eeb0-4dc6-8c4f-19f11e3a4c7f-Demo_data_uploads_-_Child_followup.csv	1970-01-01 05:30:00	0	0	N
9	LONG	noOfLines		1970-01-01 05:30:00	33	0	N
9	LONG	userId		1970-01-01 05:30:00	2	0	N
9	STRING	type	ProgramEncounter---Child followup---Person	1970-01-01 05:30:00	0	0	N
\.


--
-- Data for Name: batch_job_instance; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.batch_job_instance (job_instance_id, version, job_name, job_key) FROM stdin;
1	0	importZipJob	f09e04f87674052c7a5a2e41e10a53e6
2	0	importJob	094409c3570b5e0f4a10cb38837cac45
3	0	importJob	780a3e39da5310f4f862e602d4f3e855
4	0	importJob	867c36ccecee9fd671c59ae62727a48e
5	0	importJob	09c0fa6ceaede570785d9fc28268b3af
6	0	importJob	37ab1a60be45068822635ebf24e6d2b6
7	0	importJob	ff4fede6e3338d78a5ea881af8fc02a5
8	0	importJob	ad51fb1f988fb48f8d899b4b7153e4c8
9	0	importJob	ca87247dccdfe75e5705ff32b1b05056
\.


--
-- Data for Name: batch_step_execution; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.batch_step_execution (step_execution_id, version, step_name, job_execution_id, start_time, end_time, status, commit_count, read_count, filter_count, write_count, read_skip_count, write_skip_count, process_skip_count, rollback_count, exit_code, exit_message, last_updated) FROM stdin;
8	23	importStep	8	2021-11-14 11:53:17.846	2021-11-14 11:53:18.522	COMPLETED	21	20	0	20	0	0	0	0	COMPLETED		2021-11-14 11:53:18.522
4	23	importStep	4	2021-11-14 11:41:02.994	2021-11-14 11:41:03.775	COMPLETED	21	20	0	20	0	0	0	0	COMPLETED		2021-11-14 11:41:03.775
1	11	importZipStep	1	2021-11-14 11:03:21.165	2021-11-14 11:03:26.54	COMPLETED	9	35	0	8	0	27	0	28	COMPLETED		2021-11-14 11:03:26.541
9	35	importStep	9	2021-11-14 11:55:39.482	2021-11-14 11:55:40.92	COMPLETED	33	32	0	32	0	0	0	0	COMPLETED		2021-11-14 11:55:40.92
2	3	importStep	2	2021-11-14 11:31:25.2	2021-11-14 11:31:28.754	COMPLETED	1	79	0	0	0	0	0	79	COMPLETED		2021-11-14 11:31:28.755
7	32	importStep	7	2021-11-14 11:50:31.106	2021-11-14 11:50:32.412	COMPLETED	30	29	0	29	0	0	0	0	COMPLETED		2021-11-14 11:50:32.412
6	23	importStep	6	2021-11-14 11:46:50.083	2021-11-14 11:46:50.816	COMPLETED	21	20	0	20	0	0	0	0	COMPLETED		2021-11-14 11:46:50.816
3	82	importStep	3	2021-11-14 11:32:59.133	2021-11-14 11:33:02.21	COMPLETED	80	79	0	79	0	0	0	0	COMPLETED		2021-11-14 11:33:02.21
5	22	importStep	5	2021-11-14 11:44:31.642	2021-11-14 11:44:32.57	COMPLETED	20	19	0	19	0	0	0	0	COMPLETED		2021-11-14 11:44:32.571
\.


--
-- Data for Name: batch_step_execution_context; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.batch_step_execution_context (step_execution_id, short_context, serialized_context) FROM stdin;
9	{"batch.taskletType":"org.springframework.batch.core.step.item.ChunkOrientedTasklet","csvFileItemReader.read.count":33,"batch.stepType":"org.springframework.batch.core.step.tasklet.TaskletStep"}	\N
6	{"batch.taskletType":"org.springframework.batch.core.step.item.ChunkOrientedTasklet","csvFileItemReader.read.count":21,"batch.stepType":"org.springframework.batch.core.step.tasklet.TaskletStep"}	\N
1	{"batch.taskletType":"org.springframework.batch.core.step.item.ChunkOrientedTasklet","batch.stepType":"org.springframework.batch.core.step.tasklet.TaskletStep"}	\N
5	{"batch.taskletType":"org.springframework.batch.core.step.item.ChunkOrientedTasklet","csvFileItemReader.read.count":20,"batch.stepType":"org.springframework.batch.core.step.tasklet.TaskletStep"}	\N
4	{"batch.taskletType":"org.springframework.batch.core.step.item.ChunkOrientedTasklet","csvFileItemReader.read.count":21,"batch.stepType":"org.springframework.batch.core.step.tasklet.TaskletStep"}	\N
8	{"batch.taskletType":"org.springframework.batch.core.step.item.ChunkOrientedTasklet","csvFileItemReader.read.count":21,"batch.stepType":"org.springframework.batch.core.step.tasklet.TaskletStep"}	\N
7	{"batch.taskletType":"org.springframework.batch.core.step.item.ChunkOrientedTasklet","csvFileItemReader.read.count":30,"batch.stepType":"org.springframework.batch.core.step.tasklet.TaskletStep"}	\N
3	{"batch.taskletType":"org.springframework.batch.core.step.item.ChunkOrientedTasklet","csvFileItemReader.read.count":80,"batch.stepType":"org.springframework.batch.core.step.tasklet.TaskletStep"}	\N
2	{"batch.taskletType":"org.springframework.batch.core.step.item.ChunkOrientedTasklet","csvFileItemReader.read.count":80,"batch.stepType":"org.springframework.batch.core.step.tasklet.TaskletStep"}	\N
\.


--
-- Data for Name: catchment; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.catchment (id, name, uuid, version, organisation_id, type, audit_id, is_voided) FROM stdin;
1	States	f015dac4-a2a7-482e-96c4-cdb984a0c7d8	0	2	Villages	92	f
\.


--
-- Data for Name: catchment_address_mapping; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.catchment_address_mapping (id, catchment_id, addresslevel_id) FROM stdin;
1	1	1
\.


--
-- Data for Name: checklist; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.checklist (id, program_enrolment_id, uuid, version, base_date, organisation_id, audit_id, is_voided, checklist_detail_id) FROM stdin;
\.


--
-- Data for Name: checklist_detail; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.checklist_detail (id, uuid, version, audit_id, name, is_voided, organisation_id) FROM stdin;
\.


--
-- Data for Name: checklist_item; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.checklist_item (id, completion_date, checklist_id, uuid, version, organisation_id, audit_id, is_voided, observations, checklist_item_detail_id) FROM stdin;
\.


--
-- Data for Name: checklist_item_detail; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.checklist_item_detail (id, uuid, version, audit_id, form_id, concept_id, checklist_detail_id, status, is_voided, organisation_id, dependent_on, schedule_on_expiry_of_dependency, min_days_from_start_date, min_days_from_dependent, expires_after) FROM stdin;
\.


--
-- Data for Name: comment; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.comment (id, organisation_id, uuid, text, subject_id, is_voided, audit_id, version, comment_thread_id) FROM stdin;
\.


--
-- Data for Name: comment_thread; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.comment_thread (id, organisation_id, uuid, status, open_date_time, resolved_date_time, is_voided, audit_id, version) FROM stdin;
\.


--
-- Data for Name: concept; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.concept (id, data_type, high_absolute, high_normal, low_absolute, low_normal, name, uuid, version, unit, organisation_id, is_voided, audit_id, key_values, active) FROM stdin;
4	Coded	\N	\N	\N	\N	Gender	483be0b2-b6ba-40e0-8bf7-91cb33c6e284	1	\N	1	f	1	\N	t
1	NA	\N	\N	\N	\N	Male	7038d549-4a3b-4600-b856-f6f3d123fbd8	1	\N	1	f	2	\N	t
2	NA	\N	\N	\N	\N	Female	09e1b06f-26be-4f7a-8121-5dba3a11b684	1	\N	1	f	3	\N	t
3	NA	\N	\N	\N	\N	Other Gender	d56700ea-fac8-4255-8403-7f8f3b755335	1	\N	1	f	4	\N	t
308	Numeric	\N	\N	\N	\N	Standard upto which schooling completed	23cd954d-5f62-4ba1-a98b-b691161eedee	0	\N	2	f	537	\N	t
309	NA	\N	\N	\N	\N	Student	343e3f7d-eb1c-47b3-ada3-13250b7ba8b3	0	\N	2	f	538	\N	t
310	NA	\N	\N	\N	\N	Unemployed	46ada9e0-af53-428b-b23f-610185d818ba	0	\N	2	f	539	\N	t
311	NA	\N	\N	\N	\N	Working	f5cca911-2944-4636-ad00-356fb07fea67	0	\N	2	f	540	\N	t
312	Coded	\N	\N	\N	\N	Occupation	bc0820f0-462f-4dd9-aea7-e357679621d1	0	\N	2	f	541	\N	t
313	NA	\N	\N	\N	\N	Yes	399e1a98-9361-4a1d-a1ff-eb810a92354e	0	\N	2	f	545	\N	t
314	NA	\N	\N	\N	\N	No	53d8be75-29f3-4e96-90ac-0f4afc321fba	0	\N	2	f	546	\N	t
315	Coded	\N	\N	\N	\N	Whether any disability	ac3189a1-42c0-4e48-87cd-11e233081e67	0	\N	2	f	547	\N	t
316	Numeric	\N	\N	\N	\N	House number	2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d	0	\N	2	f	554	\N	t
317	NA	\N	\N	\N	\N	Muslim	bb38fbc5-cbb4-4912-aa12-486abc54c812	0	\N	2	f	555	\N	t
318	NA	\N	\N	\N	\N	Other	6a18dbfa-acc3-4a9a-89cc-8cab6ced1624	0	\N	2	f	556	\N	t
319	NA	\N	\N	\N	\N	Sikh	4c7c5ed5-1f6f-4203-a59d-7fcbedac8be8	0	\N	2	f	557	\N	t
320	NA	\N	\N	\N	\N	Jain	ecc781a9-d4f2-4954-a05b-01ff2ca20828	0	\N	2	f	558	\N	t
321	NA	\N	\N	\N	\N	Christan	1db734e8-11fb-4f9d-8077-1aafe7a78186	0	\N	2	f	559	\N	t
322	NA	\N	\N	\N	\N	Hindu	5efbf27f-a6fc-46e1-8eca-147fcede670c	0	\N	2	f	560	\N	t
323	Coded	\N	\N	\N	\N	Religion	ea3e1478-7228-4cb3-9db6-73764a323c0a	0	\N	2	f	561	\N	t
324	Numeric	\N	\N	\N	\N	Weight	e71446ac-607b-4733-83a2-4dafb37232a4	0	\N	2	f	583	\N	t
325	Numeric	\N	\N	\N	\N	Height	8afa9fc3-e8b7-446b-a78a-b0226409a552	0	\N	2	f	584	\N	t
326	Coded	\N	\N	\N	\N	Enrolling during birth	011bbae2-e642-40d9-a36c-59dca6be28a8	0	\N	2	f	585	\N	t
327	Numeric	\N	\N	\N	\N	MCTS	8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8	0	\N	2	f	592	\N	t
328	Numeric	\N	\N	\N	\N	R15 number	a425964c-e70b-4f6d-9909-c78c371d0bf8	0	\N	2	f	593	\N	t
329	Date	\N	\N	\N	\N	Last menstrual period	cffd9194-4e19-4b9c-9bb5-27e7ca448c23	0	\N	2	f	594	\N	t
330	Numeric	\N	\N	\N	\N	Number of living children	e1f0db24-dfbd-4c5d-ae3b-66de005e72aa	0	\N	2	f	595	\N	t
331	Coded	\N	\N	\N	\N	Is she on TB medication?	78169e26-bf95-44e1-bb4f-91092fd8cc21	0	\N	2	f	596	\N	t
332	Coded	\N	\N	\N	\N	Any pregnancy complications	ad90e65c-7ac7-440a-a818-075e2bd65e7a	0	\N	2	f	620	\N	t
333	Coded	\N	\N	\N	\N	Problem in breathing	75ffb941-c068-4c47-8364-92e279381d61	0	\N	2	f	623	\N	t
334	Coded	\N	\N	\N	\N	Any Medical Issue	c79be135-8290-4db2-9f88-a69856156d61	0	\N	2	f	635	\N	t
335	Numeric	\N	\N	\N	\N	Annual Expenditure	2e94d46c-6d1c-402a-bef0-b1e28ca23e88	0	\N	2	f	638	\N	t
\.


--
-- Data for Name: concept_answer; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.concept_answer (id, concept_id, answer_concept_id, uuid, version, answer_order, organisation_id, abnormal, is_voided, uniq, audit_id) FROM stdin;
1	4	1	fd630fa3-7122-40b5-9a4c-12bfe7a314e0	1	1	1	f	f	f	5
2	4	2	f6532996-a377-48f4-aafc-2e044ad9b1e2	1	1	1	f	f	f	6
3	4	3	e033664f-458c-4698-8090-152ee7fb4cd7	1	1	1	f	f	f	7
22	312	309	74a81555-515d-46cf-8ed4-340d20104630	0	1	2	f	f	f	542
23	312	311	3c80e8aa-1d33-4c89-8a36-916830887139	0	2	2	f	f	f	543
24	312	310	9fd293e9-53a0-441e-a592-39ddcf8a8dca	0	0	2	f	f	f	544
25	315	313	93976061-28ec-4c99-a62b-a4cec08a04fd	0	0	2	f	f	f	548
26	315	314	a3a9c94d-9355-472a-bf96-25570aa370f1	0	1	2	f	f	f	549
27	323	322	70573690-f55f-401a-9421-901d4c367601	0	0	2	f	f	f	562
28	323	321	c3c5a68b-4a0c-456b-a9c9-cd15402b4e9c	0	2	2	f	f	f	563
29	323	318	23d531fa-c6aa-47f7-94e4-15c1f6cef2c9	0	5	2	f	f	f	564
30	323	317	4adcbdaf-d8c9-47ff-9ffa-af7a47e5e8e7	0	1	2	f	f	f	565
31	323	319	d30f23c1-c9ef-4c13-8127-5eb692121088	0	3	2	f	f	f	566
32	323	320	1166c7e7-b151-4b1a-bf47-9da7098a0f10	0	4	2	f	f	f	567
33	326	313	7d345ac2-8a7a-44d5-ae95-539c9771c411	0	0	2	f	f	f	586
34	326	314	2778688c-6b36-4525-9895-0745e017be8a	0	1	2	f	f	f	587
35	331	313	bdc21192-8a8c-472e-aa5a-04c33f01f9b4	0	0	2	f	f	f	597
36	331	314	c0e7b86f-fd84-483c-8977-2d466c925440	0	1	2	f	f	f	598
37	332	313	8dd17586-96cf-45e1-9f86-648ae5ea66bc	0	0	2	f	f	f	621
38	332	314	87497122-279b-4fb6-9d2f-4c7e0ccdcb3b	0	1	2	f	f	f	622
39	333	313	247afdf5-9cbf-4068-b126-feaaa62ca8d9	0	0	2	f	f	f	624
40	333	314	6dcab182-d5f3-496e-92e6-e5ecdd592325	0	1	2	f	f	f	625
41	334	313	54268e94-576a-4ad4-80d2-c47083644ff2	0	0	2	f	f	f	636
42	334	314	756552d8-90a0-4481-8be4-d48c8b9a607f	0	1	2	f	f	f	637
\.


--
-- Data for Name: dashboard; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.dashboard (id, uuid, name, description, is_voided, version, organisation_id, audit_id) FROM stdin;
\.


--
-- Data for Name: dashboard_card_mapping; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.dashboard_card_mapping (id, uuid, dashboard_id, card_id, display_order, is_voided, version, organisation_id, audit_id) FROM stdin;
\.


--
-- Data for Name: dashboard_section; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.dashboard_section (id, uuid, name, description, dashboard_id, view_type, display_order, is_voided, version, organisation_id, audit_id) FROM stdin;
\.


--
-- Data for Name: dashboard_section_card_mapping; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.dashboard_section_card_mapping (id, uuid, dashboard_section_id, card_id, display_order, is_voided, version, organisation_id, audit_id) FROM stdin;
\.


--
-- Data for Name: decision_concept; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.decision_concept (id, concept_id, form_id) FROM stdin;
\.


--
-- Data for Name: deps_saved_ddl; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.deps_saved_ddl (deps_id, deps_view_schema, deps_view_name, deps_ddl_to_run) FROM stdin;
\.


--
-- Data for Name: encounter; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.encounter (id, observations, encounter_date_time, encounter_type_id, individual_id, uuid, version, organisation_id, is_voided, audit_id, encounter_location, earliest_visit_date_time, max_visit_date_time, cancel_date_time, cancel_observations, cancel_location, name, legacy_id) FROM stdin;
1	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1267.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-10 00:00:00+05:30	18	159	508aa669-53d1-4bfe-9f50-55678783d36d	0	2	f	888	\N	\N	\N	\N	\N	\N	\N	1
2	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1268.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-11 00:00:00+05:30	18	160	adb51a0f-af9f-4d33-b6d9-2298cc496d3a	0	2	f	889	\N	\N	\N	\N	\N	\N	\N	2
3	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1269.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-12 00:00:00+05:30	18	161	3dedca57-6a13-42dc-944a-aa31eabd9bb5	0	2	f	890	\N	\N	\N	\N	\N	\N	\N	3
4	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1270.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-13 00:00:00+05:30	18	162	04e78412-2a90-49f3-88d4-b04c65c9cec1	0	2	f	891	\N	\N	\N	\N	\N	\N	\N	4
5	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1271.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-14 00:00:00+05:30	18	163	cd9d7fa0-3a34-42f4-8866-6b94864a7979	0	2	f	892	\N	\N	\N	\N	\N	\N	\N	5
6	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1272.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-15 00:00:00+05:30	18	164	8c9e1c9e-3557-4914-b483-4f44b2089a2c	0	2	f	893	\N	\N	\N	\N	\N	\N	\N	6
7	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1273.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-16 00:00:00+05:30	18	165	25d4553b-219d-4252-8efe-a05fc09478c1	0	2	f	894	\N	\N	\N	\N	\N	\N	\N	7
8	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1274.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-17 00:00:00+05:30	18	166	7fa24c70-d93c-40b1-8d6c-6bbc879f7989	0	2	f	895	\N	\N	\N	\N	\N	\N	\N	8
9	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1275.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-18 00:00:00+05:30	18	167	8c3cc246-81b2-4404-b657-52277b65ecb7	0	2	f	896	\N	\N	\N	\N	\N	\N	\N	9
10	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1276.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-19 00:00:00+05:30	18	168	390cc290-0529-4735-9bc5-c3faaf60188e	0	2	f	897	\N	\N	\N	\N	\N	\N	\N	10
11	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1277.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-20 00:00:00+05:30	18	169	7c228e3f-c18f-4031-9573-bf8b7b1bc75c	0	2	f	898	\N	\N	\N	\N	\N	\N	\N	11
12	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1278.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-21 00:00:00+05:30	18	170	0f748f03-5564-4942-9c6c-eac57d25cf89	0	2	f	899	\N	\N	\N	\N	\N	\N	\N	12
13	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1279.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-22 00:00:00+05:30	18	171	400dc8d7-58ce-4e5f-9e64-20cbf268301d	0	2	f	900	\N	\N	\N	\N	\N	\N	\N	13
14	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1280.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-23 00:00:00+05:30	18	172	52a0fa47-c80b-4382-a1a2-4e5f5862c748	0	2	f	901	\N	\N	\N	\N	\N	\N	\N	14
15	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1281.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-24 00:00:00+05:30	18	173	e50d5d88-2c2f-4a8e-ba24-9a0627d0eb21	0	2	f	902	\N	\N	\N	\N	\N	\N	\N	15
16	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1282.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-25 00:00:00+05:30	18	174	d7244617-3773-4408-afbc-cb87de441297	0	2	f	903	\N	\N	\N	\N	\N	\N	\N	16
17	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1283.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-26 00:00:00+05:30	18	175	5f3f2815-b3a5-4d22-acd9-8f96581a81e0	0	2	f	904	\N	\N	\N	\N	\N	\N	\N	17
18	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1284.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-27 00:00:00+05:30	18	176	ed383475-90e0-4f15-a34c-92fb25fcad88	0	2	f	905	\N	\N	\N	\N	\N	\N	\N	18
19	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1285.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-28 00:00:00+05:30	18	177	ffeeb976-b218-4a7e-b354-99c907ad1219	0	2	f	906	\N	\N	\N	\N	\N	\N	\N	19
20	{"2e94d46c-6d1c-402a-bef0-b1e28ca23e88": 1286.0, "c79be135-8290-4db2-9f88-a69856156d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-29 00:00:00+05:30	18	178	8878b2e9-b2a0-4d12-8d6e-a6a5f7708b3f	0	2	f	907	\N	\N	\N	\N	\N	\N	\N	20
\.


--
-- Data for Name: encounter_type; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.encounter_type (id, name, concept_id, uuid, version, organisation_id, audit_id, is_voided, encounter_eligibility_check_rule, active) FROM stdin;
1	Monthly needs assessment	\N	55f10f7a-d85e-487e-b611-c1b5e26ab972	0	2	109	f	\N	t
2	FP services	\N	90aee0f6-6267-4133-8bd8-2938c6da5da4	0	2	110	f	\N	t
3	RTI services	\N	f750c222-f7eb-4a98-bd79-273c578dedcf	0	2	111	f	\N	t
4	ANC VHND	\N	0511f4b0-4af8-4493-ace6-97740f89f1f2	0	2	112	f	\N	t
5	ANC ASHA	\N	48f359e2-1387-49a0-bb15-71c1750b2acf	0	2	113	f	\N	t
6	ANC VHND Follow up	\N	e381bd4e-6bf5-498d-b870-48fcfea303ff	0	2	114	f	\N	t
7	Nutritional status and Morbidity	\N	0126df9e-0167-4d44-9a2a-ae41cfc58d3d	0	2	115	f	\N	t
8	Census	\N	76244d2f-d23e-469b-a185-efa51d9ce536	0	2	116	f	\N	t
9	Birth (ASHA)	\N	badd43fa-6346-436e-8fbc-9055be2754c9	0	2	117	f	\N	t
10	Neonatal	\N	cc6f9612-79af-4dcd-a019-5852c9e201aa	0	2	118	f	\N	t
11	Abortion followup	\N	08250f58-6c95-49ca-ba42-57e49005ead6	0	2	119	f	\N	t
12	Marriage	\N	5666eb22-da31-4f0f-98cc-201e1657c502	0	2	120	f	\N	t
13	Death	\N	c2d709b5-f769-42b0-bea5-8f8b182ef1a5	0	2	121	f	\N	t
14	ASHA Area Inputs	\N	7d38fd0e-94c5-48c1-9e3c-1719189cbea2	0	2	122	f	\N	t
15	Household Survey	\N	a4e1d7ba-ff64-4c0f-a560-b58235154e4f	0	2	123	f		t
16	Child followup	\N	30200b51-257d-4ce9-b2d8-bf3cd52c5b2a	0	2	605	f		t
17	ANC followup	\N	5fba24e5-d961-46d7-9c9f-4bf559496e9b	0	2	614	f		t
18	Survey	\N	716849bf-1045-4f61-a78d-d399698f1d83	0	2	629	f		t
\.


--
-- Data for Name: entity_approval_status; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.entity_approval_status (id, uuid, entity_id, entity_type, approval_status_id, approval_status_comment, organisation_id, auto_approved, audit_id, version, is_voided, status_date_time) FROM stdin;
\.


--
-- Data for Name: facility; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.facility (id, uuid, name, address_id, is_voided, organisation_id, version, audit_id) FROM stdin;
\.


--
-- Data for Name: form; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.form (id, name, form_type, uuid, version, organisation_id, audit_id, is_voided, decision_rule, validation_rule, visit_schedule_rule, checklists_rule) FROM stdin;
3	ASHA Area Inputs Registration (voided~3)	IndividualProfile	0aad3f30-1ef0-4b56-a158-98416982dd62	0	2	454	t	\N	\N	\N	\N
1	Person Registration	IndividualProfile	a9f9fca7-bea7-4f27-b7fa-405cc7c78a40	0	2	96	f	\N	\N	\N	\N
2	Household Registration	IndividualProfile	f3fc6f4c-cee4-455c-a5d0-763bf0aa3f1e	0	2	102	f	\N	\N	\N	\N
5	Child Exit	ProgramExit	2022e77f-1929-4a5f-aba0-65ba5db3bfb2	0	2	575	f	\N	\N	\N	\N
7	Pregnancy Exit	ProgramExit	d5c697ac-d779-48cd-bc17-67bce1b2257d	0	2	581	f	\N	\N	\N	\N
4	Child Enrolment	ProgramEnrolment	14f49caf-a5fc-4c89-aaa9-e90b6b65df37	0	2	573	f	\N	\N	\N	\N
6	Pregnancy Enrolment	ProgramEnrolment	9e55d4e0-3c3b-4e1d-96c8-7e38efffac7b	0	2	579	f	\N	\N	\N	\N
9	Child followup Encounter Cancellation	ProgramEncounterCancellation	412ab9c3-a089-4cb2-8dea-f0a44cdc3eb0	0	2	609	f	\N	\N	\N	\N
8	Child followup Encounter	ProgramEncounter	6716892a-08ba-4429-9645-c9284289051b	0	2	607	f	\N	\N	\N	\N
11	ANC followup Encounter Cancellation	ProgramEncounterCancellation	344fdccf-1c84-4707-a25a-52a20142b152	0	2	618	f	\N	\N	\N	\N
10	ANC followup Encounter	ProgramEncounter	bb6350bb-b9c1-406c-af94-208ad9ef0169	0	2	616	f	\N	\N	\N	\N
13	Survey Encounter Cancellation	IndividualEncounterCancellation	c89be27b-0a71-49a3-a92d-01e9b92370e9	0	2	633	f	\N	\N	\N	\N
12	Survey Encounter	Encounter	2fdb5f09-3bcf-407b-b4b8-fdf2df96b2d0	0	2	631	f	\N	\N	\N	\N
\.


--
-- Data for Name: form_element; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.form_element (id, name, display_order, is_mandatory, key_values, concept_id, form_element_group_id, uuid, version, organisation_id, type, valid_format_regex, valid_format_description_key, audit_id, is_voided, rule) FROM stdin;
1	Standard upto which schooling completed	1	t	[]	308	1	d827d2ed-4f47-493b-a056-86286a57065b	0	2	SingleSelect	\N	\N	551	f	\N
2	Occupation	2	t	[]	312	1	028ea711-5a79-45cd-90bf-1cca9790bf49	0	2	SingleSelect	\N	\N	552	f	\N
3	Whether any disability	3	t	[]	315	1	6f3d2a0c-e4fb-42fd-ab17-fc017eaf65ab	0	2	SingleSelect	\N	\N	553	f	\N
4	House number	1	t	[]	316	2	6eb7ff34-0992-4217-a496-165e64104e08	0	2	SingleSelect	\N	\N	569	f	\N
5	Religion	2	t	[]	323	2	23cb3bdd-01dc-4bf0-8f45-f7f5b27e4bda	0	2	SingleSelect	\N	\N	570	f	\N
6	Enrolling during birth?	1	t	[]	326	3	7785e3d3-91ae-401d-9c9f-3d0aa524db84	0	2	SingleSelect	\N	\N	589	f	\N
7	Weight	2	t	[]	324	3	8374e4f7-8d28-4496-ac47-f4989ce2ded3	0	2	SingleSelect	\N	\N	590	f	\N
8	Height	3	t	[]	325	3	d9fdc6c5-fb68-4353-ad2c-f9fddb69105a	0	2	SingleSelect	\N	\N	591	f	\N
9	MCTS	1	t	[]	327	4	a3a08540-ec03-4177-a7ec-690686fc0c81	0	2	SingleSelect	\N	\N	600	f	\N
10	R15 number	2	t	[]	328	4	3b5207f5-f440-4273-81af-66d3d703074e	0	2	SingleSelect	\N	\N	601	f	\N
11	Last menstrual period	3	t	[]	329	4	db9e1350-1144-4fc2-b294-c4e34859e4aa	0	2	SingleSelect	\N	\N	602	f	\N
12	Number of living children	4	t	[]	330	4	11b68724-a29f-4e51-8e55-894d10f25ea4	0	2	SingleSelect	\N	\N	603	f	\N
13	Is she on TB medication?	5	t	[]	331	4	2f848496-7448-4135-b19c-2e61054bf81a	0	2	SingleSelect	\N	\N	604	f	\N
14	Height	1	t	[]	325	5	5a8c0488-517c-4db5-893f-51f2373801dc	0	2	SingleSelect	\N	\N	612	f	\N
15	Weight	2	t	[]	324	5	04ce57d8-0386-4858-ac6a-0d47e6e632d5	0	2	SingleSelect	\N	\N	613	f	\N
16	Any pregnancy complications	1	t	[]	332	6	f54e914f-d16f-4bdf-bd8a-1490d069bca4	0	2	SingleSelect	\N	\N	627	f	\N
17	Breathing problems	2	t	[]	333	6	09d1aa3c-2a4e-4c1f-8d20-b3d607c5d99f	0	2	SingleSelect	\N	\N	628	f	\N
18	Any Medical Issue	1	t	[]	334	7	1305c602-722b-44b7-8d80-f9db31c428d5	0	2	SingleSelect	\N	\N	640	f	\N
19	Annual Expenditure	2	f	[]	335	7	8b759528-d0d1-40a2-9b96-fa6430f742f7	0	2	SingleSelect	\N	\N	641	f	\N
\.


--
-- Data for Name: form_element_group; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.form_element_group (id, name, form_id, uuid, version, display_order, display, organisation_id, audit_id, is_voided, rule) FROM stdin;
1	Details	1	1564f046-184f-4884-b210-afc461a3ce6e	0	1	Details	2	550	f	\N
2	Details	2	1a43f8f9-2370-400f-b33c-c599afcee8c9	0	1	Details	2	568	f	\N
3	Birth details	4	038f7a3f-877f-4fb1-b9b7-b8e586a37426	0	1	Birth details	2	588	f	\N
4	ANC Enrolment Basic Details	6	8c5da2f8-5887-497c-915a-ca44b1203e14	0	1	ANC Enrolment Basic Details	2	599	f	\N
5	Follow up details	8	9ad5fc24-0fb4-4700-8768-523eb06631e4	0	1	Follow up details	2	611	f	\N
6	follou details	10	7bd5c613-7035-4bc6-8ebf-92d377f034a9	0	1	follou details	2	626	f	\N
7	Deatils	12	b8690cc2-781f-49ca-ab87-280931075463	0	1	Deatils	2	639	f	\N
\.


--
-- Data for Name: form_mapping; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.form_mapping (id, form_id, uuid, version, entity_id, observations_type_entity_id, organisation_id, audit_id, is_voided, subject_type_id, enable_approval) FROM stdin;
1	1	5d775267-3577-4945-9389-e159bfa2fe7f	0	\N	\N	2	97	f	2	f
2	2	563f5b5c-c11b-4f2b-ba66-c40c8142f579	0	\N	\N	2	103	f	3	f
4	4	aebaea6c-d69a-4de5-bfb6-a1ae1f73d553	0	2	\N	2	574	f	2	f
5	5	eb7e0eca-4964-4b3f-93b2-61ec751e961d	0	2	\N	2	576	f	2	f
6	6	d8c08ac1-31b7-40a8-9c84-14c2ac2fe2fe	0	3	\N	2	580	f	2	f
7	7	255f57b1-f0df-473c-93de-01fdb8373c1a	0	3	\N	2	582	f	2	f
8	8	51218687-2843-486a-9d8f-7754666def30	0	2	16	2	608	f	2	f
9	9	6ed5da5f-a4be-409f-a913-79db22de84c4	0	2	16	2	610	f	2	f
10	10	97964eee-2b43-4d68-b963-0267d71cf36d	0	3	17	2	617	f	2	f
11	11	5dcea186-11c5-4356-b127-6d143980cc96	0	3	17	2	619	f	2	f
12	12	db6fdbe2-88a7-4051-84b6-9063e022d640	0	\N	18	2	632	f	3	f
13	13	990cd252-58f9-4c87-bdee-82471979e09c	0	\N	18	2	634	f	3	f
\.


--
-- Data for Name: gender; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.gender (id, uuid, name, concept_id, version, audit_id, is_voided, organisation_id) FROM stdin;
1	ad7d1d14-54fd-45a2-86b7-ea329b744484	Female	\N	1	8	f	1
2	840de9fb-e565-4d7d-b751-90335ba20490	Male	\N	1	9	f	1
3	188ad77e-fe46-4328-b0e2-98f3a05c554c	Other	\N	1	10	f	1
4	8c92039f-876b-41df-80a3-0f89378de386	Male	\N	0	85	f	2
5	0685b126-146a-4565-ac65-45c52ad90075	Female	\N	0	86	f	2
6	c591dee9-899e-4ebe-a40d-3b467a55dce5	Other	\N	0	87	f	2
\.


--
-- Data for Name: group_dashboard; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.group_dashboard (id, uuid, organisation_id, is_primary_dashboard, audit_id, version, group_id, dashboard_id, is_voided) FROM stdin;
\.


--
-- Data for Name: group_privilege; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.group_privilege (id, uuid, group_id, privilege_id, subject_type_id, program_id, program_encounter_type_id, encounter_type_id, checklist_detail_id, allow, is_voided, version, organisation_id, audit_id) FROM stdin;
\.


--
-- Data for Name: group_role; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.group_role (id, uuid, group_subject_type_id, role, member_subject_type_id, is_primary, maximum_number_of_members, minimum_number_of_members, organisation_id, audit_id, is_voided, version) FROM stdin;
1	930dba89-afb6-4dec-b609-af881bd132c7	3	Head of household	2	f	1	1	2	99	f	0
2	9918b68f-1f27-4f80-96d4-ec02aeaae79d	3	Member	2	f	100	1	2	100	f	0
\.


--
-- Data for Name: group_subject; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.group_subject (id, uuid, group_subject_id, member_subject_id, group_role_id, membership_start_date, membership_end_date, organisation_id, audit_id, is_voided, version) FROM stdin;
\.


--
-- Data for Name: groups; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.groups (id, uuid, name, is_voided, version, organisation_id, audit_id, has_all_privileges) FROM stdin;
1	6e1c4136-8029-40d4-a622-2c9f2aa829c0	Everyone	f	0	1	83	t
2	b6d3ab33-7c9d-4714-9b5f-f602453d1a31	Everyone	f	0	2	88	t
\.


--
-- Data for Name: identifier_assignment; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.identifier_assignment (id, uuid, identifier_source_id, identifier, assignment_order, assigned_to_user_id, individual_id, program_enrolment_id, version, is_voided, organisation_id, audit_id) FROM stdin;
\.


--
-- Data for Name: identifier_source; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.identifier_source (id, uuid, name, type, catchment_id, facility_id, minimum_balance, batch_generation_size, options, version, is_voided, organisation_id, audit_id, min_length, max_length) FROM stdin;
\.


--
-- Data for Name: identifier_user_assignment; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.identifier_user_assignment (id, uuid, identifier_source_id, assigned_to_user_id, identifier_start, identifier_end, last_assigned_identifier, version, is_voided, organisation_id, audit_id) FROM stdin;
\.


--
-- Data for Name: individual; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.individual (id, uuid, address_id, observations, version, date_of_birth, date_of_birth_verified, gender_id, registration_date, organisation_id, first_name, last_name, is_voided, audit_id, facility_id, registration_location, subject_type_id, legacy_id) FROM stdin;
80	3efd5e1a-96a6-4a98-8581-9eea4742f581	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 1.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-01	f	4	2021-08-01	2	123	3546	f	721	\N	\N	2	1
81	20348c76-f7b8-467d-9939-fed6a3aaa249	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 2.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-02	f	4	2021-08-02	2	124	3547	f	722	\N	\N	2	2
82	71ee29c9-7547-4b73-b02c-f01eaadd029d	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 3.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-03	f	4	2021-08-03	2	125	3548	f	723	\N	\N	2	3
83	8875e2b8-bab6-44b8-afbd-48cbd99e283b	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 4.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-04	f	4	2021-08-04	2	126	3549	f	724	\N	\N	2	4
84	8a280f05-277b-46ca-bb87-5de56866763f	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 5.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-05	f	4	2021-08-05	2	127	3550	f	725	\N	\N	2	5
85	98593b71-537b-4139-bee1-17694ebb0660	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 6.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-06	f	4	2021-08-06	2	128	3551	f	726	\N	\N	2	6
86	b505f97c-8eda-47b9-8b81-7923f12ab75a	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 7.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-07	f	4	2021-08-07	2	129	3552	f	727	\N	\N	2	7
87	b16e558d-cf08-41f3-859c-38db8d1b6096	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 8.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-08	f	4	2021-08-08	2	130	3553	f	728	\N	\N	2	8
88	4326280a-abb1-4c32-a0db-66fd57835fe7	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 9.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-09	f	4	2021-08-09	2	131	3554	f	729	\N	\N	2	9
89	a620191f-fe3c-473a-9091-673e7c7fa345	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 10.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-10	f	4	2021-08-10	2	132	3555	f	730	\N	\N	2	10
90	d6d00b2c-ce14-482c-b589-d8fce8e523bb	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 11.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-11	f	4	2021-08-11	2	133	3546	f	731	\N	\N	2	11
91	2e167ea0-666c-434c-b9d6-e7d7b920128b	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 12.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-12	f	4	2021-08-12	2	134	3547	f	732	\N	\N	2	12
92	68b42998-dbb5-4275-9989-4141d8c08272	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 13.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-13	f	4	2021-08-13	2	135	3548	f	733	\N	\N	2	13
93	3dfd5d49-be99-467e-95e0-2c02168f6326	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 14.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-14	f	4	2021-08-14	2	136	3549	f	734	\N	\N	2	14
94	aa64247e-4d83-4ecf-b2d6-298eb88813a9	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 15.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-15	f	4	2021-08-15	2	137	3550	f	735	\N	\N	2	15
95	18eb8f6c-7ed5-41f8-ae86-0a5a1b89f40b	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 16.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-16	f	4	2021-08-16	2	138	3551	f	736	\N	\N	2	16
96	7b10a5a4-435c-4ae5-9d86-839249a1f463	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 17.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-17	f	4	2021-08-17	2	139	3552	f	737	\N	\N	2	17
97	62341382-5fbc-457a-a9b7-eedb8d3ce06c	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 18.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-18	f	4	2021-08-18	2	140	3553	f	738	\N	\N	2	18
98	a63230e5-1089-489c-87ee-afce3469fc09	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 19.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-19	f	4	2021-08-19	2	141	3554	f	739	\N	\N	2	19
99	ce258679-54ec-4178-857a-566f1ad3ea8f	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 20.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-20	f	4	2021-08-20	2	142	3555	f	740	\N	\N	2	20
100	62f82a9d-a12a-4592-a939-486f7bda2451	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 21.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-21	f	4	2021-08-21	2	143	3546	f	741	\N	\N	2	21
101	fc1074ef-f703-4983-ae86-e73acc5cfa14	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 22.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-22	f	4	2021-08-22	2	144	3547	f	742	\N	\N	2	22
102	e1dfdf05-6a3f-430d-9e65-2bbf543d3713	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 23.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-23	f	4	2021-08-23	2	145	3548	f	743	\N	\N	2	23
103	ac79a620-1bce-493d-b212-d2a6d23b48fb	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 24.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-24	f	4	2021-08-24	2	146	3549	f	744	\N	\N	2	24
104	37391218-73f9-4b68-8899-cf1e4d0b9510	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 25.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-25	f	4	2021-08-25	2	147	3550	f	745	\N	\N	2	25
105	053de5bf-9015-4cad-a4a0-c35627de5870	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 26.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-26	f	4	2021-08-26	2	148	3551	f	746	\N	\N	2	26
106	cc65598e-b550-4adc-bbf8-2cfd63f75a64	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 27.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-27	f	4	2021-08-27	2	149	3552	f	747	\N	\N	2	27
107	94832861-6459-4974-bbca-a76ef8e385ca	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 28.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-28	f	4	2021-08-28	2	150	3553	f	748	\N	\N	2	28
108	ac398c4a-66b8-48ee-90f9-8669bc1b965f	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 29.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-29	f	4	2021-08-29	2	151	3554	f	749	\N	\N	2	29
109	eae55442-27ca-4475-9f1f-b57f4c0f22f0	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 30.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-30	f	4	2021-08-30	2	152	3555	f	750	\N	\N	2	30
110	f0f10cde-8d34-4cf6-b05b-ff84ca15f07a	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 31.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-01-31	f	4	2021-08-31	2	153	3546	f	751	\N	\N	2	31
111	3df56b6a-14cb-49a9-9201-fd58a831015c	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 32.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-02-01	f	4	2021-09-01	2	154	3547	f	752	\N	\N	2	32
112	4710e905-27d2-45f7-8a83-5a1477b3c073	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 33.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-02-02	f	4	2021-09-02	2	155	3548	f	753	\N	\N	2	33
113	4d3b65c7-7949-4fe3-8388-e27bc6429a00	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 34.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "343e3f7d-eb1c-47b3-ada3-13250b7ba8b3"}	0	2002-02-03	f	4	2021-09-03	2	156	3549	f	754	\N	\N	2	34
114	8fb7e0a6-90c2-4b1d-8b73-c56283d06cbc	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 35.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-04	f	4	2021-09-04	2	157	3550	f	755	\N	\N	2	35
115	1ea31d07-6fc4-4e7e-8140-9dc7f3e6a2db	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 36.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-05	f	4	2021-09-05	2	158	3551	f	756	\N	\N	2	36
116	d685fe5f-c492-4296-ad80-32ffc3c3edfe	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 37.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-06	f	4	2021-09-06	2	159	3552	f	757	\N	\N	2	37
117	44bac64f-75d7-4037-960c-f49c2468bea3	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 38.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-07	f	4	2021-09-07	2	160	3553	f	758	\N	\N	2	38
118	344d6af9-9f3b-424e-832d-895f926f6258	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 39.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-08	f	4	2021-09-08	2	161	3554	f	759	\N	\N	2	39
119	a447fce0-9011-4bd7-b448-b47771b40188	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 40.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-09	f	4	2021-09-09	2	162	3555	f	760	\N	\N	2	40
120	0f4c05b4-28c6-429f-b367-f763810a1167	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 41.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-10	f	4	2021-09-10	2	163	3546	f	761	\N	\N	2	41
121	8563c7dc-a9ab-4dfe-a2c3-6288bff96953	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 42.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-11	f	4	2021-09-11	2	164	3547	f	762	\N	\N	2	42
122	7e1633a8-cb13-4b93-a280-bef8111d169e	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 43.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-12	f	4	2021-09-12	2	165	3548	f	763	\N	\N	2	43
123	18fd3501-bc7f-40b5-abf9-de9bb1f654b8	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 44.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-13	f	4	2021-09-13	2	166	3549	f	764	\N	\N	2	44
124	eb132994-789f-4753-b44a-5177fe7760f2	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 45.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-14	f	5	2021-09-14	2	167	3550	f	765	\N	\N	2	45
125	bcf0664a-677a-4ef0-a0af-b7b426bdd85e	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 46.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-15	f	5	2021-09-15	2	168	3551	f	766	\N	\N	2	46
126	7164d090-6750-4367-8007-ecc822e43b87	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 47.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-16	f	5	2021-09-16	2	169	3552	f	767	\N	\N	2	47
127	df35aba7-c57c-4af0-8c58-a29eebd76b48	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 48.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-17	f	5	2021-09-17	2	170	3553	f	768	\N	\N	2	48
128	83bb7ab4-3b0f-476e-bb82-c49dd2dec6c0	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 49.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-18	f	5	2021-09-18	2	171	3554	f	769	\N	\N	2	49
129	0927a2bf-8b8e-4d6d-85a3-9e65b4e60f3a	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 50.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-19	f	5	2021-09-19	2	172	3555	f	770	\N	\N	2	50
130	95951dfc-9ae6-4f4d-9e70-6b78cf6792cc	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 51.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-20	f	5	2021-09-20	2	173	3546	f	771	\N	\N	2	51
131	b6fc711e-563c-4568-a330-ac86b4bda81d	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 52.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-21	f	5	2021-09-21	2	174	3547	f	772	\N	\N	2	52
132	a16d72c6-c482-485c-900b-c44ada9cc320	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 53.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-22	f	5	2021-09-22	2	175	3548	f	773	\N	\N	2	53
133	d1f28204-5bc9-4686-b6f2-0fec3cd839f2	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 54.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-23	f	5	2021-09-23	2	176	3549	f	774	\N	\N	2	54
134	f95002e5-9b83-46fd-833a-0fd3dcf3838b	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 55.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-24	f	5	2021-09-24	2	177	3550	f	775	\N	\N	2	55
135	9801fc13-973b-4ec4-96e4-cb98cac6622a	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 56.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-25	f	5	2021-09-25	2	178	3551	f	776	\N	\N	2	56
136	b074e23e-5047-4f8c-a551-aec0f9b7b805	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 57.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-26	f	5	2021-09-26	2	179	3552	f	777	\N	\N	2	57
137	a18f93f3-a24a-4f47-bcee-8eafdc7abe0f	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 58.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-27	f	5	2021-09-27	2	180	3553	f	778	\N	\N	2	58
138	0effc481-7eaf-4f89-a860-56bd55d353f8	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 59.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-02-28	f	5	2021-09-28	2	181	3554	f	779	\N	\N	2	59
139	063fda1b-8212-436f-b623-e6586a905bc7	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 60.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-01	f	5	2021-09-29	2	182	3555	f	780	\N	\N	2	60
140	7cfa6ae0-00ba-4060-9e7c-049d9add9aea	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 61.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-02	f	5	2021-09-30	2	183	3546	f	781	\N	\N	2	61
141	1ea8996e-f9b4-4619-b346-e15ed51862f6	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 62.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-03	f	5	2021-10-01	2	184	3547	f	782	\N	\N	2	62
142	7b9994e0-b98a-4be2-99b2-9fa6a0de0ee6	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 63.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-04	f	5	2021-10-02	2	185	3548	f	783	\N	\N	2	63
143	409d9509-d919-4421-9b69-c07f86e36c67	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 64.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-05	f	5	2021-10-03	2	186	3549	f	784	\N	\N	2	64
144	ece42927-be98-4880-be34-4c3255581c5c	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 65.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-06	f	5	2021-10-04	2	187	3550	f	785	\N	\N	2	65
145	79290f1b-d3e7-4651-8fec-50537b66f956	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 66.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-07	f	5	2021-10-05	2	188	3551	f	786	\N	\N	2	66
146	1433f60b-ba5b-452f-9cfa-3ca804f10ab4	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 67.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-08	f	5	2021-10-06	2	189	3552	f	787	\N	\N	2	67
147	6d576558-f37d-4505-bd0d-0415b8978bbe	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 68.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-09	f	5	2021-10-07	2	190	3553	f	788	\N	\N	2	68
148	b5111c34-84f1-4675-a6ba-f3969eed6dbb	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 69.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-10	f	5	2021-10-08	2	191	3554	f	789	\N	\N	2	69
149	9128016c-9946-4745-b948-927bf55cb428	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 70.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-11	f	5	2021-10-09	2	192	3555	f	790	\N	\N	2	70
150	7121c197-7f21-4853-9f4e-acfb645ea1a6	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 71.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-12	f	5	2021-10-10	2	193	3546	f	791	\N	\N	2	71
151	0cb36062-0a44-4daf-8a93-0c20a7dca199	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 72.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-13	f	5	2021-10-11	2	194	3547	f	792	\N	\N	2	72
152	7cb945cd-4485-45a1-ad84-566b5ebccc41	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 73.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-14	f	5	2021-10-12	2	195	3548	f	793	\N	\N	2	73
153	2784fb97-1498-423d-81f4-777dd05d683f	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 74.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-15	f	5	2021-10-13	2	196	3549	f	794	\N	\N	2	74
154	1566d378-8132-449d-b1cd-2280b3fd285e	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 75.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-16	f	5	2021-10-14	2	197	3550	f	795	\N	\N	2	75
155	e44644b5-4093-4723-9458-2c787f607a54	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 76.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-17	f	5	2021-10-15	2	198	3551	f	796	\N	\N	2	76
156	29fa0146-760e-4fc4-b0ea-32e87818835e	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 77.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-18	f	5	2021-10-16	2	199	3552	f	797	\N	\N	2	77
157	decb46e9-ae83-4f81-b921-e790e77109a9	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 78.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-19	f	5	2021-10-17	2	200	3553	f	798	\N	\N	2	78
158	e5595d63-d175-42c7-bc0e-09b945952383	1	{"23cd954d-5f62-4ba1-a98b-b691161eedee": 79.0, "ac3189a1-42c0-4e48-87cd-11e233081e67": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "bc0820f0-462f-4dd9-aea7-e357679621d1": "f5cca911-2944-4636-ad00-356fb07fea67"}	0	2002-03-20	f	5	2021-10-18	2	201	3554	f	799	\N	\N	2	79
159	e10d9f75-7e4d-4e0b-a1dd-c0203f7cf137	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1001.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "5efbf27f-a6fc-46e1-8eca-147fcede670c"}	0	\N	f	\N	2021-10-01	2	67	\N	f	800	\N	\N	3	100
160	bc3c7ee2-2a87-40bc-b166-9895030e3a99	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1002.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "5efbf27f-a6fc-46e1-8eca-147fcede670c"}	0	\N	f	\N	2021-10-02	2	68	\N	f	801	\N	\N	3	101
161	13e8612e-c212-4cc4-8266-5d43a19321e6	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1003.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "5efbf27f-a6fc-46e1-8eca-147fcede670c"}	0	\N	f	\N	2021-10-03	2	69	\N	f	802	\N	\N	3	102
162	e12e52e4-76cd-4e7d-aef5-5fdca20d6f50	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1004.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "5efbf27f-a6fc-46e1-8eca-147fcede670c"}	0	\N	f	\N	2021-10-04	2	70	\N	f	803	\N	\N	3	103
163	c276412f-057e-48e6-b0eb-4b4f1d186907	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1005.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "5efbf27f-a6fc-46e1-8eca-147fcede670c"}	0	\N	f	\N	2021-10-05	2	71	\N	f	804	\N	\N	3	104
164	5a5c95dc-4c6e-43a1-98e9-da3828840e56	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1006.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "bb38fbc5-cbb4-4912-aa12-486abc54c812"}	0	\N	f	\N	2021-10-06	2	72	\N	f	805	\N	\N	3	105
165	942860ae-96e6-40f4-b92f-cf8e450307be	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1007.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "bb38fbc5-cbb4-4912-aa12-486abc54c812"}	0	\N	f	\N	2021-10-07	2	73	\N	f	806	\N	\N	3	106
166	86170fbb-d01d-45e2-8ef4-2d8588d0b46d	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1008.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "bb38fbc5-cbb4-4912-aa12-486abc54c812"}	0	\N	f	\N	2021-10-08	2	74	\N	f	807	\N	\N	3	107
167	8b62d851-fc90-453f-a65d-e756cc42bfed	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1009.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "bb38fbc5-cbb4-4912-aa12-486abc54c812"}	0	\N	f	\N	2021-10-09	2	75	\N	f	808	\N	\N	3	108
168	2af96d93-fdfb-47f8-b9c1-9db2783834b1	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1010.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "bb38fbc5-cbb4-4912-aa12-486abc54c812"}	0	\N	f	\N	2021-10-10	2	76	\N	f	809	\N	\N	3	109
169	cdcb4be5-8c6b-4196-9d85-a49ba5b00389	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1011.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "4c7c5ed5-1f6f-4203-a59d-7fcbedac8be8"}	0	\N	f	\N	2021-10-11	2	77	\N	f	810	\N	\N	3	110
170	67f40a9c-fa6c-49ff-8ebb-f0de0d67f813	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1012.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "4c7c5ed5-1f6f-4203-a59d-7fcbedac8be8"}	0	\N	f	\N	2021-10-12	2	78	\N	f	811	\N	\N	3	111
171	95625059-7806-4bc6-b3d0-26146190368a	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1013.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "4c7c5ed5-1f6f-4203-a59d-7fcbedac8be8"}	0	\N	f	\N	2021-10-13	2	79	\N	f	812	\N	\N	3	112
172	434b8509-10db-4d1f-84f8-71ddf41449fa	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1014.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "4c7c5ed5-1f6f-4203-a59d-7fcbedac8be8"}	0	\N	f	\N	2021-10-14	2	80	\N	f	813	\N	\N	3	113
173	054fcc31-4567-4e44-be6e-1a7ce8ad11a0	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1015.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "4c7c5ed5-1f6f-4203-a59d-7fcbedac8be8"}	0	\N	f	\N	2021-10-15	2	81	\N	f	814	\N	\N	3	114
174	fa839fd0-eccd-411c-9f3a-3cd94da951c6	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1016.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "4c7c5ed5-1f6f-4203-a59d-7fcbedac8be8"}	0	\N	f	\N	2021-10-16	2	82	\N	f	815	\N	\N	3	115
175	c2a82e05-88a2-4c53-ba15-9f1fcc479fe1	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1017.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "4c7c5ed5-1f6f-4203-a59d-7fcbedac8be8"}	0	\N	f	\N	2021-10-17	2	83	\N	f	816	\N	\N	3	116
176	c2cf98c4-7606-451a-b0d5-0000cbb13465	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1018.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "4c7c5ed5-1f6f-4203-a59d-7fcbedac8be8"}	0	\N	f	\N	2021-10-18	2	84	\N	f	817	\N	\N	3	117
177	fdce1551-78dd-4d64-a6e4-537456fb58bd	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1019.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "4c7c5ed5-1f6f-4203-a59d-7fcbedac8be8"}	0	\N	f	\N	2021-10-19	2	85	\N	f	818	\N	\N	3	118
178	e2ccd553-67f8-425b-bdc2-a3a7bd5e30c3	1	{"2c3f50c6-ccfa-40f0-8ba8-4bc85638d12d": 1020.0, "ea3e1478-7228-4cb3-9db6-73764a323c0a": "4c7c5ed5-1f6f-4203-a59d-7fcbedac8be8"}	0	\N	f	\N	2021-10-20	2	86	\N	f	819	\N	\N	3	119
\.


--
-- Data for Name: individual_relation; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.individual_relation (id, uuid, name, is_voided, organisation_id, version, audit_id) FROM stdin;
1	7e876220-20b4-4c17-87b7-0e235926f7a6	son	f	1	1	46
2	91fd32f2-0261-46a1-92e4-4c201247c9a3	daughter	f	1	1	47
3	eeb49484-a07d-49f7-bb4b-932b713fbc66	father	f	1	1	48
4	5a77c22b-a24f-456e-84a3-9bd12e104f73	mother	f	1	1	49
5	334ea293-fd10-4dab-92f3-04ce153e27aa	husband	f	1	1	50
6	0ab14ce3-cbdb-4cb7-8601-353bebe408c9	wife	f	1	1	51
7	4809d13f-4ab1-49d7-aa57-ee71a821bc3f	brother	f	1	1	52
8	a081882c-6775-4caa-98cd-9720a0d11dfc	sister	f	1	1	53
9	4474c0f3-9d35-4622-a65a-5688f633a274	grandson	f	1	1	54
10	82691c26-c042-48d4-972b-664bcb348fc4	granddaughter	f	1	1	55
11	0d0b0e92-79d4-49c1-b33b-cf0508ea550c	grandfather	f	1	1	56
12	8c382726-92be-4e3e-8b6e-2b032c5cd6a8	grandmother	f	1	1	57
13	7e876220-20b4-4c17-87b7-0e235926f7a6	son	f	2	0	456
14	91fd32f2-0261-46a1-92e4-4c201247c9a3	daughter	f	2	0	458
15	eeb49484-a07d-49f7-bb4b-932b713fbc66	father	f	2	0	460
16	5a77c22b-a24f-456e-84a3-9bd12e104f73	mother	f	2	0	462
17	334ea293-fd10-4dab-92f3-04ce153e27aa	husband	f	2	0	464
18	0ab14ce3-cbdb-4cb7-8601-353bebe408c9	wife	f	2	0	466
19	4809d13f-4ab1-49d7-aa57-ee71a821bc3f	brother	f	2	0	468
20	a081882c-6775-4caa-98cd-9720a0d11dfc	sister	f	2	0	470
21	4474c0f3-9d35-4622-a65a-5688f633a274	grandson	f	2	0	472
22	82691c26-c042-48d4-972b-664bcb348fc4	granddaughter	f	2	0	474
23	0d0b0e92-79d4-49c1-b33b-cf0508ea550c	grandfather	f	2	0	476
24	8c382726-92be-4e3e-8b6e-2b032c5cd6a8	grandmother	f	2	0	478
25	a37480e4-5a30-46b9-8a0c-7088de31a452	Son in law	f	2	0	480
26	8389106f-4baf-4c5c-b036-b0ec636e86dc	Uncle	f	2	0	482
27	50842ea2-9722-4e2b-857a-db815d92b31f	Brother in law	f	2	0	484
28	d5093bbe-8ae0-4ab4-9ccb-5e9d78ae7ed1	Sister in law	f	2	0	486
29	d3832850-6e19-4966-b2f8-582b15afb562	Father in law	f	2	0	488
30	9c2bcb63-9ebb-401f-b469-04ece9089ade	Mother in law	f	2	0	490
31	1734b609-c3c2-4aab-a5fc-02290adac537	Nephew	f	2	0	492
32	4c6ef736-7b68-48de-aeb7-a662201ebfdd	Niece	f	2	0	494
33	7344325b-0e0f-45da-83f1-97dc4684d100	Aunty	f	2	0	496
34	4c5f9ab8-f1bf-4425-b9b5-01f9e35fa205	Daughter-in-law	f	2	0	498
35	146b6ea3-f0ae-4d35-9d6f-ce89e58e0429	Friend	f	2	0	500
36	47e1d1c3-05a4-4e4c-9b7c-29c77d060979	Roommate	f	2	0	504
37	dc15eb4d-e931-492a-b832-9fca71c34670	Friend's Family	f	2	0	508
\.


--
-- Data for Name: individual_relation_gender_mapping; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.individual_relation_gender_mapping (id, uuid, relation_id, gender_id, is_voided, organisation_id, version, audit_id) FROM stdin;
1	f6e6f570-aaaf-4069-a14d-e2649e9710d7	1	2	f	1	1	58
2	2eb6adbc-5a55-46f8-925e-f3061fd16e29	2	1	f	1	1	59
3	7c97fe3b-c2e8-437d-a43b-1e6d4357a8d1	3	2	f	1	1	60
4	1896f28c-cace-4034-bf29-c0ab42a4c41e	4	1	f	1	1	61
5	f2916111-b753-4004-85d5-a63856ce4462	5	2	f	1	1	62
6	ec90bb6f-2ccb-4e4c-be01-ae95cc441b98	6	1	f	1	1	63
7	ac49854a-776d-4311-9b13-c536b97e0c48	7	2	f	1	1	64
8	90de5a8a-cbbc-4bab-8019-edf3f1d02317	8	1	f	1	1	65
9	0dff0a2b-ac07-4c31-8338-c32af05b31fc	9	2	f	1	1	66
10	db89d727-3c3e-45fc-a18d-a58c3098d5ca	10	1	f	1	1	67
11	50a3aa9e-04be-465f-be7b-22e0ab8e500e	11	2	f	1	1	68
12	29b20f70-6b3e-481e-96cf-c4fe0e2d46c1	12	1	f	1	1	69
13	54e4d921-4641-43c4-bbc7-87c36b7371c4	13	4	f	2	0	457
14	18770cc8-c926-4503-b5ff-01edae3c1c13	14	5	f	2	0	459
15	ab113a00-6a93-4656-9645-3d99e9489cc2	15	4	f	2	0	461
16	4f0ca9a7-1250-4675-807f-e06caf817b14	16	5	f	2	0	463
17	901717d2-9481-40bc-a5b3-6fe3b03bc00e	17	4	f	2	0	465
18	db38e7e3-0219-489f-a500-ce2da873d511	18	5	f	2	0	467
19	a7ff4c34-9b81-4e60-8c3c-93252fb890bd	19	4	f	2	0	469
20	d523ba2b-29ba-4ce0-8a49-c3f0ef19018f	20	5	f	2	0	471
21	e242f917-e95f-4803-bda4-9e6798ebc9e3	21	4	f	2	0	473
22	ae28d13f-627b-4d17-a62e-ffc1dfc46e68	22	5	f	2	0	475
23	8a8dc26a-d17f-4105-810a-00ab9a994eee	23	4	f	2	0	477
24	63bf7330-8198-466d-a9b1-bb431a1eefd3	24	5	f	2	0	479
25	e47d3e5b-f5c9-488f-82ba-8ee85caefcf3	25	4	f	2	0	481
26	f73d4fbf-1bd2-4f21-a24c-c3ead68c121d	26	4	f	2	0	483
27	9cc58da5-ab06-4459-907a-7953bcff273b	27	4	f	2	0	485
28	47cb7981-e39c-4ac7-af73-a2f592aa04c1	28	5	f	2	0	487
29	7f8ca6fa-ba53-4a3a-92d3-6a0505b45aa8	29	4	f	2	0	489
30	58f8fe2b-b068-4131-b250-d284ff485368	30	5	f	2	0	491
31	6768a0ab-47d9-481f-8c8f-9af560143bfe	31	4	f	2	0	493
32	bac216c2-d240-4388-9324-a6373f9da03c	32	5	f	2	0	495
33	ffe0e14a-ecdc-4c92-9fba-abd29086595f	33	5	f	2	0	497
34	f78cee87-ad61-4828-8d4e-53c18f6814b8	34	5	f	2	0	499
35	1f2d3f35-8cc0-42a5-85e5-68e0b544e891	35	6	f	2	0	501
36	abdaedd3-186b-4d01-bbcb-bd8d50d2ac59	35	4	f	2	0	502
37	e8e24f55-bba2-410c-ab3a-43f868eb8620	35	5	f	2	0	503
38	57a72a72-d449-4e8b-90ec-f8ba75fd593d	36	6	f	2	0	505
39	67a69465-497c-46cc-b573-2760b7f9ac72	36	4	f	2	0	506
40	7bbff7e0-2477-4750-9e81-97aed13000c0	36	5	f	2	0	507
41	7dba3774-f918-40a5-8f26-82d7b950abe7	37	6	f	2	0	509
42	cbc06873-e457-49a9-b5a3-41a7853e4cdb	37	4	f	2	0	510
43	4633329c-fab9-40f9-9e52-e2bbfb06416d	37	5	f	2	0	511
\.


--
-- Data for Name: individual_relationship; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.individual_relationship (id, uuid, individual_a_id, individual_b_id, relationship_type_id, enter_date_time, exit_date_time, exit_observations, is_voided, organisation_id, version, audit_id) FROM stdin;
\.


--
-- Data for Name: individual_relationship_type; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.individual_relationship_type (id, uuid, name, individual_a_is_to_b_relation_id, individual_b_is_to_a_relation_id, is_voided, organisation_id, version, audit_id) FROM stdin;
1	1d9c019a-9350-44f9-9ef9-a699f0d94a13	father-son	3	1	f	1	1	70
2	1db2a945-0692-481e-a68c-aaf7cc246d64	father-daughter	3	2	f	1	1	71
3	d84d15c2-3d09-416e-8c26-9709ce3c90da	mother-son	4	1	f	1	1	72
4	99ad5750-bdf8-40e6-964c-01cf806707b7	mother-daughter	4	2	f	1	1	73
5	89d85d58-de14-4249-b9bb-61d4abb94b77	spouse	5	6	f	1	1	74
6	2a6a496c-6063-4383-8857-0c10a831d85c	brother-brother	7	7	f	1	1	75
7	3731d4b6-80f4-410b-baf7-2c0fcc38fe1f	sister-sister	8	8	f	1	1	76
8	765bc1ed-441a-414d-b62a-672103b35c95	brother-sister	7	8	f	1	1	77
9	8458bbe3-aa87-4c7c-b5e2-a139e01bd88f	grandfather-grandson	11	9	f	1	1	78
10	1724ff11-95c5-42c2-b697-f40f1105d696	grandfather-granddaughter	11	10	f	1	1	79
11	28edbf6e-98eb-4218-8950-01d97be476da	grandmother-grandson	12	9	f	1	1	80
12	ace301c1-2815-42c1-943e-c7b44f64b376	grandmother-granddaughter	12	10	f	1	1	81
13	1d9c019a-9350-44f9-9ef9-a699f0d94a13	father-son	15	13	f	2	0	512
14	1db2a945-0692-481e-a68c-aaf7cc246d64	father-daughter	15	14	f	2	0	513
15	d84d15c2-3d09-416e-8c26-9709ce3c90da	mother-son	16	13	f	2	0	514
16	99ad5750-bdf8-40e6-964c-01cf806707b7	mother-daughter	16	14	f	2	0	515
17	89d85d58-de14-4249-b9bb-61d4abb94b77	husband-wife	17	18	f	2	0	516
18	2a6a496c-6063-4383-8857-0c10a831d85c	brother-brother	19	19	f	2	0	517
19	3731d4b6-80f4-410b-baf7-2c0fcc38fe1f	sister-sister	20	20	f	2	0	518
20	765bc1ed-441a-414d-b62a-672103b35c95	brother-sister	19	20	f	2	0	519
21	8458bbe3-aa87-4c7c-b5e2-a139e01bd88f	grandfather-grandson	23	21	f	2	0	520
22	1724ff11-95c5-42c2-b697-f40f1105d696	grandfather-granddaughter	23	22	f	2	0	521
23	28edbf6e-98eb-4218-8950-01d97be476da	grandmother-grandson	24	21	f	2	0	522
24	ace301c1-2815-42c1-943e-c7b44f64b376	grandmother-granddaughter	24	22	f	2	0	523
25	9303c4ce-4493-4a7b-8d13-17567538c83d	Friend-Friend	35	35	f	2	0	524
26	7dcb898a-0f52-45a1-9495-6ec1c2b5077f	Son in law-Father in law	25	29	f	2	0	525
27	5abf1b5d-8153-4092-adf5-eb308be90fb5	Daughter-in-law-Mother in law	34	30	f	2	0	526
28	21a41490-016e-4d33-9f8b-f85eb69ced85	Brother in law-Brother in law	27	27	f	2	0	527
29	53493e72-aa49-4f71-ad68-837b74886784	Brother in law-Sister in law	27	28	f	2	0	528
30	0236bd49-88ed-404d-989a-b031f4ff7326	Nephew-Aunty	31	33	f	2	0	529
31	ba7f80d4-3b0b-4d6a-9c75-4e32ec10c45d	Niece-Aunty	32	33	f	2	0	530
32	9a1e03af-103e-4a0e-b65d-9464ec1c051a	Sister in law-Sister in law	28	28	f	2	0	531
33	85db6952-ba6c-49e9-96c4-9e78fa7cbb99	Uncle-Nephew	26	31	f	2	0	532
34	6d666124-d631-4b26-bd74-81334eb48016	Uncle-Niece	26	32	f	2	0	533
35	ec597cf9-a109-487b-9764-c05e806435c9	Roommate-Roommate	36	36	f	2	0	534
36	e61b9726-2431-4c26-87e6-dee6d3496e02	Friend's Family-Friend's Family	37	37	f	2	0	535
\.


--
-- Data for Name: individual_relative; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.individual_relative (id, uuid, individual_id, relative_individual_id, relation_id, enter_date_time, exit_date_time, is_voided, organisation_id, version, audit_id) FROM stdin;
\.


--
-- Data for Name: location_location_mapping; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.location_location_mapping (id, location_id, parent_location_id, version, audit_id, uuid, is_voided, organisation_id) FROM stdin;
\.


--
-- Data for Name: msg91_config; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.msg91_config (id, uuid, auth_key, otp_sms_template_id, otp_length, organisation_id, audit_id, is_voided, version) FROM stdin;
\.


--
-- Data for Name: news; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.news (id, organisation_id, uuid, title, content, contenthtml, hero_image, published_date, is_voided, audit_id, version) FROM stdin;
\.


--
-- Data for Name: non_applicable_form_element; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.non_applicable_form_element (id, organisation_id, form_element_id, is_voided, version, audit_id, uuid) FROM stdin;
\.


--
-- Data for Name: operational_encounter_type; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.operational_encounter_type (id, uuid, organisation_id, encounter_type_id, version, audit_id, name, is_voided) FROM stdin;
7	68e3aaf7-ee35-4555-a771-f06b5bc2e27d	2	16	0	606	Child followup	f
8	64dfbf6c-49f0-4c8c-8144-052d88c39061	2	17	0	615	ANC followup	f
9	a333412a-e0b0-4d51-b985-5399a3b9f496	2	18	0	630	Survey	f
\.


--
-- Data for Name: operational_program; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.operational_program (id, uuid, organisation_id, program_id, version, audit_id, name, is_voided, program_subject_label) FROM stdin;
1	aaf5a933-6e33-4af3-8a27-c4c3c64dfc4c	2	1	0	132	Eligible couple (voided~1)	t	\N
2	82d40b5b-c44a-4104-9faa-380f386ee997	2	2	0	572	Child	f	\N
3	01ca6d4a-fa53-48c8-a050-b2dd8284a8ce	2	3	0	578	Pregnancy	f	\N
\.


--
-- Data for Name: operational_subject_type; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.operational_subject_type (id, uuid, name, subject_type_id, organisation_id, is_voided, audit_id, version) FROM stdin;
1	77e58956-9686-4a0b-8378-c1411cc9d083	Person	2	2	f	95	0
2	e1b9dc2a-98df-4b2b-85e3-a4cd780bd182	Household	3	2	f	101	0
\.


--
-- Data for Name: organisation; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.organisation (id, name, db_user, uuid, parent_organisation_id, is_voided, media_directory, username_suffix, account_id, schema_name) FROM stdin;
1	OpenCHS	openchs_impl	3539a906-dfae-4ec3-8fbb-1b08f35c3884	\N	f	openchs	\N	1	openchs_impl
2	Test organisation	test	0512d373-d0ee-4bb1-a603-170c754cd4e5	\N	f	test	test	1	test
\.


--
-- Data for Name: organisation_config; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.organisation_config (id, uuid, organisation_id, settings, audit_id, version, is_voided, worklist_updation_rule) FROM stdin;
1	737b43e0-1363-4fe0-90cb-84a5e9b6d959	2	{"languages": ["en", "mr_IN"], "saveDrafts": true, "searchFilters": [{"type": "Name", "widget": "Default", "titleKey": "Name", "subjectTypeUUID": "9f2af1f9-e150-4f8e-aad3-40bb7eb05aa3"}, {"type": "Age", "widget": "Default", "titleKey": "Age", "subjectTypeUUID": "9f2af1f9-e150-4f8e-aad3-40bb7eb05aa3"}, {"type": "Address", "widget": "Default", "titleKey": "Address", "subjectTypeUUID": "9f2af1f9-e150-4f8e-aad3-40bb7eb05aa3"}, {"type": "SearchAll", "widget": "Default", "titleKey": "SearchAll", "subjectTypeUUID": "9f2af1f9-e150-4f8e-aad3-40bb7eb05aa3"}, {"type": "Name", "widget": "Default", "titleKey": "Name", "subjectTypeUUID": "e9f5e678-6bce-4254-ab36-b8838ceb9fcc"}, {"type": "Address", "widget": "Default", "titleKey": "Address", "subjectTypeUUID": "e9f5e678-6bce-4254-ab36-b8838ceb9fcc"}, {"type": "SearchAll", "widget": "Default", "titleKey": "Search All", "subjectTypeUUID": "e9f5e678-6bce-4254-ab36-b8838ceb9fcc"}, {"type": "Concept", "scope": "registration", "titleKey": "Household Number", "conceptName": "Household number", "conceptUUID": "24dabc3a-6562-4521-bd42-5fff11ea5c46", "conceptDataType": "Text", "scopeParameters": {"programUUIDs": [], "encounterTypeUUIDs": []}, "subjectTypeUUID": "e9f5e678-6bce-4254-ab36-b8838ceb9fcc"}], "enableComments": true, "hideDateOfBirth": false, "myDashboardFilters": [{"type": "Address", "widget": "Default", "titleKey": "Address", "subjectTypeUUID": "9f2af1f9-e150-4f8e-aad3-40bb7eb05aa3"}, {"type": "Address", "titleKey": "Address", "subjectTypeUUID": "e9f5e678-6bce-4254-ab36-b8838ceb9fcc"}], "customRegistrationLocations": []}	89	0	f	\N
\.


--
-- Data for Name: organisation_group; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.organisation_group (id, name, db_user, account_id) FROM stdin;
\.


--
-- Data for Name: organisation_group_organisation; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.organisation_group_organisation (id, name, organisation_group_id, organisation_id) FROM stdin;
\.


--
-- Data for Name: platform_translation; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.platform_translation (id, uuid, translation_json, is_voided, platform, language, version, audit_id) FROM stdin;
\.


--
-- Data for Name: privilege; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.privilege (id, uuid, name, description, entity_type, is_voided, created_date_time, last_modified_date_time) FROM stdin;
1	67410e50-8b40-4735-bfb4-135b13580027	View subject	View subject	Subject	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.092+05:30
2	46c3aa38-1ef5-4639-a406-d0b4f9bcb420	Register subject	Register subject	Subject	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.093+05:30
3	db791f27-0c04-4060-8938-6f18fb4069ee	Edit subject	Edit subject	Subject	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.094+05:30
4	088a30ca-9ce2-4ab3-a517-e249cc43a4bf	Void subject	Void subject	Subject	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.095+05:30
5	020c5e18-01f0-469a-8a4a-e27cbc2a2292	Enrol subject	Enrol subject	Enrolment	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.096+05:30
6	583188ff-cd10-4615-9e22-000ce0bc6d80	View enrolment details	View enrolment details	Enrolment	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.097+05:30
7	a1dcc42f-eed4-4baf-807a-4f6e238f1cba	Edit enrolment details	Edit enrolment details	Enrolment	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.098+05:30
8	bd419d1e-cfc6-4607-8cad-38871721115d	Exit enrolment	Exit enrolment	Enrolment	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.099+05:30
9	9f2a3495-93b7-47c3-8560-d572b6a9fc61	View visit	View visit	Encounter	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.1+05:30
10	867d5de9-0bf3-434c-9cb1-bd09a05250af	Schedule visit	Schedule visit	Encounter	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.101+05:30
11	e3352a23-f478-4166-af11-e949cc69e1cc	Perform visit	Perform visit	Encounter	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.102+05:30
12	85ce5ed4-1490-4980-8c64-63fb423b5f14	Edit visit	Edit visit	Encounter	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.103+05:30
13	51fa8342-3228-4945-88eb-4b41970fa425	Cancel visit	Cancel visit	Encounter	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.104+05:30
14	450a83ed-0e49-4b4c-8b8c-2dbfebcd7e5d	View checklist	View checklist	Checklist	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.105+05:30
15	79bcebce-4177-471d-8f0d-5558fbd91b76	Edit checklist	Edit checklist	Checklist	f	2021-11-14 10:53:12.563409+05:30	2021-11-14 10:53:14.106+05:30
16	0843ee63-721c-49c5-8374-818b512caf82	Add member	Add member	Subject	f	2021-11-14 10:53:12.656548+05:30	2021-11-14 10:53:14.107+05:30
17	d9d7ae77-a67e-4644-8976-5b3551106a53	Edit member	Edit member	Subject	f	2021-11-14 10:53:12.656548+05:30	2021-11-14 10:53:14.108+05:30
18	f2915fc4-d2cb-492a-b9bc-88a7bae11b75	Remove member	Remove member	Subject	f	2021-11-14 10:53:12.656548+05:30	2021-11-14 10:53:14.109+05:30
19	37ae14f9-e6ac-4d24-951a-e457b0cdcf00	Approve Subject	Approve Subject	Subject	f	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.11+05:30
21	31449500-4b8d-43db-855a-c9099600ee32	Approve Enrolment	Approve Enrolment	Enrolment	f	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.112+05:30
23	7d725125-6b48-44d2-a53b-bf847ae8a3d0	Approve Encounter	Approve Encounter	Encounter	f	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.114+05:30
25	9635465c-f0bb-4b10-8cf9-eda181fe7a4f	Approve ChecklistItem	Approve ChecklistItem	ChecklistItem	f	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.116+05:30
20	8a2e92c2-8af2-4f1c-896e-317c0bb4095f	Reject Subject	Reject Subject	Subject	t	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.111+05:30
22	8b0089f6-8c52-471c-bb89-8d4c1800dbcd	Reject Enrolment	Reject Enrolment	Enrolment	t	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.113+05:30
24	ca4428e7-dc4c-4dad-8190-451d8ccd7402	Reject Encounter	Reject Encounter	Encounter	t	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.115+05:30
26	54654e97-acb6-4a89-8754-82a56af93f37	Reject ChecklistItem	Reject ChecklistItem	ChecklistItem	t	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.117+05:30
\.


--
-- Data for Name: program; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.program (id, uuid, name, version, colour, organisation_id, audit_id, is_voided, enrolment_summary_rule, enrolment_eligibility_check_rule, active) FROM stdin;
1	fdf5c253-c49f-43e1-9591-4556a3ea36d4	Eligible couple (voided~1)	0	orangered	2	131	t	\N	\N	t
2	e799c74f-0bc1-4d5d-a382-1e7a9d2ead3d	Child	0	#ffc000	2	571	f			t
3	0a40550a-9689-41a9-974e-24e3510bc089	Pregnancy	0	#00ffa7	2	577	f			t
\.


--
-- Data for Name: program_encounter; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.program_encounter (id, observations, earliest_visit_date_time, encounter_date_time, program_enrolment_id, uuid, version, encounter_type_id, name, max_visit_date_time, organisation_id, cancel_date_time, cancel_observations, audit_id, is_voided, encounter_location, cancel_location, legacy_id) FROM stdin;
2	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-11 00:00:00+05:30	2021-09-11 00:00:00+05:30	2	427e8efd-78d0-4c3c-a040-93bc1ef5d82a	0	17	\N	2021-09-11 00:00:00+05:30	2	\N	\N	860	f	\N	\N	2
3	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-12 00:00:00+05:30	2021-09-12 00:00:00+05:30	3	ef698efd-2467-4e5d-a462-b19c93726299	0	17	\N	2021-09-12 00:00:00+05:30	2	\N	\N	861	f	\N	\N	3
4	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-13 00:00:00+05:30	2021-09-13 00:00:00+05:30	4	2e3d1f0b-7971-46ee-a484-745565cdd6e9	0	17	\N	2021-09-13 00:00:00+05:30	2	\N	\N	862	f	\N	\N	4
5	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-14 00:00:00+05:30	2021-09-14 00:00:00+05:30	5	d323927a-c5cd-4a95-be09-859d0895df36	0	17	\N	2021-09-14 00:00:00+05:30	2	\N	\N	863	f	\N	\N	5
6	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-15 00:00:00+05:30	2021-09-15 00:00:00+05:30	6	b40037fd-90bb-4252-8b8f-55159410b24c	0	17	\N	2021-09-15 00:00:00+05:30	2	\N	\N	864	f	\N	\N	6
7	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-16 00:00:00+05:30	2021-09-16 00:00:00+05:30	7	d5371082-e874-47ad-8958-291d15d62d26	0	17	\N	2021-09-16 00:00:00+05:30	2	\N	\N	865	f	\N	\N	7
8	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-17 00:00:00+05:30	2021-09-17 00:00:00+05:30	8	596ce29c-4f59-4e62-8055-660e1ce3d981	0	17	\N	2021-09-17 00:00:00+05:30	2	\N	\N	866	f	\N	\N	8
9	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-18 00:00:00+05:30	2021-09-18 00:00:00+05:30	9	f8d639ab-c74c-49b0-9c25-7b71c7a2ffae	0	17	\N	2021-09-18 00:00:00+05:30	2	\N	\N	867	f	\N	\N	9
10	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-19 00:00:00+05:30	2021-09-19 00:00:00+05:30	10	6f5e15a2-4223-417c-bfbc-7eccbf5f350f	0	17	\N	2021-09-19 00:00:00+05:30	2	\N	\N	868	f	\N	\N	10
11	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-20 00:00:00+05:30	2021-09-20 00:00:00+05:30	11	68ca0330-5b0a-43f1-963a-8ee63c59a0c2	0	17	\N	2021-09-20 00:00:00+05:30	2	\N	\N	869	f	\N	\N	11
12	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-21 00:00:00+05:30	2021-09-21 00:00:00+05:30	12	16285534-a486-4f4c-8bfa-f7cb174a96e1	0	17	\N	2021-09-21 00:00:00+05:30	2	\N	\N	870	f	\N	\N	12
13	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-22 00:00:00+05:30	2021-09-22 00:00:00+05:30	13	115e575b-00e5-4ec3-ba91-f1b91ad8c4ca	0	17	\N	2021-09-22 00:00:00+05:30	2	\N	\N	871	f	\N	\N	13
14	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-23 00:00:00+05:30	2021-09-23 00:00:00+05:30	14	24a68ac6-7322-4196-b0de-be8e2b7a7d7e	0	17	\N	2021-09-23 00:00:00+05:30	2	\N	\N	872	f	\N	\N	14
15	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-24 00:00:00+05:30	2021-09-24 00:00:00+05:30	15	7ee1fa68-59b3-4449-b2ae-f6534f0b8e67	0	17	\N	2021-09-24 00:00:00+05:30	2	\N	\N	873	f	\N	\N	15
16	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-25 00:00:00+05:30	2021-09-25 00:00:00+05:30	16	3b5cd601-3ce2-4689-8fcc-f66e8777df7a	0	17	\N	2021-09-25 00:00:00+05:30	2	\N	\N	874	f	\N	\N	16
17	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-26 00:00:00+05:30	2021-09-26 00:00:00+05:30	1	50876a22-4053-4520-9ce9-8546c4c570ff	0	17	\N	2021-09-26 00:00:00+05:30	2	\N	\N	875	f	\N	\N	17
18	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-27 00:00:00+05:30	2021-09-27 00:00:00+05:30	2	0d24c67b-cc04-4029-a270-10bb3c5511ca	0	17	\N	2021-09-27 00:00:00+05:30	2	\N	\N	876	f	\N	\N	18
19	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-28 00:00:00+05:30	2021-09-28 00:00:00+05:30	3	684cf27c-1ad0-420f-8d31-5733e02e82bf	0	17	\N	2021-09-28 00:00:00+05:30	2	\N	\N	877	f	\N	\N	19
20	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-29 00:00:00+05:30	2021-09-29 00:00:00+05:30	4	b748511f-0146-47af-b337-2129d557ee12	0	17	\N	2021-09-29 00:00:00+05:30	2	\N	\N	878	f	\N	\N	20
21	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-09-30 00:00:00+05:30	2021-09-30 00:00:00+05:30	5	f069da28-c86f-4689-92e0-ea7aeb73061d	0	17	\N	2021-09-30 00:00:00+05:30	2	\N	\N	879	f	\N	\N	21
22	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-01 00:00:00+05:30	2021-10-01 00:00:00+05:30	6	c0445f71-5aed-4910-a95f-3c0b5a78a03b	0	17	\N	2021-10-01 00:00:00+05:30	2	\N	\N	880	f	\N	\N	22
23	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-02 00:00:00+05:30	2021-11-02 00:00:00+05:30	7	c293dcb4-ed31-4b53-a82c-cdbe6fe2a2ee	0	17	\N	2021-10-02 00:00:00+05:30	2	\N	\N	881	f	\N	\N	23
24	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-03 00:00:00+05:30	2021-11-03 00:00:00+05:30	8	cdc303f8-99ea-4a65-a11c-8ed866f4b95b	0	17	\N	2021-10-03 00:00:00+05:30	2	\N	\N	882	f	\N	\N	24
25	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-04 00:00:00+05:30	2021-11-04 00:00:00+05:30	9	5d4c57d9-9587-46a5-a5f1-9caff71503d8	0	17	\N	2021-10-04 00:00:00+05:30	2	\N	\N	883	f	\N	\N	25
26	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-05 00:00:00+05:30	2021-11-05 00:00:00+05:30	10	f80221c8-a073-4161-a5e1-76c2d4d5743f	0	17	\N	2021-10-05 00:00:00+05:30	2	\N	\N	884	f	\N	\N	26
1	{}	2021-09-10 00:00:00+05:30	\N	1	994aabc7-a5c1-464f-98bc-ffbb64d27018	0	17	\N	2021-09-10 00:00:00+05:30	2	2021-11-14 12:05:01.265411+05:30	{}	859	f	\N	\N	1
27	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-06 00:00:00+05:30	2021-11-06 00:00:00+05:30	11	303dbd85-5f23-47aa-8b56-ce43c5780368	0	17	\N	2021-10-06 00:00:00+05:30	2	\N	\N	885	f	\N	\N	27
28	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-07 00:00:00+05:30	2021-11-07 00:00:00+05:30	12	b6f86870-73df-487f-b2ba-c84d7233c79f	0	17	\N	2021-10-07 00:00:00+05:30	2	\N	\N	886	f	\N	\N	28
29	{"75ffb941-c068-4c47-8364-92e279381d61": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "ad90e65c-7ac7-440a-a818-075e2bd65e7a": "53d8be75-29f3-4e96-90ac-0f4afc321fba"}	2021-10-08 00:00:00+05:30	2021-11-08 00:00:00+05:30	13	eaab05c0-5dc0-4179-a11e-82b6d41432f5	0	17	\N	2021-10-08 00:00:00+05:30	2	\N	\N	887	f	\N	\N	29
30	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 1.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 2.0}	2021-10-01 00:00:00+05:30	2021-10-01 00:00:00+05:30	20	5e0dedba-26b9-4eba-8bbd-cb663bde2553	0	16	\N	2021-10-01 00:00:00+05:30	2	\N	\N	908	f	\N	\N	100
31	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 2.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 3.0}	2021-10-02 00:00:00+05:30	2021-10-02 00:00:00+05:30	21	7f544364-c53a-42e4-9f5f-f6619f0777b6	0	16	\N	2021-10-02 00:00:00+05:30	2	\N	\N	909	f	\N	\N	101
32	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 3.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 4.0}	2021-10-03 00:00:00+05:30	2021-10-03 00:00:00+05:30	22	703324e5-e297-4973-9a08-39b9511d1c4b	0	16	\N	2021-10-03 00:00:00+05:30	2	\N	\N	910	f	\N	\N	102
33	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 4.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 5.0}	2021-10-04 00:00:00+05:30	2021-10-04 00:00:00+05:30	23	9eb5340a-dd3b-46be-8b83-f110cb1b1cfa	0	16	\N	2021-10-04 00:00:00+05:30	2	\N	\N	911	f	\N	\N	103
34	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 5.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 6.0}	2021-10-05 00:00:00+05:30	2021-10-05 00:00:00+05:30	24	436ec385-ae7e-46f2-b210-3557536d4fb7	0	16	\N	2021-10-05 00:00:00+05:30	2	\N	\N	912	f	\N	\N	104
35	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 6.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 7.0}	2021-10-06 00:00:00+05:30	2021-10-06 00:00:00+05:30	25	af580d33-12d2-4f74-990b-27c5dee8c00e	0	16	\N	2021-10-06 00:00:00+05:30	2	\N	\N	913	f	\N	\N	105
36	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 7.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 8.0}	2021-10-07 00:00:00+05:30	2021-10-07 00:00:00+05:30	26	30830a11-0a36-4432-867b-f56d29b967a3	0	16	\N	2021-10-07 00:00:00+05:30	2	\N	\N	914	f	\N	\N	106
37	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 8.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 9.0}	2021-10-08 00:00:00+05:30	2021-10-08 00:00:00+05:30	27	23af2803-92a6-4e1e-8da2-61ae16e27960	0	16	\N	2021-10-08 00:00:00+05:30	2	\N	\N	915	f	\N	\N	107
38	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 9.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 10.0}	2021-10-09 00:00:00+05:30	2021-10-09 00:00:00+05:30	28	be5da137-a1be-4a36-a6f5-fd75aa09b3da	0	16	\N	2021-10-09 00:00:00+05:30	2	\N	\N	916	f	\N	\N	108
39	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 10.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 11.0}	2021-10-10 00:00:00+05:30	2021-10-10 00:00:00+05:30	29	38b9861e-7f14-4628-baf9-c4d9baac3336	0	16	\N	2021-10-10 00:00:00+05:30	2	\N	\N	917	f	\N	\N	109
40	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 11.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 12.0}	2021-10-11 00:00:00+05:30	2021-10-11 00:00:00+05:30	30	7e001f35-5e00-430b-a58b-d2a301ea2c19	0	16	\N	2021-10-11 00:00:00+05:30	2	\N	\N	918	f	\N	\N	110
41	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 12.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 13.0}	2021-10-12 00:00:00+05:30	2021-10-12 00:00:00+05:30	31	e93bee80-5b2e-4fcf-a957-3f48bf1b3565	0	16	\N	2021-10-12 00:00:00+05:30	2	\N	\N	919	f	\N	\N	111
42	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 13.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 14.0}	2021-10-13 00:00:00+05:30	2021-10-13 00:00:00+05:30	32	775ad090-0f0c-4df3-9380-b0daed544bc2	0	16	\N	2021-10-13 00:00:00+05:30	2	\N	\N	920	f	\N	\N	112
43	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 14.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 15.0}	2021-10-14 00:00:00+05:30	2021-10-14 00:00:00+05:30	33	e5e76e60-5178-4c66-aa1f-03b9e1400c6f	0	16	\N	2021-10-14 00:00:00+05:30	2	\N	\N	921	f	\N	\N	113
44	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 15.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 16.0}	2021-10-15 00:00:00+05:30	2021-10-15 00:00:00+05:30	20	e4b037c6-30bd-4374-b4cc-da9dbb3555da	0	16	\N	2021-10-15 00:00:00+05:30	2	\N	\N	922	f	\N	\N	114
45	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 16.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 17.0}	2021-10-16 00:00:00+05:30	2021-10-16 00:00:00+05:30	21	6893294b-68d2-4bf6-90ae-078b1f7021a0	0	16	\N	2021-10-16 00:00:00+05:30	2	\N	\N	923	f	\N	\N	115
46	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 17.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 18.0}	2021-10-17 00:00:00+05:30	2021-10-17 00:00:00+05:30	22	8c8076c1-e905-4732-83f9-61e62a3cf859	0	16	\N	2021-10-17 00:00:00+05:30	2	\N	\N	924	f	\N	\N	116
47	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 18.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 19.0}	2021-10-18 00:00:00+05:30	2021-10-18 00:00:00+05:30	23	d0e0cf8b-8787-4142-9220-d44302347e77	0	16	\N	2021-10-18 00:00:00+05:30	2	\N	\N	925	f	\N	\N	117
48	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 19.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 20.0}	2021-10-19 00:00:00+05:30	2021-10-19 00:00:00+05:30	24	2dfc1942-5c0d-47d3-aebd-5fa5b9e1fd56	0	16	\N	2021-10-19 00:00:00+05:30	2	\N	\N	926	f	\N	\N	118
49	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 20.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 21.0}	2021-10-20 00:00:00+05:30	2021-10-20 00:00:00+05:30	25	e7dae241-99b8-4a4c-afb2-873ae9e74ee3	0	16	\N	2021-10-20 00:00:00+05:30	2	\N	\N	927	f	\N	\N	119
50	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 21.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 22.0}	2021-10-21 00:00:00+05:30	2021-10-21 00:00:00+05:30	26	a8f4becc-2aa3-4113-a8f0-81bdec872494	0	16	\N	2021-10-21 00:00:00+05:30	2	\N	\N	928	f	\N	\N	120
51	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 22.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 23.0}	2021-10-22 00:00:00+05:30	2021-10-22 00:00:00+05:30	27	df3690db-a49c-42ee-8d32-7158f3103d4d	0	16	\N	2021-10-22 00:00:00+05:30	2	\N	\N	929	f	\N	\N	121
52	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 23.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 24.0}	2021-10-23 00:00:00+05:30	2021-10-23 00:00:00+05:30	28	fe0e6c0d-36bb-40e6-b42a-9637cdbe07ff	0	16	\N	2021-10-23 00:00:00+05:30	2	\N	\N	930	f	\N	\N	122
53	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 24.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 25.0}	2021-10-24 00:00:00+05:30	2021-10-24 00:00:00+05:30	29	a792ef32-b1f7-44de-82f1-b385e821ca94	0	16	\N	2021-10-24 00:00:00+05:30	2	\N	\N	931	f	\N	\N	123
54	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 25.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 26.0}	2021-10-25 00:00:00+05:30	2021-10-25 00:00:00+05:30	30	48e6974b-8453-466b-b907-dbe2f1c96d46	0	16	\N	2021-10-25 00:00:00+05:30	2	\N	\N	932	f	\N	\N	124
55	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 26.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 27.0}	2021-10-26 00:00:00+05:30	2021-10-26 00:00:00+05:30	31	1606026e-dc4d-47fd-87c6-121a17456296	0	16	\N	2021-10-26 00:00:00+05:30	2	\N	\N	933	f	\N	\N	125
56	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 27.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 28.0}	2021-10-27 00:00:00+05:30	2021-10-27 00:00:00+05:30	32	8fc635b1-b148-4015-ba97-07308dbd05e9	0	16	\N	2021-10-27 00:00:00+05:30	2	\N	\N	934	f	\N	\N	126
57	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 28.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 29.0}	2021-10-28 00:00:00+05:30	2021-10-28 00:00:00+05:30	33	537f7084-42e3-4965-b881-b6b80a461efc	0	16	\N	2021-10-28 00:00:00+05:30	2	\N	\N	935	f	\N	\N	127
58	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 29.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 30.0}	2021-10-29 00:00:00+05:30	2021-10-29 00:00:00+05:30	34	43fb286d-a7c5-40b3-a305-fb8e10789cf8	0	16	\N	2021-10-29 00:00:00+05:30	2	\N	\N	936	f	\N	\N	128
59	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 30.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 31.0}	2021-10-30 00:00:00+05:30	2021-10-30 00:00:00+05:30	35	13632bfe-af9e-4648-9231-4953ce4011ae	0	16	\N	2021-10-30 00:00:00+05:30	2	\N	\N	937	f	\N	\N	129
60	{"8afa9fc3-e8b7-446b-a78a-b0226409a552": 31.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 32.0}	2021-10-31 00:00:00+05:30	2021-10-31 00:00:00+05:30	36	34d4f6c7-d9d6-4d3c-9ddb-d2009cfacd7b	0	16	\N	2021-10-31 00:00:00+05:30	2	\N	\N	938	f	\N	\N	130
61	{}	2021-11-01 00:00:00+05:30	\N	37	62379362-79cd-4606-a420-9fbd4d8fd6ed	0	16	\N	2021-11-01 00:00:00+05:30	2	2021-11-14 12:05:01.265411+05:30	{}	939	f	\N	\N	131
\.


--
-- Data for Name: program_enrolment; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.program_enrolment (id, program_id, individual_id, program_outcome_id, observations, program_exit_observations, enrolment_date_time, program_exit_date_time, uuid, version, organisation_id, audit_id, is_voided, enrolment_location, exit_location, legacy_id) FROM stdin;
3	3	82	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 25.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2347.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-03T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-03 00:00:00+05:30	\N	b66c53e8-316a-4acf-8b23-f77029a8de2d	0	2	822	f	\N	\N	3
4	3	83	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 26.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2348.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-04T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-04 00:00:00+05:30	\N	e90555ab-beb2-4251-9cbb-d53c7f4a6eaa	0	2	823	f	\N	\N	4
5	3	84	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 27.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2349.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-05T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-05 00:00:00+05:30	\N	b2f91251-5147-4010-ac03-264435cbc4bd	0	2	824	f	\N	\N	5
6	3	85	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 28.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2350.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-06T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-06 00:00:00+05:30	\N	c220f4a0-7fdc-494f-9c87-09c32a3c3848	0	2	825	f	\N	\N	6
7	3	86	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 29.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2351.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-07T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-07 00:00:00+05:30	\N	96056364-ed15-47e8-9d71-31409e26c6dd	0	2	826	f	\N	\N	7
8	3	87	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 30.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2352.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-08T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-08 00:00:00+05:30	\N	c84b1e48-b953-45ed-879d-3e46871ee6cd	0	2	827	f	\N	\N	8
9	3	88	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 31.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2353.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-09T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-09 00:00:00+05:30	\N	a8c44ef4-2d90-4c4d-9beb-72a6e1d2ff2e	0	2	828	f	\N	\N	9
10	3	89	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 32.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2354.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-10T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-10 00:00:00+05:30	\N	efaedaa4-76fd-4fee-b849-fe5b05663e84	0	2	829	f	\N	\N	10
11	3	90	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 33.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2355.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-11T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-11 00:00:00+05:30	\N	30587410-2095-4e20-9eb1-2a5a55cd9e80	0	2	830	f	\N	\N	11
12	3	91	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 34.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2356.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-12T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-12 00:00:00+05:30	\N	29f8b5bd-98c7-45d9-8ea9-36f6fbd8105e	0	2	831	f	\N	\N	12
13	3	92	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 35.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2357.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-13T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-13 00:00:00+05:30	\N	bf387720-fb95-4537-a473-6b7abdbdee20	0	2	832	f	\N	\N	13
14	3	93	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 36.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2358.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-14T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-14 00:00:00+05:30	\N	cb94c1c8-6752-4aa7-bc33-343b22d35f5d	0	2	833	f	\N	\N	14
15	3	94	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 37.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2359.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-15T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-15 00:00:00+05:30	\N	174ee76e-bad1-4543-8a12-50e89af82dcb	0	2	834	f	\N	\N	15
16	3	95	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 38.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2360.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-16T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-16 00:00:00+05:30	\N	53d75895-0cae-4153-a42b-711bd8ecb7cb	0	2	835	f	\N	\N	16
17	3	96	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 39.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2361.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-17T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-17 00:00:00+05:30	\N	445b46ed-fe5b-4bbe-91e6-dfb044b8bcb4	0	2	836	f	\N	\N	17
18	3	97	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 40.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2362.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-18T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-18 00:00:00+05:30	\N	e28a1687-3f17-41ce-a55a-e9a0d54487b7	0	2	837	f	\N	\N	18
19	3	98	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "53d8be75-29f3-4e96-90ac-0f4afc321fba", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 41.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2363.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-19T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-19 00:00:00+05:30	\N	9251318e-4075-4a33-abc8-25c99030956a	0	2	838	f	\N	\N	19
20	2	99	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 13.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-01 00:00:00+05:30	\N	bd45ce2e-32b0-4b1f-89ea-69d51748d802	0	2	839	f	\N	\N	20
21	2	100	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 14.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-02 00:00:00+05:30	\N	a60f33e9-a33a-417d-8537-ac35cdfa0e82	0	2	840	f	\N	\N	21
22	2	101	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 15.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-03 00:00:00+05:30	\N	ff22d4fd-de99-45dd-8de0-b71a5996eb3d	0	2	841	f	\N	\N	22
23	2	102	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 16.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-04 00:00:00+05:30	\N	44684293-693e-415f-8aed-41f3a4925924	0	2	842	f	\N	\N	23
24	2	103	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 17.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-05 00:00:00+05:30	\N	b8082411-3189-4b63-a0f7-1775904a672f	0	2	843	f	\N	\N	24
25	2	104	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 18.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-06 00:00:00+05:30	\N	9658bf1b-f062-4301-a811-c0d1e855d2e4	0	2	844	f	\N	\N	25
26	2	105	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 19.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-07 00:00:00+05:30	\N	f42656ff-3994-4996-9693-eff7e146ea50	0	2	845	f	\N	\N	26
27	2	106	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 20.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-08 00:00:00+05:30	\N	8281ac2c-31b1-4a78-8441-3ca28da7eee8	0	2	846	f	\N	\N	27
28	2	107	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 21.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-09 00:00:00+05:30	\N	14a4a0ec-125f-4607-831d-4fa369942b82	0	2	847	f	\N	\N	28
29	2	108	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 22.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-10 00:00:00+05:30	\N	b32f0196-777e-4694-96e4-eb460f0e089e	0	2	848	f	\N	\N	29
30	2	109	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 23.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-11 00:00:00+05:30	\N	e845c0b4-11da-469c-ad2f-485cea4d0df2	0	2	849	f	\N	\N	30
31	2	110	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 24.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-12 00:00:00+05:30	\N	0bce7644-3cdf-49b0-af35-13a2a8e2f589	0	2	850	f	\N	\N	31
32	2	111	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 25.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-13 00:00:00+05:30	\N	df6d6a38-2af5-485d-8aa1-cf7a5f3419ed	0	2	851	f	\N	\N	32
33	2	112	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 26.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-14 00:00:00+05:30	\N	11f6061e-fe5d-448e-8085-95a9b0115291	0	2	852	f	\N	\N	33
34	2	113	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 27.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-15 00:00:00+05:30	\N	5017e0b0-2011-4f9e-8412-f317db40dcef	0	2	853	f	\N	\N	34
35	2	114	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 28.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-16 00:00:00+05:30	\N	f000b086-117e-4177-8fa6-71f1f027683f	0	2	854	f	\N	\N	35
36	2	115	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 29.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-17 00:00:00+05:30	\N	6e8031c8-0e1d-43da-bd86-d21b2e7f64ce	0	2	855	f	\N	\N	36
37	2	116	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 30.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-18 00:00:00+05:30	2021-11-14 11:59:02.230679+05:30	0e3c2efa-cc31-4309-94d4-55039b040178	0	2	856	f	\N	\N	37
38	2	117	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 31.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-19 00:00:00+05:30	2021-11-14 11:59:02.230679+05:30	dd825832-8c27-4b50-adbc-a4320b3fb6f8	0	2	857	f	\N	\N	38
39	2	118	\N	{"011bbae2-e642-40d9-a36c-59dca6be28a8": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8afa9fc3-e8b7-446b-a78a-b0226409a552": 32.0, "e71446ac-607b-4733-83a2-4dafb37232a4": 1.0}	\N	2021-09-20 00:00:00+05:30	2021-11-14 11:59:02.230679+05:30	03cbb505-4c6b-4664-89f8-5fcc60fcd474	0	2	858	f	\N	\N	39
1	3	80	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 23.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2345.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-01T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-01 00:00:00+05:30	2021-11-14 11:59:21.266654+05:30	d34ded32-6d45-42a5-a3ab-6dd327b30d44	0	2	820	f	\N	\N	1
2	3	81	\N	{"78169e26-bf95-44e1-bb4f-91092fd8cc21": "399e1a98-9361-4a1d-a1ff-eb810a92354e", "8f3a1e0a-6f50-4240-bf6f-82b3746bc2d8": 24.0, "a425964c-e70b-4f6d-9909-c78c371d0bf8": 2346.0, "cffd9194-4e19-4b9c-9bb5-27e7ca448c23": "2021-09-02T00:00:00.000+05:30", "e1f0db24-dfbd-4c5d-ae3b-66de005e72aa": 2.0}	\N	2021-10-02 00:00:00+05:30	2021-11-14 11:59:21.266654+05:30	755f5c72-b009-41a0-9399-a48f17d14356	0	2	821	f	\N	\N	2
\.


--
-- Data for Name: program_organisation_config; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.program_organisation_config (id, uuid, program_id, organisation_id, visit_schedule, version, audit_id, is_voided) FROM stdin;
\.


--
-- Data for Name: program_organisation_config_at_risk_concept; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.program_organisation_config_at_risk_concept (id, program_organisation_config_id, concept_id) FROM stdin;
\.


--
-- Data for Name: program_outcome; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.program_outcome (id, uuid, name, version, organisation_id, audit_id, is_voided) FROM stdin;
\.


--
-- Data for Name: report_card; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.report_card (id, uuid, name, query, description, colour, is_voided, version, organisation_id, audit_id, standard_report_card_type_id, icon_file_s3_key) FROM stdin;
\.


--
-- Data for Name: rule; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.rule (id, uuid, version, audit_id, type, rule_dependency_id, name, fn_name, data, organisation_id, execution_order, is_voided, entity) FROM stdin;
\.


--
-- Data for Name: rule_dependency; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.rule_dependency (id, uuid, version, audit_id, checksum, code, organisation_id, is_voided) FROM stdin;
\.


--
-- Data for Name: rule_failure_log; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.rule_failure_log (id, uuid, form_id, rule_type, entity_type, entity_id, error_message, stacktrace, source, audit_id, is_voided, version, organisation_id) FROM stdin;
\.


--
-- Data for Name: rule_failure_telemetry; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.rule_failure_telemetry (id, uuid, user_id, organisation_id, version, rule_uuid, individual_uuid, error_message, stacktrace, error_date_time, close_date_time, is_closed, audit_id) FROM stdin;
\.


--
-- Data for Name: schema_version; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.schema_version (installed_rank, version, description, type, script, checksum, installed_by, installed_on, execution_time, success) FROM stdin;
1	0.1	CreateTables	SQL	V0_1__CreateTables.sql	-1010778448	openchs	2021-11-14 10:53:06.454931	73	t
2	0.2	AdditionalUserColumns	SQL	V0_2__AdditionalUserColumns.sql	598335116	openchs	2021-11-14 10:53:06.564404	5	t
3	0.3	CreateOpenCHSUser	SQL	V0_3__CreateOpenCHSUser.sql	-1384118001	openchs	2021-11-14 10:53:06.580191	4	t
4	0.4	SetupGender	SQL	V0_4__SetupGender.sql	-1684826540	openchs	2021-11-14 10:53:06.593138	3	t
5	0.5	CreateProgramEncounterTables	SQL	V0_5__CreateProgramEncounterTables.sql	2126472639	openchs	2021-11-14 10:53:06.606401	22	t
6	0.6	ObservationsWithoutPrograms	SQL	V0_6__ObservationsWithoutPrograms.sql	554876676	openchs	2021-11-14 10:53:06.638783	21	t
7	0.7	FormTables	SQL	V0_7__FormTables.sql	-1468350519	openchs	2021-11-14 10:53:06.67108	30	t
8	0.8	RenameDateOfBirthEstimatedToVerified	SQL	V0_8__RenameDateOfBirthEstimatedToVerified.sql	1314036102	openchs	2021-11-14 10:53:06.711007	2	t
9	0.9	RenameColumnUsedInSummary	SQL	V0_9__RenameColumnUsedInSummary.sql	-423140476	openchs	2021-11-14 10:53:06.724011	2	t
10	0.10	CreateConceptAnswerTable	SQL	V0_10__CreateConceptAnswerTable.sql	-1142215842	openchs	2021-11-14 10:53:06.737393	8	t
11	0.11	DropColumnProfileFromIndividual	SQL	V0_11__DropColumnProfileFromIndividual.sql	1301592739	openchs	2021-11-14 10:53:06.75632	2	t
12	0.12	AddDisplayOrderToFormElementGroup	SQL	V0_12__AddDisplayOrderToFormElementGroup.sql	-1730594591	openchs	2021-11-14 10:53:06.767834	11	t
13	0.13	CreateTableForFormAssociation	SQL	V0_13__CreateTableForFormAssociation.sql	650093988	openchs	2021-11-14 10:53:06.788767	10	t
14	0.14	UniqueConstraints	SQL	V0_14__UniqueConstraints.sql	466108484	openchs	2021-11-14 10:53:06.808101	32	t
15	0.15	ChangeDataTypeOfRelatedEntity	SQL	V0_15__ChangeDataTypeOfRelatedEntity.sql	2099177607	openchs	2021-11-14 10:53:06.849714	2	t
16	0.16	ChangeSortOrderDataTypeAndAddUniqueConstraint	SQL	V0_16__ChangeSortOrderDataTypeAndAddUniqueConstraint.sql	1421640915	openchs	2021-11-14 10:53:06.861543	2	t
17	0.17	UniqueConstraintOnConceptName	SQL	V0_17__UniqueConstraintOnConceptName.sql	2068071747	openchs	2021-11-14 10:53:06.874971	4	t
18	0.18	CreateGenderConcepts	SQL	V0_18__CreateGenderConcepts.sql	624445853	openchs	2021-11-14 10:53:06.889068	3	t
19	0.19	CreateGenderConceptWithAnswers	SQL	V0_19__CreateGenderConceptWithAnswers.sql	-1501805504	openchs	2021-11-14 10:53:06.901087	4	t
20	0.20	UniqueConstraintOnGender	SQL	V0_20__UniqueConstraintOnGender.sql	-1214262700	openchs	2021-11-14 10:53:06.914614	4	t
21	0.21	RemoveFollowupTypeAndUseEncounterType	SQL	V0_21__RemoveFollowupTypeAndUseEncounterType.sql	-436069503	openchs	2021-11-14 10:53:06.93008	12	t
22	0.22	AddObservationsTypeEntityId	SQL	V0_22__AddObservationsTypeEntityId.sql	-1927448004	openchs	2021-11-14 10:53:06.953091	2	t
23	0.23	RenameProgramEncounterDateTime	SQL	V0_23__RenameProgramEncounterDateTime.sql	-2121432657	openchs	2021-11-14 10:53:06.965628	2	t
24	0.24	AddRegistrationDateToIndividual	SQL	V0_24__AddRegistrationDateToIndividual.sql	1230410355	openchs	2021-11-14 10:53:06.977818	8	t
25	0.25	AddNameToProgramEncounter	SQL	V0_25__AddNameToProgramEncounter.sql	418869244	openchs	2021-11-14 10:53:06.996877	2	t
26	0.26	AddMaxDateForProgramEncounter	SQL	V0_26__AddMaxDateForProgramEncounter.sql	-1453668778	openchs	2021-11-14 10:53:07.008418	1	t
27	0.27	HealthMetaDataVersion	SQL	V0_27__HealthMetaDataVersion.sql	-1199562630	openchs	2021-11-14 10:53:07.019372	7	t
28	0.28	RenameSpellingMistakeInTableName	SQL	V0_28__RenameSpellingMistakeInTableName.sql	-520504467	openchs	2021-11-14 10:53:07.036562	2	t
29	0.29	CreateChecklistTables	SQL	V0_29__CreateChecklistTables.sql	1735055931	openchs	2021-11-14 10:53:07.047895	26	t
30	0.30	MakingUniqueConstraintsDeferred	SQL	V0_30__MakingUniqueConstraintsDeferred.sql	1842893321	openchs	2021-11-14 10:53:07.08355	11	t
31	0.31	CreateBaseDate	SQL	V0_31__CreateBaseDate.sql	1101091756	openchs	2021-11-14 10:53:07.102793	1	t
32	0.32	RenameObservationColumns	SQL	V0_32__RenameObservationColumns.sql	1180023750	openchs	2021-11-14 10:53:07.112735	1	t
33	0.33	AddUnitToConcept	SQL	V0_33__AddUnitToConcept.sql	176295804	openchs	2021-11-14 10:53:07.123491	1	t
34	0.34	CreateCatchmentAndMappingTable	SQL	V0_34__CreateCatchmentAndMappingTable.sql	-1566624789	openchs	2021-11-14 10:53:07.134403	16	t
35	0.35	DropCatchmentFromIndividual	SQL	V0_35__DropCatchmentFromIndividual.sql	-903838888	openchs	2021-11-14 10:53:07.158743	1	t
36	0.36	AddColumnDisplayToFormElementGroup	SQL	V0_36__AddColumnDisplayToFormElementGroup.sql	-141629419	openchs	2021-11-14 10:53:07.168343	1	t
37	0.37	AddColumnColourToProgram	SQL	V0_37__AddColumnColourToProgram.sql	1917154220	openchs	2021-11-14 10:53:07.178809	1	t
38	0.38	DropMetaColumnsFromCatchmentAddressMapping	SQL	V0_38__DropMetaColumnsFromCatchmentAddressMapping.sql	1049144005	openchs	2021-11-14 10:53:07.188217	2	t
39	0.39	AddUniqueConstaintWhereItIsMissing	SQL	V0_39__AddUniqueConstaintWhereItIsMissing.sql	1553509046	openchs	2021-11-14 10:53:07.198345	34	t
40	0.40	AddingAddressLevelAttributes	SQL	V0_40__AddingAddressLevelAttributes.sql	-997896356	openchs	2021-11-14 10:53:07.240236	4	t
41	0.41	Organisations	SQL	V0_41__Organisations.sql	-698994054	openchs	2021-11-14 10:53:07.258634	200	t
42	0.42	Multitenancy	SQL	V0_42__Multitenancy.sql	886526685	openchs	2021-11-14 10:53:07.469919	17	t
43	0.43	AddAbnormalToConceptAnswer	SQL	V0_43__AddAbnormalToConceptAnswer.sql	1978512101	openchs	2021-11-14 10:53:07.497995	12	t
44	0.44	ProgramsSpecificToACustomer	SQL	V0_44__ProgramsSpecificToACustomer.sql	-1257243972	openchs	2021-11-14 10:53:07.522612	16	t
45	0.45	AddMultitenancy ProgramsSpecificToACustomer	SQL	V0_45__AddMultitenancy_ProgramsSpecificToACustomer.sql	1688167973	openchs	2021-11-14 10:53:07.549199	3	t
46	0.46	ReplaceNameWithFirstAndLastNames	SQL	V0_46__ReplaceNameWithFirstAndLastNames.sql	2115534139	openchs	2021-11-14 10:53:07.56082	2	t
47	0.47	AddingFormElementType	SQL	V0_47__AddingFormElementType.sql	-1524900904	openchs	2021-11-14 10:53:07.571658	16	t
48	0.48	SplitScheduledDateIntoMinAndMaxDates	SQL	V0_48__SplitScheduledDateIntoMinAndMaxDates.sql	-1370947884	openchs	2021-11-14 10:53:07.59734	2	t
49	0.49	AddValidFormatRegexAndMessageKeyToFormElement	SQL	V0_49__AddValidFormatRegexAndMessageKeyToFormElement.sql	1988385366	openchs	2021-11-14 10:53:07.610367	2	t
50	0.50	AddingTypeToCatchments	SQL	V0_50__AddingTypeToCatchments.sql	-533065888	openchs	2021-11-14 10:53:07.623136	10	t
51	0.51	AddingTypeToAddressLevel	SQL	V0_51__AddingTypeToAddressLevel.sql	-1147025983	openchs	2021-11-14 10:53:07.643176	2	t
52	0.52	AddressLevelOnIndividualIsMandatory	SQL	V0_52__AddressLevelOnIndividualIsMandatory.sql	1531868730	openchs	2021-11-14 10:53:07.655606	1	t
53	0.53	AddUniqueConstraintToOrganisation	SQL	V0_53__AddUniqueConstraintToOrganisation.sql	-40365443	openchs	2021-11-14 10:53:07.667067	10	t
54	0.54	AddCancelToProgramEncounter	SQL	V0_54__AddCancelToProgramEncounter.sql	-441902374	openchs	2021-11-14 10:53:07.68788	2	t
55	1.01	AddVoidingToConcepts	SQL	V1_01__AddVoidingToConcepts.sql	250061624	openchs	2021-11-14 10:53:07.701059	24	t
56	1.02	AddVoidedToEncounters	SQL	V1_02__AddVoidedToEncounters.sql	-60830572	openchs	2021-11-14 10:53:07.736525	16	t
57	1.03	AddGinIndexForObservations	SQL	V1_03__AddGinIndexForObservations.sql	-861966596	openchs	2021-11-14 10:53:07.762942	3	t
58	1.04	AddVoidedToIndividual	SQL	V1_04__AddVoidedToIndividual.sql	-403634913	openchs	2021-11-14 10:53:07.77486	11	t
59	1.04.5	AddHierarchyToOrganisations	SQL	V1_04.5__AddHierarchyToOrganisations.sql	2036376580	openchs	2021-11-14 10:53:07.794444	3	t
60	1.04.6	RevisitPoliciesForMultitenancy	SQL	V1_04.6__RevisitPoliciesForMultitenancy.sql	258035259	openchs	2021-11-14 10:53:07.806067	31	t
61	1.05	DisplayOrderToFloat	SQL	V1_05__DisplayOrderToFloat.sql	-1836162603	openchs	2021-11-14 10:53:07.847265	27	t
62	1.06	DropIsUsedInSummaryColumnInFormElement	SQL	V1_06__DropIsUsedInSummaryColumnInFormElement.sql	-7965232	openchs	2021-11-14 10:53:07.88286	2	t
63	1.07	DropIsGeneratedColumnInFormElement	SQL	V1_07__DropIsGeneratedColumnInFormElement.sql	1878290041	openchs	2021-11-14 10:53:07.892618	2	t
64	1.08	NonApplicableOrganisationEntityMapping	SQL	V1_08__NonApplicableOrganisationEntityMapping.sql	93775699	openchs	2021-11-14 10:53:07.902718	7	t
65	1.09	MigrateConceptDataType	SQL	V1_09__MigrateConceptDataType.sql	663754657	openchs	2021-11-14 10:53:07.918835	2	t
66	1.10	AddPolicyToNonApplicableFormElementTable	SQL	V1_10__AddPolicyToNonApplicableFormElementTable.sql	1160209650	openchs	2021-11-14 10:53:07.929666	3	t
67	1.11	RevisitPoliciesForMultitenancy	SQL	V1_11__RevisitPoliciesForMultitenancy.sql	2018671290	openchs	2021-11-14 10:53:07.940687	3	t
68	1.12	ProgramOrganisationConfigTable	SQL	V1_12__ProgramOrganisationConfigTable.sql	-1677454136	openchs	2021-11-14 10:53:07.951363	26	t
69	1.13	AddSoloFieldToConceptAnswer	SQL	V1_13__AddSoloFieldToConceptAnswer.sql	1784600157	openchs	2021-11-14 10:53:07.989254	34	t
70	1.14	DisableChildrenFromUpdatingParent	SQL	V1_14__DisableChildrenFromUpdatingParent.sql	37126482	openchs	2021-11-14 10:53:08.065869	36	t
71	1.15	ActualSqlForV1 14	SQL	V1_15__ActualSqlForV1_14.sql	-1197563688	openchs	2021-11-14 10:53:08.119166	17	t
72	1.16	DeletingOrgIDFromCatchmentAddressMapping	SQL	V1_16__DeletingOrgIDFromCatchmentAddressMapping.sql	-562767235	openchs	2021-11-14 10:53:08.143898	10	t
73	1.17	MoveAuditToNewTable	SQL	V1_17__MoveAuditToNewTable.sql	201601109	openchs	2021-11-14 10:53:08.164654	45	t
74	1.18	DisableRowLevelSecurityForCatchmentAddressMapping	SQL	V1_18__DisableRowLevelSecurityForCatchmentAddressMapping.sql	-209752374	openchs	2021-11-14 10:53:08.217845	1	t
75	1.19	RemoveStrictPolicieForFormElement	SQL	V1_19__RemoveStrictPolicieForFormElement.sql	962987074	openchs	2021-11-14 10:53:08.225786	2	t
76	1.20	AddVoidedToFormElementAndFormElementGroup	SQL	V1_20__AddVoidedToFormElementAndFormElementGroup.sql	717328699	openchs	2021-11-14 10:53:08.234437	32	t
77	1.21	RemoveConceptIdFromProgram	SQL	V1_21__RemoveConceptIdFromProgram.sql	-1967176069	openchs	2021-11-14 10:53:08.276627	4	t
78	1.22	AddForeignKeyConstraintsToAuditedTables	SQL	V1_22__AddForeignKeyConstraintsToAuditedTables.sql	-741297534	openchs	2021-11-14 10:53:08.298109	34	t
79	1.23	AddOrganisationIdToFormElementDisplayOrderUniqueConstraint	SQL	V1_23__AddOrganisationIdToFormElementDisplayOrderUniqueConstraint.sql	-1001383089	openchs	2021-11-14 10:53:08.347091	10	t
80	1.24	AddVoidedToEncounterTypesAndFormMapping	SQL	V1_24__AddVoidedToEncounterTypesAndFormMapping.sql	-1070689411	openchs	2021-11-14 10:53:08.365591	17	t
81	1.25	AddRelationAndRelative	SQL	V1_25__AddRelationAndRelative.sql	-2103441582	openchs	2021-11-14 10:53:08.390645	23	t
82	1.26	AddReverseRelation	SQL	V1_26__AddReverseRelation.sql	1892977804	openchs	2021-11-14 10:53:08.424434	37	t
83	1.27	AddRelationshipTables	SQL	V1_27__AddRelationshipTables.sql	2112942025	openchs	2021-11-14 10:53:08.481119	74	t
84	1.28	UpdateLastModifiedDateTimeForNumericConcepts	SQL	V1_28__UpdateLastModifiedDateTimeForNumericConcepts.sql	441081105	openchs	2021-11-14 10:53:08.573218	2	t
85	1.29	RemoveRLSFromUsers	SQL	V1_29__RemoveRLSFromUsers.sql	-1272706063	openchs	2021-11-14 10:53:08.58743	1	t
86	1.30	RevertPolicyRelaxingInFormElement Users Catchment	SQL	V1_30__RevertPolicyRelaxingInFormElement_Users_Catchment.sql	-1905327745	openchs	2021-11-14 10:53:08.598454	3	t
87	1.31	AddRuleRelatedTables	SQL	V1_31__AddRuleRelatedTables.sql	-1112075058	openchs	2021-11-14 10:53:08.609435	30	t
88	1.40	RenamingOpenCHSUserToAdmin	SQL	V1_40__RenamingOpenCHSUserToAdmin.sql	435465816	openchs	2021-11-14 10:53:08.651008	3	t
89	1.41	AddAuditColumnsToUser	SQL	V1_41__AddAuditColumnsToUser.sql	-1540216253	openchs	2021-11-14 10:53:08.676062	59	t
90	1.42	DropColumnVersionFromUsers	SQL	V1_42__DropColumnVersionFromUsers.sql	-1736278593	openchs	2021-11-14 10:53:08.755506	4	t
91	1.43	DropColumnAuditIdFromUsers	SQL	V1_43__DropColumnAuditIdFromUsers.sql	2048999647	openchs	2021-11-14 10:53:08.77786	4	t
92	1.44	AddingOrganisationLevelUniqueConstraintToRuleNames	SQL	V1_44__AddingOrganisationLevelUniqueConstraintToRuleNames.sql	-205710553	openchs	2021-11-14 10:53:08.798639	21	t
93	1.45	DefaultingExecutionOrderToMax	SQL	V1_45__DefaultingExecutionOrderToMax.sql	-1515613199	openchs	2021-11-14 10:53:08.829173	16	t
94	1.46	DroppingNotNullConstraintOnRules	SQL	V1_46__DroppingNotNullConstraintOnRules.sql	-1460305777	openchs	2021-11-14 10:53:08.853207	1	t
95	1.47	AddNameToOperationProgramsAndEncounterTypes	SQL	V1_47__AddNameToOperationProgramsAndEncounterTypes.sql	-1768305558	openchs	2021-11-14 10:53:08.864309	8	t
96	1.48	AddingVoidingCapabilityToRules	SQL	V1_48__AddingVoidingCapabilityToRules.sql	-724654493	openchs	2021-11-14 10:53:08.882242	15	t
97	1.49	AddingVoidingCapabilityToRemainingEntities	SQL	V1_49__AddingVoidingCapabilityToRemainingEntities.sql	-384782867	openchs	2021-11-14 10:53:08.905629	185	t
98	1.50	AddVoidingToProgramEnrolment	SQL	V1_50__AddVoidingToProgramEnrolment.sql	-149556715	openchs	2021-11-14 10:53:09.10228	17	t
99	1.51	AddVoidingToChecklistItem	SQL	V1_51__AddVoidingToChecklistItem.sql	2039923730	openchs	2021-11-14 10:53:09.139971	11	t
100	1.52	AnswerOrderInConceptAnswerIsDouble	SQL	V1_52__AnswerOrderInConceptAnswerIsDouble.sql	1719161713	openchs	2021-11-14 10:53:09.171529	15	t
101	1.53	AddMultiTenancyToRuleTables	SQL	V1_53__AddMultiTenancyToRuleTables.sql	-960742974	openchs	2021-11-14 10:53:09.207231	7	t
102	1.54	EnableRLSOnNewTables	SQL	V1_54__EnableRLSOnNewTables.sql	406108909	openchs	2021-11-14 10:53:09.234547	4	t
103	1.55	ModifyingChecklistItemSchema	SQL	V1_55__ModifyingChecklistItemSchema.sql	-1648484371	openchs	2021-11-14 10:53:09.25977	20	t
104	1.56	ModifyingChecklistItemSchema	SQL	V1_56__ModifyingChecklistItemSchema.sql	-749679445	openchs	2021-11-14 10:53:09.300615	7	t
105	1.57	AddingChecklistReferenceTables	SQL	V1_57__AddingChecklistReferenceTables.sql	-1847469194	openchs	2021-11-14 10:53:09.329722	44	t
106	1.58	AllowVoidingOfNonApplicableFormElements	SQL	V1_58__AllowVoidingOfNonApplicableFormElements.sql	-876113176	openchs	2021-11-14 10:53:09.394606	18	t
107	1.59	AddingMultiTenancyToChecklistTables	SQL	V1_59__AddingMultiTenancyToChecklistTables.sql	-1268487144	openchs	2021-11-14 10:53:09.435881	8	t
108	1.59.1	UpdateConceptUniqueKeyConstraintToIncludeOrg	SQL	V1_59.1__UpdateConceptUniqueKeyConstraintToIncludeOrg.sql	-519108521	openchs	2021-11-14 10:53:09.463662	7	t
109	1.60	CreateLocationToLocationParentMapping	SQL	V1_60__CreateLocationToLocationParentMapping.sql	-1047050298	openchs	2021-11-14 10:53:09.486161	20	t
110	1.61	CreateFacility	SQL	V1_61__CreateFacility.sql	-1898188175	openchs	2021-11-14 10:53:09.521702	15	t
111	1.62	UserFacilityIndividualMapping	SQL	V1_62__UserFacilityIndividualMapping.sql	1057518812	openchs	2021-11-14 10:53:09.555617	15	t
112	1.63	RemoveInvalidFormElementTypes	SQL	V1_63__RemoveInvalidFormElementTypes.sql	-519375708	openchs	2021-11-14 10:53:09.589239	2	t
113	1.64	MigrateLevelToADouble	SQL	V1_64__MigrateLevelToADouble.sql	-354153816	openchs	2021-11-14 10:53:09.600959	12	t
114	1.64.5	CreateNecessaryViewsForAddressLevel	SQL	V1_64.5__CreateNecessaryViewsForAddressLevel.sql	-1284912256	openchs	2021-11-14 10:53:09.626072	16	t
115	1.65	CreateAddressLevelType	SQL	V1_65__CreateAddressLevelType.sql	-773824940	openchs	2021-11-14 10:53:09.6545	4	t
116	1.66	AssociateRLSPoliciesToAddressLevelType	SQL	V1_66__AssociateRLSPoliciesToAddressLevelType.sql	-1935992107	openchs	2021-11-14 10:53:09.669281	5	t
117	1.67	AddUserColumns	SQL	V1_67__AddUserColumns.sql	-1813909293	openchs	2021-11-14 10:53:09.695918	19	t
118	1.68	MakeUserColumnsNotNullable	SQL	V1_68__MakeUserColumnsNotNullable.sql	-829109358	openchs	2021-11-14 10:53:09.736973	4	t
119	1.69	UserFacilityMappingNotNullColumns	SQL	V1_69__UserFacilityMappingNotNullColumns.sql	-686386027	openchs	2021-11-14 10:53:09.761983	3	t
120	1.70	ProgramOrganisationConfigConcept	SQL	V1_70__ProgramOrganisationConfigConcept.sql	1175588546	openchs	2021-11-14 10:53:09.786807	7	t
121	1.71	AddOperatingIndividualScopeToUsers	SQL	V1_71__AddOperatingIndividualScopeToUsers.sql	1278385804	openchs	2021-11-14 10:53:09.810812	2	t
122	1.72	CatchmentIsMandatoryConditionally	SQL	V1_72__CatchmentIsMandatoryConditionally.sql	-866874235	openchs	2021-11-14 10:53:09.821939	3	t
123	1.73	SetAdminUserRoles	SQL	V1_73__SetAdminUserRoles.sql	-2085906778	openchs	2021-11-14 10:53:09.832676	1	t
124	1.73.1	ChangeTypeTimestampToTimestampTZForAuditCreatedDateTimeAndLastModifiedDateTime	SQL	V1_73_1__ChangeTypeTimestampToTimestampTZForAuditCreatedDateTimeAndLastModifiedDateTime.sql	1549749339	openchs	2021-11-14 10:53:09.842582	32	t
125	1.74	AddingChecklistItemInterdependency	SQL	V1_74__AddingChecklistItemInterdependency.sql	867864144	openchs	2021-11-14 10:53:09.883055	3	t
126	1.75	UpdateAuditWhenLastModifiedDateTimeIsInFuture	SQL	V1_75__UpdateAuditWhenLastModifiedDateTimeIsInFuture.sql	-1437880031	openchs	2021-11-14 10:53:09.893518	2	t
127	1.76	CreateProgramRule	SQL	V1_76__CreateProgramRule.sql	-1553662238	openchs	2021-11-14 10:53:09.9038	16	t
128	1.77	CreateVideoTable	SQL	V1_77__CreateVideoTable.sql	667556661	openchs	2021-11-14 10:53:09.931712	21	t
129	1.78	CreateVideoTelemetricTable	SQL	V1_78__CreateVideoTelemetricTable.sql	1433562913	openchs	2021-11-14 10:53:09.974804	12	t
130	1.79	AddUniqueConstraintOn AddressLevel title and level	SQL	V1_79__AddUniqueConstraintOn_AddressLevel_title_and_level.sql	-1646303530	openchs	2021-11-14 10:53:10.005141	4	t
131	1.80	AddScheduleOnExpiryOfDependencyToChecklistItemDetail	SQL	V1_80__AddScheduleOnExpiryOfDependencyToChecklistItemDetail.sql	-2019739920	openchs	2021-11-14 10:53:10.017674	11	t
132	1.81	AddMediaDirectoryToOrganisation	SQL	V1_81__AddMediaDirectoryToOrganisation.sql	-933221874	openchs	2021-11-14 10:53:10.036212	5	t
133	1.82	AddMinDaysFromStartDateToChecklistItemDetail	SQL	V1_82__AddMinDaysFromStartDateToChecklistItemDetail.sql	1110824284	openchs	2021-11-14 10:53:10.049208	2	t
134	1.83	AddRegistrationLocationToIndividual	SQL	V1_83__AddRegistrationLocationToIndividual.sql	-367031038	openchs	2021-11-14 10:53:10.058838	1	t
135	1.84	AddLocationFieldsToProgramEnrolment	SQL	V1_84__AddLocationFieldsToProgramEnrolment.sql	1744711160	openchs	2021-11-14 10:53:10.068513	2	t
136	1.85	AddLocationFieldsToProgramEncounter	SQL	V1_85__AddLocationFieldsToProgramEncounter.sql	998632110	openchs	2021-11-14 10:53:10.078212	1	t
137	1.86	AddLocationFieldsToEncounter	SQL	V1_86__AddLocationFieldsToEncounter.sql	-1413895738	openchs	2021-11-14 10:53:10.087458	1	t
138	1.87	AddSubjectTypes	SQL	V1_87__AddSubjectTypes.sql	-101792742	openchs	2021-11-14 10:53:10.096535	23	t
139	1.88	IndividualToPointToSubjectType	SQL	V1_88__IndividualToPointToSubjectType.sql	-447763604	openchs	2021-11-14 10:53:10.127946	3	t
140	1.89	UpdateUniqueConstraintAs Title Level OrgId On AddressLevel	SQL	V1_89__UpdateUniqueConstraintAs_Title_Level_OrgId_On_AddressLevel.sql	1350705938	openchs	2021-11-14 10:53:10.139845	2	t
141	1.90	EnableRowLevelSecurityOnProgramOrganisationConfig	SQL	V1_90__EnableRowLevelSecurityOnProgramOrganisationConfig.sql	-546268704	openchs	2021-11-14 10:53:10.150769	1	t
142	1.91	CreateUserSettingsTable	SQL	V1_91__CreateUserSettingsTable.sql	-1943088164	openchs	2021-11-14 10:53:10.161012	11	t
143	1.92	AddSettingsColumnToUsersTable	SQL	V1_92__AddSettingsColumnToUsersTable.sql	1899078484	openchs	2021-11-14 10:53:10.181674	2	t
144	1.93	DropUserSettingsTable	SQL	V1_93__DropUserSettingsTable.sql	2042306745	openchs	2021-11-14 10:53:10.193252	4	t
145	1.93.1	AddOrganisationIdToGenderTable	SQL	V1_93_1__AddOrganisationIdToGenderTable.sql	-1818688013	openchs	2021-11-14 10:53:10.207003	12	t
146	1.93.2	EnableRLS OnAllTables	SQL	V1_93_2__EnableRLS_OnAllTables.sql	1051847878	openchs	2021-11-14 10:53:10.228781	11	t
147	1.93.3	Create openchs impl	SQL	V1_93_3__Create_openchs_impl.sql	1822757547	openchs	2021-11-14 10:53:10.249402	1	t
148	1.93.4	SetPolicyForUsersTable	SQL	V1_93_4__SetPolicyForUsersTable.sql	-1248590332	openchs	2021-11-14 10:53:10.260667	4	t
149	1.93.5	AddIndicesToOrganisationId	SQL	V1_93_5__AddIndicesToOrganisationId.sql	-880506410	openchs	2021-11-14 10:53:10.274904	201	t
150	1.94	FunctionToCreateOrgDBUser	SQL	V1_94__FunctionToCreateOrgDBUser.sql	345745916	openchs	2021-11-14 10:53:10.490807	4	t
151	1.95	AddEmailAndPhoneToUser	SQL	V1_95__AddEmailAndPhoneToUser.sql	-1769939210	openchs	2021-11-14 10:53:10.515855	15	t
152	1.96	CreateSyncTelemetryTable	SQL	V1_96__CreateSyncTelemetryTable.sql	-1720066759	openchs	2021-11-14 10:53:10.542808	11	t
153	1.97	AddColumnsToSyncTelemetryTable	SQL	V1_97__AddColumnsToSyncTelemetryTable.sql	-90397670	openchs	2021-11-14 10:53:10.56232	2	t
154	1.98	RenameUsernameAndAddNameInUserTable	SQL	V1_98__RenameUsernameAndAddNameInUserTable.sql	-444810637	openchs	2021-11-14 10:53:10.573123	3	t
155	1.99	CreateIdentifierTables	SQL	V1_99__CreateIdentifierTables.sql	-562392561	openchs	2021-11-14 10:53:10.584537	64	t
156	1.100	AddColumnsToChecklistItemDetail	SQL	V1_100__AddColumnsToChecklistItemDetail.sql	-419766127	openchs	2021-11-14 10:53:10.657681	2	t
157	1.101	EnableRLS OnAddressLevelType	SQL	V1_101__EnableRLS_OnAddressLevelType.sql	-1598449286	openchs	2021-11-14 10:53:10.66794	2	t
158	1.102	AddIndicesToOrganisationId	SQL	V1_102__AddIndicesToOrganisationId.sql	1125452490	openchs	2021-11-14 10:53:10.679225	283	t
159	1.103	AddMissingIndices	SQL	V1_103__AddMissingIndices.sql	1311458220	openchs	2021-11-14 10:53:10.974066	52	t
160	1.104	AddColumnsToIdntifierSourceTable	SQL	V1_104__AddColumnsToIdntifierSourceTable.sql	73487457	openchs	2021-11-14 10:53:11.050152	28	t
161	1.105	DropSchedulingConstraintOnProgramEncounter	SQL	V1_105__DropSchedulingConstraintOnProgramEncounter.sql	739346240	openchs	2021-11-14 10:53:11.10317	5	t
162	1.107	DropAndModifyRLSPolicies	SQL	V1_107__DropAndModifyRLSPolicies.sql	317002761	openchs	2021-11-14 10:53:11.134002	30	t
163	1.108	ConvertTimestampTypeColumnsToTimestampWithTimeZoneType	SQL	V1_108__ConvertTimestampTypeColumnsToTimestampWithTimeZoneType.sql	1080401303	openchs	2021-11-14 10:53:11.186139	199	t
164	1.109	AddProgramSubjectLabelColumnToOperationalProgram	SQL	V1_109__AddProgramSubjectLabelColumnToOperationalProgram.sql	-363354595	openchs	2021-11-14 10:53:11.396697	2	t
165	1.111	AddLevelColumnToAddressLevelType	SQL	V1_111__AddLevelColumnToAddressLevelType.sql	1505441354	openchs	2021-11-14 10:53:11.407654	15	t
166	1.112	AddParentIdColumnToAddressLevelType	SQL	V1_112__AddParentIdColumnToAddressLevelType.sql	-1141440053	openchs	2021-11-14 10:53:11.432024	2	t
167	1.113	AddSubjectTypeToFormMapping	SQL	V1_113__AddSubjectTypeToFormMapping.sql	2123410715	openchs	2021-11-14 10:53:11.442527	4	t
168	1.114	AddParentColumnAndAlterLineageInLocation	SQL	V1_114__AddParentColumnAndAlterLineageInLocation.sql	-1496853378	openchs	2021-11-14 10:53:11.454888	5	t
169	1.115	AddEntityColumnToRuleTable	SQL	V1_115__AddEntityColumnToRuleTable.sql	52218720	openchs	2021-11-14 10:53:11.468405	7	t
170	1.116	AddNameParentUniqueConstraintToLocation	SQL	V1_116__AddNameParentUniqueConstraintToLocation.sql	196811631	openchs	2021-11-14 10:53:11.483704	4	t
171	1.117	AddUsernameSuffixToOrganisationTable	SQL	V1_117__AddUsernameSuffixToOrganisationTable.sql	1063295939	openchs	2021-11-14 10:53:11.496856	1	t
172	1.118	AddUniqueUUIDConstraintToVideo	SQL	V1_118__AddUniqueUUIDConstraintToVideo.sql	-708229522	openchs	2021-11-14 10:53:11.506874	4	t
173	1.119	CreateRuleFailureTelemetryTable	SQL	V1_119__CreateRuleFailureTelemetryTable.sql	-589057985	openchs	2021-11-14 10:53:11.520145	16	t
174	1.120	AddSchedulingRelatedColumnsToEncounterTable	SQL	V1_120__AddSchedulingRelatedColumnsToEncounterTable.sql	-272911783	openchs	2021-11-14 10:53:11.548491	12	t
175	1.121	AddDateTimeColumnToRuleFailureTelemetry	SQL	V1_121__AddDateTimeColumnToRuleFailureTelemetry.sql	88262135	openchs	2021-11-14 10:53:11.585002	38	t
176	1.122	CreateOrganisationConfigTable	SQL	V1_122__CreateOrganisationConfigTable.sql	496491893	openchs	2021-11-14 10:53:11.649433	23	t
177	1.123	AddAuditToOrganisationConfigTable	SQL	V1_123__AddAuditToOrganisationConfigTable.sql	1290806006	openchs	2021-11-14 10:53:11.698291	24	t
178	1.124	CreateTranslationTable	SQL	V1_124__CreateTranslationTable.sql	1130811360	openchs	2021-11-14 10:53:11.74315	20	t
179	1.125	CreatePlatformTranslationTable	SQL	V1_125__CreatePlatformTranslationTable.sql	1957335093	openchs	2021-11-14 10:53:11.791476	21	t
180	1.126	AddLanguageToTranslationTable	SQL	V1_126__AddLanguageToTranslationTable.sql	1279181139	openchs	2021-11-14 10:53:11.832817	2	t
181	1.127	AddLanguageToPlatformTranslationTable	SQL	V1_127__AddLanguageToPlatformTranslationTable.sql	2106552388	openchs	2021-11-14 10:53:11.844424	1	t
182	1.128	AddOrganisationIdToPlatformTranslationTable	SQL	V1_128__AddOrganisationIdToPlatformTranslationTable.sql	-1806730880	openchs	2021-11-14 10:53:11.855775	11	t
183	1.129	RemoveAuditFromPlatformTranslationTable	SQL	V1_129__RemoveAuditFromPlatformTranslationTable.sql	1075501879	openchs	2021-11-14 10:53:11.876664	4	t
184	1.130	CreateTablesForRulesFromUI	SQL	V1_130__CreateTablesForRulesFromUI.sql	-531458997	openchs	2021-11-14 10:53:11.890419	2	t
185	1.131	AddColulmsForRulesFromUI	SQL	V1_131__AddColulmsForRulesFromUI.sql	-1539591806	openchs	2021-11-14 10:53:11.901441	3	t
186	1.132	AddColulmsForRulesFromUI	SQL	V1_132__AddColulmsForRulesFromUI.sql	1816943734	openchs	2021-11-14 10:53:11.914269	2	t
187	1.133	UpdateOpenchsImplUserCreateScript	SQL	V1_133__UpdateOpenchsImplUserCreateScript.sql	1197713233	openchs	2021-11-14 10:53:11.926283	2	t
188	1.134	UpdateUniqueConstraintOnReferenceTables	SQL	V1_134__UpdateUniqueConstraintOnReferenceTables.sql	-1732538485	openchs	2021-11-14 10:53:11.937503	107	t
189	1.135	Openchs impl  userCanCreateRoles	SQL	V1_135__Openchs_impl__userCanCreateRoles.sql	-696814054	openchs	2021-11-14 10:53:12.055805	17	t
190	1.136	addKeyValuesToConcept	SQL	V1_136__addKeyValuesToConcept.sql	-2135200862	openchs	2021-11-14 10:53:12.096685	10	t
191	1.137	UpdateUniqueConstraintOnChecklistItemDetailTable	SQL	V1_137__UpdateUniqueConstraintOnChecklistItemDetailTable.sql	-1986431216	openchs	2021-11-14 10:53:12.126216	7	t
192	1.138	UpdateEncounterNameType	SQL	V1_138__UpdateEncounterNameType.sql	-1474865201	openchs	2021-11-14 10:53:12.144868	19	t
193	1.139	UpdateCreateDbUser	SQL	V1_139__UpdateCreateDbUser.sql	2072624922	openchs	2021-11-14 10:53:12.176695	4	t
194	1.140	DropChecklistRuleColumnFromProgramAddToForm	SQL	V1_140__DropChecklistRuleColumnFromProgramAddToForm.sql	2081702934	openchs	2021-11-14 10:53:12.192866	2	t
195	1.141	CreateWorkupdationRuleColumnInOrgConfig	SQL	V1_141__CreateWorkupdationRuleColumnInOrgConfig.sql	1076139085	openchs	2021-11-14 10:53:12.207121	15	t
196	1.142.1	CreateEntitiesForOrganisationGroup	SQL	V1_142.1__CreateEntitiesForOrganisationGroup.sql	1474847627	openchs	2021-11-14 10:53:12.235513	116	t
197	1.142.2	CreateNewRLSForAccount	SQL	V1_142.2__CreateNewRLSForAccount.sql	270333458	openchs	2021-11-14 10:53:12.382443	46	t
198	1.143	DropOrganisationNotNullConstraintFromUser	SQL	V1_143__DropOrganisationNotNullConstraintFromUser.sql	-1495802286	openchs	2021-11-14 10:53:12.44667	3	t
199	1.144	ChangeUserTableRLS	SQL	V1_144__ChangeUserTableRLS.sql	-235571865	openchs	2021-11-14 10:53:12.461697	49	t
200	1.145	UpdateDbUserFunction	SQL	V1_145__UpdateDbUserFunction.sql	-1806357283	openchs	2021-11-14 10:53:12.534605	2	t
201	1.146	DropFormIdNotNullConstraint	SQL	V1_146__DropFormIdNotNullConstraint.sql	833681352	openchs	2021-11-14 10:53:12.547413	2	t
202	1.147	CreateRolesAndPrivilegeTables	SQL	V1_147__CreateRolesAndPrivilegeTables.sql	1775959127	openchs	2021-11-14 10:53:12.557815	82	t
203	1.148	CreateSubjectGroupsRelatedTables	SQL	V1_148__CreateSubjectGroupsRelatedTables.sql	61224039	openchs	2021-11-14 10:53:12.648885	65	t
204	1.149	AddColumnIsHouseholdInSubjectType	SQL	V1_149__AddColumnIsHouseholdInSubjectType.sql	-48028424	openchs	2021-11-14 10:53:12.728278	22	t
205	1.150	DropFormNameNotNullConstraint	SQL	V1_150__DropFormNameNotNullConstraint.sql	1296356908	openchs	2021-11-14 10:53:12.777658	2	t
206	1.151	AddLegacyId	SQL	V1_151__AddLegacyId.sql	111842711	openchs	2021-11-14 10:53:12.801332	6	t
207	1.152	AddLegacyIdToProgramEnrolment	SQL	V1_152__AddLegacyIdToProgramEnrolment.sql	-2019471133	openchs	2021-11-14 10:53:12.82008	6	t
208	1.153	AddLegacyIdToEncounterTables	SQL	V1_153__AddLegacyIdToEncounterTables.sql	-1224193127	openchs	2021-11-14 10:53:12.835711	10	t
209	1.154	UpdateRolesAndPrivilegeTables	SQL	V1_154__UpdateRolesAndPrivilegeTables.sql	-1302719325	openchs	2021-11-14 10:53:12.859949	14	t
210	1.155	AddRuleColumnToFormElementGroup	SQL	V1_155__AddRuleColumnToFormElementGroup.sql	-2051288522	openchs	2021-11-14 10:53:12.906338	2	t
211	1.156	RuleFailureLogTable	SQL	V1_156__RuleFailureLogTable.sql	-748011860	openchs	2021-11-14 10:53:12.925572	13	t
212	1.157	AddActiveFlag	SQL	V1_157__AddActiveFlag.sql	-14920397	openchs	2021-11-14 10:53:12.952762	54	t
213	1.158	DropLevelColumnFromAddressLevel	SQL	V1_158__DropLevelColumnFromAddressLevel.sql	619023453	openchs	2021-11-14 10:53:13.017736	2	t
214	1.159	CreateIndexesOnForeignKeys	SQL	V1_159__CreateIndexesOnForeignKeys.sql	727175537	openchs	2021-11-14 10:53:13.028525	202	t
215	1.160	AddTypeToSubjectType	SQL	V1_160__AddTypeToSubjectType.sql	599065489	openchs	2021-11-14 10:53:13.246795	11	t
216	1.161	AlterIndividualRelationshipIdType	SQL	V1_161__AlterIndividualRelationshipIdType.sql	-1801330727	openchs	2021-11-14 10:53:13.282005	32	t
217	1.162	AddAuditToPlatformTranslations	SQL	V1_162__AddAuditToPlatformTranslations.sql	-1331722438	openchs	2021-11-14 10:53:13.332793	12	t
218	1.163	CreateSubjectSummaryRuleColumnInSubjectType	SQL	V1_163__CreateSubjectSummaryRuleColumnInSubjectType.sql	-745693715	openchs	2021-11-14 10:53:13.368431	16	t
219	1.164	RemoveRegisterSubjectPrivilegeWhereUserSettingIsHiderRegister	SQL	V1_164__RemoveRegisterSubjectPrivilegeWhereUserSettingIsHiderRegister.sql	-1065793363	openchs	2021-11-14 10:53:13.408388	6	t
220	1.165	CreateDashboardCardTables	SQL	V1_165__CreateDashboardCardTables.sql	-362652407	openchs	2021-11-14 10:53:13.438014	70	t
221	1.166	RenameCardToReportCard	SQL	V1_166__RenameCardToReportCard.sql	113683853	openchs	2021-11-14 10:53:13.529946	2	t
222	1.167	AddDeviceInfoColumnToSyncTelemetry	SQL	V1_167__AddDeviceInfoColumnToSyncTelemetry.sql	-983826135	openchs	2021-11-14 10:53:13.545021	2	t
223	1.168	CreateMsg91ConfigTable	SQL	V1_168__CreateMsg91ConfigTable.sql	-956879297	openchs	2021-11-14 10:53:13.557618	10	t
224	1.169	AddSchemaNameToOrganisation	SQL	V1_169__AddSchemaNameToOrganisation.sql	-1187694363	openchs	2021-11-14 10:53:13.579183	18	t
225	1.170	AddTablesForApprovalWorkflow	SQL	V1_170__AddTablesForApprovalWorkflow.sql	235607798	openchs	2021-11-14 10:53:13.624734	82	t
226	1.171	DecisionConcept	SQL	V1_171__DecisionConcept.sql	2109312080	openchs	2021-11-14 10:53:13.73198	7	t
227	1.172	AddIconColumnToReportCardTable	SQL	V1_172__AddIconColumnToReportCardTable.sql	-2100936328	openchs	2021-11-14 10:53:13.750582	2	t
228	1.173	AddStatusDateTimeColumnToEntityApprovalStatus	SQL	V1_173__AddStatusDateTimeColumnToEntityApprovalStatus.sql	-1622809580	openchs	2021-11-14 10:53:13.763198	2	t
229	1.173.1	AddDashboardSection	SQL	V1_173_1__AddDashboardSection.sql	-1895021098	openchs	2021-11-14 10:53:13.776347	27	t
230	1.174	AddMoreStandardReportCardTypes	SQL	V1_174__AddMoreStandardReportCardTypes.sql	232772714	openchs	2021-11-14 10:53:13.814405	2	t
231	1.175	VoidRejectPrivileges	SQL	V1_175__VoidRejectPrivileges.sql	-278880277	openchs	2021-11-14 10:53:13.826983	1	t
232	1.176	CreateNewsTables	SQL	V1_176__CreateNewsTables.sql	1810702970	openchs	2021-11-14 10:53:13.83867	14	t
233	1.177	AddGPSCordinatesAndLocationPropertiesToAddressLevel	SQL	V1_177__AddGPSCordinatesAndLocationPropertiesToAddressLevel.sql	-1524232625	openchs	2021-11-14 10:53:13.863221	2	t
234	1.178	CreateCommentTable	SQL	V1_178__CreateCommentTable.sql	1400423952	openchs	2021-11-14 10:53:13.875621	15	t
235	1.179	AllowRegistrationWithoutLocation	SQL	V1_179__AllowRegistrationWithoutLocation.sql	-2112911679	openchs	2021-11-14 10:53:13.901403	13	t
236	1.180	AddUniqueNameColumnToSubjectType	SQL	V1_180__AddUniqueNameColumnToSubjectType.sql	-987668377	openchs	2021-11-14 10:53:13.925925	12	t
237	1.181	AddNameRegExColumnsToSubjectType	SQL	V1_181__AddNameRegExColumnsToSubjectType.sql	-2144001562	openchs	2021-11-14 10:53:13.948884	2	t
238	1.182	AddCommentStandardReportCardType	SQL	V1_182__AddCommentStandardReportCardType.sql	-204897504	openchs	2021-11-14 10:53:13.962046	1	t
239	1.183	CreateCommentThreadTable	SQL	V1_183__CreateCommentThreadTable.sql	718987178	openchs	2021-11-14 10:53:13.974751	14	t
240	1.184	AddEnableApprovalToFormMapping	SQL	V1_184__AddEnableApprovalToFormMapping.sql	-1385491952	openchs	2021-11-14 10:53:13.998092	16	t
241	1.185	ReplaceRLSForOrganisationConfig	SQL	V1_185__ReplaceRLSForOrganisationConfig.sql	1872179045	openchs	2021-11-14 10:53:14.022437	2	t
242	1.186	RemovePrintSettingsFromOrgConfig	SQL	V1_186__RemovePrintSettingsFromOrgConfig.sql	-1219546178	openchs	2021-11-14 10:53:14.033053	1	t
243	1.187	ReplaceRLSForGroupDashboard	SQL	V1_187__ReplaceRLSForGroupDashboard.sql	1029226065	openchs	2021-11-14 10:53:14.042385	2	t
244	1.188	AddIconColumnToSubjectType	SQL	V1_188__AddIconColumnToSubjectType.sql	205896299	openchs	2021-11-14 10:53:14.052607	1	t
245	1.189	AddSyncSourceToSyncTelemetry	SQL	V1_189__AddSyncSourceToSyncTelemetry.sql	-392587034	openchs	2021-11-14 10:53:14.062682	1	t
246	1.190	AddUniqueConstraintForUuidAndOrganisationid	SQL	V1_190__AddUniqueConstraintForUuidAndOrganisationid.sql	1343776163	openchs	2021-11-14 10:53:14.07235	4	t
247	1.191	UpdateLastModifiedMillisecondToThreeDigits	SQL	V1_191__UpdateLastModifiedMillisecondToThreeDigits.sql	1162135556	openchs	2021-11-14 10:53:14.084904	2	t
248	1.192	CreateSubjectMigrationTable	SQL	V1_192__CreateSubjectMigrationTable.sql	2017976330	openchs	2021-11-14 10:53:14.095285	12	t
249	1.193	Make LastUpdatedDateTimeTo3DigitPrecision	SQL	V1_193__Make_LastUpdatedDateTimeTo3DigitPrecision.sql	-189480069	openchs	2021-11-14 10:53:14.11907	86	t
250	\N	Functions	SQL	R__Functions.sql	-781785283	openchs	2021-11-14 10:53:14.23398	23	t
251	\N	UtilityViews	SQL	R__UtilityViews.sql	-968204608	openchs	2021-11-14 10:53:14.278397	43	t
252	\N	Views	SQL	R__Views.sql	1065277786	openchs	2021-11-14 10:53:14.344236	29	t
\.


--
-- Data for Name: standard_report_card_type; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.standard_report_card_type (id, uuid, name, description, is_voided, created_date_time, last_modified_date_time) FROM stdin;
1	7726476c-fb91-4c28-8afc-9782714c1d8c	Pending approval	Pending approval	f	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.092+05:30
2	84d6c349-9fbb-41d3-85fe-1d34521a0d45	Approved	Approved	f	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.093+05:30
3	9e584c8d-b31d-4e5a-9161-baf4f369d02d	Rejected	Rejected	f	2021-11-14 10:53:13.646894+05:30	2021-11-14 10:53:14.094+05:30
4	27020b32-c21b-43a4-81bd-7b88ad3a6ef0	Scheduled visits	Scheduled visits	f	2021-11-14 10:53:13.822255+05:30	2021-11-14 10:53:14.095+05:30
5	9f88bee5-2ab9-4ac4-ae19-d07e9715bdb5	Overdue visits	Overdue visits	f	2021-11-14 10:53:13.822255+05:30	2021-11-14 10:53:14.096+05:30
6	88a7514c-48c0-4d5d-a421-d074e43bb36c	Last 24 hours registrations	Last 24 hours registrations	f	2021-11-14 10:53:13.822255+05:30	2021-11-14 10:53:14.097+05:30
7	a5efc04c-317a-4823-a203-e62603454a65	Last 24 hours enrolments	Last 24 hours enrolments	f	2021-11-14 10:53:13.822255+05:30	2021-11-14 10:53:14.098+05:30
8	77b5b3fa-de35-4f24-996b-2842492ea6e0	Last 24 hours visits	Last 24 hours visits	f	2021-11-14 10:53:13.822255+05:30	2021-11-14 10:53:14.099+05:30
9	1fbcadf3-bf1a-439e-9e13-24adddfbf6c0	Total	Total	f	2021-11-14 10:53:13.822255+05:30	2021-11-14 10:53:14.1+05:30
10	a65c064b-db32-408b-aceb-d15acfebca1e	Comments	Comments	f	2021-11-14 10:53:13.970432+05:30	2021-11-14 10:53:14.101+05:30
\.


--
-- Data for Name: subject_migration; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.subject_migration (id, uuid, individual_id, old_address_level_id, new_address_level_id, organisation_id, audit_id, is_voided, version) FROM stdin;
\.


--
-- Data for Name: subject_type; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.subject_type (id, uuid, name, organisation_id, is_voided, audit_id, version, is_group, is_household, active, type, subject_summary_rule, allow_empty_location, unique_name, valid_first_name_regex, valid_first_name_description_key, valid_last_name_regex, valid_last_name_description_key, icon_file_s3_key) FROM stdin;
1	9f2af1f9-e150-4f8e-aad3-40bb7eb05aa3	Individual	1	f	82	1	f	f	t	\N	\N	f	f	\N	\N	\N	\N	\N
2	9b73aed9-7067-45dd-b003-4655b0f15a0a	Person	2	f	94	0	f	f	t	Person		f	f	\N	\N	\N	\N	\N
3	691ef492-586d-4ed2-a33f-d650de16f005	Household	2	f	98	0	t	t	t	Household		f	f	\N	\N	\N	\N	\N
7	1b1d7dde-e8c7-4dd1-9b84-bd23d96851da	ASHA Area Inputs	2	f	107	0	f	f	t	Individual	\N	f	f	\N	\N	\N	\N	\N
\.


--
-- Data for Name: sync_telemetry; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.sync_telemetry (id, uuid, user_id, organisation_id, version, sync_status, sync_start_time, sync_end_time, entity_status, device_name, android_version, app_version, device_info, sync_source) FROM stdin;
\.


--
-- Data for Name: translation; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.translation (id, uuid, organisation_id, audit_id, version, translation_json, is_voided, language) FROM stdin;
\.


--
-- Data for Name: user_facility_mapping; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.user_facility_mapping (id, version, audit_id, uuid, is_voided, organisation_id, facility_id, user_id) FROM stdin;
\.


--
-- Data for Name: user_group; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.user_group (id, uuid, user_id, group_id, is_voided, version, organisation_id, audit_id) FROM stdin;
1	4fe6c26d-43f0-4f1e-9159-71781fc1becc	1	1	f	0	1	84
2	c07e0bab-2ebf-45f4-af9b-2e30eba40927	2	2	f	0	2	93
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.users (id, uuid, username, organisation_id, created_by_id, last_modified_by_id, created_date_time, last_modified_date_time, is_voided, catchment_id, is_org_admin, operating_individual_scope, settings, email, phone_number, disabled_in_cognito, name) FROM stdin;
1	5fed2907-df3a-4867-aef5-c87f4c78a31a	admin	1	1	1	2021-11-14 16:23:08.691945+05:30	2021-11-14 16:23:08.692+05:30	f	\N	f	None	\N	\N	\N	f	\N
2	2eac4b85-2e33-4482-a48b-7629f15a4ab3	user@test	2	2	2	2021-11-14 10:59:13.849+05:30	2021-11-14 10:59:13.849+05:30	f	1	t	ByCatchment	\N	test@avni.com	+919897656234	f	Test user
\.


--
-- Data for Name: video; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.video (id, version, audit_id, uuid, organisation_id, title, file_path, description, duration, is_voided) FROM stdin;
\.


--
-- Data for Name: video_telemetric; Type: TABLE DATA; Schema: public; Owner: openchs
--

COPY public.video_telemetric (id, uuid, video_start_time, video_end_time, player_open_time, player_close_time, video_id, user_id, created_datetime, organisation_id, is_voided) FROM stdin;
\.


--
-- Name: account_admin_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.account_admin_id_seq', 1, true);


--
-- Name: account_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.account_id_seq', 1, true);


--
-- Name: address_level_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.address_level_id_seq', 1, true);


--
-- Name: address_level_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.address_level_type_id_seq', 1, true);


--
-- Name: approval_status_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.approval_status_id_seq', 3, true);


--
-- Name: audit_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.audit_id_seq', 939, true);


--
-- Name: batch_job_execution_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.batch_job_execution_seq', 9, true);


--
-- Name: batch_job_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.batch_job_seq', 9, true);


--
-- Name: batch_step_execution_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.batch_step_execution_seq', 9, true);


--
-- Name: catchment_address_mapping_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.catchment_address_mapping_id_seq', 1, true);


--
-- Name: catchment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.catchment_id_seq', 1, true);


--
-- Name: checklist_detail_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.checklist_detail_id_seq', 1, false);


--
-- Name: checklist_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.checklist_id_seq', 1, false);


--
-- Name: checklist_item_detail_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.checklist_item_detail_id_seq', 1, false);


--
-- Name: checklist_item_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.checklist_item_id_seq', 1, false);


--
-- Name: comment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.comment_id_seq', 1, false);


--
-- Name: comment_thread_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.comment_thread_id_seq', 1, false);


--
-- Name: concept_answer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.concept_answer_id_seq', 42, true);


--
-- Name: concept_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.concept_id_seq', 335, true);


--
-- Name: dashboard_card_mapping_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.dashboard_card_mapping_id_seq', 1, false);


--
-- Name: dashboard_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.dashboard_id_seq', 1, false);


--
-- Name: dashboard_section_card_mapping_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.dashboard_section_card_mapping_id_seq', 1, false);


--
-- Name: dashboard_section_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.dashboard_section_id_seq', 1, false);


--
-- Name: decision_concept_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.decision_concept_id_seq', 1, false);


--
-- Name: deps_saved_ddl_deps_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.deps_saved_ddl_deps_id_seq', 1, false);


--
-- Name: encounter_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.encounter_id_seq', 20, true);


--
-- Name: encounter_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.encounter_type_id_seq', 18, true);


--
-- Name: entity_approval_status_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.entity_approval_status_id_seq', 1, false);


--
-- Name: facility_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.facility_id_seq', 1, false);


--
-- Name: form_element_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.form_element_group_id_seq', 7, true);


--
-- Name: form_element_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.form_element_id_seq', 19, true);


--
-- Name: form_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.form_id_seq', 13, true);


--
-- Name: form_mapping_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.form_mapping_id_seq', 13, true);


--
-- Name: gender_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.gender_id_seq', 6, true);


--
-- Name: group_dashboard_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.group_dashboard_id_seq', 1, false);


--
-- Name: group_privilege_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.group_privilege_id_seq', 1, false);


--
-- Name: group_role_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.group_role_id_seq', 2, true);


--
-- Name: group_subject_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.group_subject_id_seq', 1, false);


--
-- Name: groups_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.groups_id_seq', 2, true);


--
-- Name: identifier_assignment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.identifier_assignment_id_seq', 1, false);


--
-- Name: identifier_source_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.identifier_source_id_seq', 1, false);


--
-- Name: identifier_user_assignment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.identifier_user_assignment_id_seq', 1, false);


--
-- Name: individual_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.individual_id_seq', 178, true);


--
-- Name: individual_relation_gender_mapping_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.individual_relation_gender_mapping_id_seq', 43, true);


--
-- Name: individual_relation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.individual_relation_id_seq', 37, true);


--
-- Name: individual_relationship_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.individual_relationship_id_seq', 1, false);


--
-- Name: individual_relationship_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.individual_relationship_type_id_seq', 36, true);


--
-- Name: individual_relative_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.individual_relative_id_seq', 1, false);


--
-- Name: location_location_mapping_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.location_location_mapping_id_seq', 1, false);


--
-- Name: msg91_config_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.msg91_config_id_seq', 1, false);


--
-- Name: news_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.news_id_seq', 1, false);


--
-- Name: non_applicable_form_element_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.non_applicable_form_element_id_seq', 1, false);


--
-- Name: operational_encounter_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.operational_encounter_type_id_seq', 9, true);


--
-- Name: operational_program_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.operational_program_id_seq', 3, true);


--
-- Name: operational_subject_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.operational_subject_type_id_seq', 2, true);


--
-- Name: organisation_config_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.organisation_config_id_seq', 1, true);


--
-- Name: organisation_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.organisation_group_id_seq', 1, false);


--
-- Name: organisation_group_organisation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.organisation_group_organisation_id_seq', 1, false);


--
-- Name: organisation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.organisation_id_seq', 2, true);


--
-- Name: platform_translation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.platform_translation_id_seq', 1, false);


--
-- Name: privilege_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.privilege_id_seq', 26, true);


--
-- Name: program_encounter_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.program_encounter_id_seq', 61, true);


--
-- Name: program_enrolment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.program_enrolment_id_seq', 39, true);


--
-- Name: program_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.program_id_seq', 3, true);


--
-- Name: program_organisation_config_at_risk_concept_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.program_organisation_config_at_risk_concept_id_seq', 1, false);


--
-- Name: program_organisation_config_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.program_organisation_config_id_seq', 1, false);


--
-- Name: program_outcome_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.program_outcome_id_seq', 1, false);


--
-- Name: report_card_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.report_card_id_seq', 1, false);


--
-- Name: rule_dependency_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.rule_dependency_id_seq', 1, false);


--
-- Name: rule_failure_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.rule_failure_log_id_seq', 1, false);


--
-- Name: rule_failure_telemetry_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.rule_failure_telemetry_id_seq', 1, false);


--
-- Name: rule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.rule_id_seq', 1, false);


--
-- Name: standard_report_card_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.standard_report_card_type_id_seq', 10, true);


--
-- Name: subject_migration_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.subject_migration_id_seq', 1, false);


--
-- Name: subject_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.subject_type_id_seq', 7, true);


--
-- Name: sync_telemetry_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.sync_telemetry_id_seq', 1, false);


--
-- Name: translation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.translation_id_seq', 1, false);


--
-- Name: user_facility_mapping_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.user_facility_mapping_id_seq', 1, false);


--
-- Name: user_group_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.user_group_id_seq', 2, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.users_id_seq', 2, true);


--
-- Name: video_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.video_id_seq', 1, false);


--
-- Name: video_telemetric_id_seq; Type: SEQUENCE SET; Schema: public; Owner: openchs
--

SELECT pg_catalog.setval('public.video_telemetric_id_seq', 1, false);


--
-- Name: account_admin account_admin_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.account_admin
    ADD CONSTRAINT account_admin_pkey PRIMARY KEY (id);


--
-- Name: account account_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.account
    ADD CONSTRAINT account_pkey PRIMARY KEY (id);


--
-- Name: address_level address_level_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level
    ADD CONSTRAINT address_level_pkey PRIMARY KEY (id);


--
-- Name: address_level_type address_level_type_name_organisation_id_unique; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level_type
    ADD CONSTRAINT address_level_type_name_organisation_id_unique UNIQUE (name, organisation_id);


--
-- Name: address_level_type address_level_type_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level_type
    ADD CONSTRAINT address_level_type_pkey PRIMARY KEY (id);


--
-- Name: address_level address_level_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level
    ADD CONSTRAINT address_level_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: approval_status approval_status_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.approval_status
    ADD CONSTRAINT approval_status_pkey PRIMARY KEY (id);


--
-- Name: audit audit_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.audit
    ADD CONSTRAINT audit_pkey PRIMARY KEY (id);


--
-- Name: batch_job_execution_context batch_job_execution_context_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.batch_job_execution_context
    ADD CONSTRAINT batch_job_execution_context_pkey PRIMARY KEY (job_execution_id);


--
-- Name: batch_job_execution batch_job_execution_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.batch_job_execution
    ADD CONSTRAINT batch_job_execution_pkey PRIMARY KEY (job_execution_id);


--
-- Name: batch_job_instance batch_job_instance_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.batch_job_instance
    ADD CONSTRAINT batch_job_instance_pkey PRIMARY KEY (job_instance_id);


--
-- Name: batch_step_execution_context batch_step_execution_context_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.batch_step_execution_context
    ADD CONSTRAINT batch_step_execution_context_pkey PRIMARY KEY (step_execution_id);


--
-- Name: batch_step_execution batch_step_execution_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.batch_step_execution
    ADD CONSTRAINT batch_step_execution_pkey PRIMARY KEY (step_execution_id);


--
-- Name: report_card card_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.report_card
    ADD CONSTRAINT card_pkey PRIMARY KEY (id);


--
-- Name: report_card card_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.report_card
    ADD CONSTRAINT card_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: catchment_address_mapping catchment_address_mapping_catchment_id_address_level_id_unique; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.catchment_address_mapping
    ADD CONSTRAINT catchment_address_mapping_catchment_id_address_level_id_unique UNIQUE (catchment_id, addresslevel_id);


--
-- Name: catchment_address_mapping catchment_address_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.catchment_address_mapping
    ADD CONSTRAINT catchment_address_mapping_pkey PRIMARY KEY (id);


--
-- Name: catchment catchment_name_organisation_id_unique; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.catchment
    ADD CONSTRAINT catchment_name_organisation_id_unique UNIQUE (name, organisation_id);


--
-- Name: catchment catchment_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.catchment
    ADD CONSTRAINT catchment_pkey PRIMARY KEY (id);


--
-- Name: catchment catchment_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.catchment
    ADD CONSTRAINT catchment_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: checklist checklist_checklist_detail_id_program_enrolment_id_unique; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist
    ADD CONSTRAINT checklist_checklist_detail_id_program_enrolment_id_unique UNIQUE (checklist_detail_id, program_enrolment_id);


--
-- Name: checklist_detail checklist_detail_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_detail
    ADD CONSTRAINT checklist_detail_pkey PRIMARY KEY (id);


--
-- Name: checklist_detail checklist_detail_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_detail
    ADD CONSTRAINT checklist_detail_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: checklist_item_detail checklist_item_detail_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item_detail
    ADD CONSTRAINT checklist_item_detail_pkey PRIMARY KEY (id);


--
-- Name: checklist_item_detail checklist_item_detail_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item_detail
    ADD CONSTRAINT checklist_item_detail_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: checklist_item checklist_item_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item
    ADD CONSTRAINT checklist_item_pkey PRIMARY KEY (id);


--
-- Name: checklist_item checklist_item_uuid_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item
    ADD CONSTRAINT checklist_item_uuid_key UNIQUE (uuid);


--
-- Name: checklist checklist_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist
    ADD CONSTRAINT checklist_pkey PRIMARY KEY (id);


--
-- Name: checklist checklist_uuid_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist
    ADD CONSTRAINT checklist_uuid_key UNIQUE (uuid);


--
-- Name: comment comment_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_pkey PRIMARY KEY (id);


--
-- Name: comment_thread comment_thread_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.comment_thread
    ADD CONSTRAINT comment_thread_pkey PRIMARY KEY (id);


--
-- Name: concept_answer concept_answer_concept_id_answer_concept_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept_answer
    ADD CONSTRAINT concept_answer_concept_id_answer_concept_id_key UNIQUE (concept_id, answer_concept_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: concept_answer concept_answer_concept_id_answer_concept_id_organisation_id_uni; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept_answer
    ADD CONSTRAINT concept_answer_concept_id_answer_concept_id_organisation_id_uni UNIQUE (concept_id, answer_concept_id, organisation_id);


--
-- Name: concept_answer concept_answer_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept_answer
    ADD CONSTRAINT concept_answer_pkey PRIMARY KEY (id);


--
-- Name: concept_answer concept_answer_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept_answer
    ADD CONSTRAINT concept_answer_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: concept concept_name_orgid; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept
    ADD CONSTRAINT concept_name_orgid UNIQUE (name, organisation_id);


--
-- Name: concept concept_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept
    ADD CONSTRAINT concept_pkey PRIMARY KEY (id);


--
-- Name: concept concept_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept
    ADD CONSTRAINT concept_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: dashboard_card_mapping dashboard_card_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_card_mapping
    ADD CONSTRAINT dashboard_card_mapping_pkey PRIMARY KEY (id);


--
-- Name: dashboard_card_mapping dashboard_card_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_card_mapping
    ADD CONSTRAINT dashboard_card_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: dashboard dashboard_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard
    ADD CONSTRAINT dashboard_pkey PRIMARY KEY (id);


--
-- Name: dashboard_section_card_mapping dashboard_section_card_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section_card_mapping
    ADD CONSTRAINT dashboard_section_card_mapping_pkey PRIMARY KEY (id);


--
-- Name: dashboard_section_card_mapping dashboard_section_card_mapping_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section_card_mapping
    ADD CONSTRAINT dashboard_section_card_mapping_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: dashboard_section dashboard_section_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section
    ADD CONSTRAINT dashboard_section_pkey PRIMARY KEY (id);


--
-- Name: dashboard_section dashboard_section_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section
    ADD CONSTRAINT dashboard_section_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: dashboard dashboard_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard
    ADD CONSTRAINT dashboard_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: decision_concept decision_concept_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.decision_concept
    ADD CONSTRAINT decision_concept_pkey PRIMARY KEY (id);


--
-- Name: deps_saved_ddl deps_saved_ddl_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.deps_saved_ddl
    ADD CONSTRAINT deps_saved_ddl_pkey PRIMARY KEY (deps_id);


--
-- Name: encounter encounter_legacy_id_organisation_id_uniq_idx; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter
    ADD CONSTRAINT encounter_legacy_id_organisation_id_uniq_idx UNIQUE (legacy_id, organisation_id);


--
-- Name: encounter encounter_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter
    ADD CONSTRAINT encounter_pkey PRIMARY KEY (id);


--
-- Name: encounter_type encounter_type_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter_type
    ADD CONSTRAINT encounter_type_pkey PRIMARY KEY (id);


--
-- Name: encounter_type encounter_type_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter_type
    ADD CONSTRAINT encounter_type_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: encounter encounter_uuid_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter
    ADD CONSTRAINT encounter_uuid_key UNIQUE (uuid);


--
-- Name: entity_approval_status entity_approval_status_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.entity_approval_status
    ADD CONSTRAINT entity_approval_status_pkey PRIMARY KEY (id);


--
-- Name: facility facility_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.facility
    ADD CONSTRAINT facility_pkey PRIMARY KEY (id);


--
-- Name: form_element form_element_form_element_group_id_display_order_organisati_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element
    ADD CONSTRAINT form_element_form_element_group_id_display_order_organisati_key UNIQUE (form_element_group_id, display_order, organisation_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: form_element_group form_element_group_form_id_display_order_organisation_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element_group
    ADD CONSTRAINT form_element_group_form_id_display_order_organisation_id_key UNIQUE (form_id, display_order, organisation_id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: form_element_group form_element_group_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element_group
    ADD CONSTRAINT form_element_group_pkey PRIMARY KEY (id);


--
-- Name: form_element_group form_element_group_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element_group
    ADD CONSTRAINT form_element_group_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: form_element form_element_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element
    ADD CONSTRAINT form_element_pkey PRIMARY KEY (id);


--
-- Name: form_element form_element_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element
    ADD CONSTRAINT form_element_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: form_mapping form_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_mapping
    ADD CONSTRAINT form_mapping_pkey PRIMARY KEY (id);


--
-- Name: form_mapping form_mapping_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_mapping
    ADD CONSTRAINT form_mapping_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: form form_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form
    ADD CONSTRAINT form_pkey PRIMARY KEY (id);


--
-- Name: form form_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form
    ADD CONSTRAINT form_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: gender gender_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.gender
    ADD CONSTRAINT gender_pkey PRIMARY KEY (id);


--
-- Name: gender gender_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.gender
    ADD CONSTRAINT gender_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: group_dashboard group_dashboard_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_dashboard
    ADD CONSTRAINT group_dashboard_pkey PRIMARY KEY (id);


--
-- Name: group_privilege group_privilege_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_privilege
    ADD CONSTRAINT group_privilege_pkey PRIMARY KEY (id);


--
-- Name: group_role group_role_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_role
    ADD CONSTRAINT group_role_pkey PRIMARY KEY (id);


--
-- Name: group_role group_role_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_role
    ADD CONSTRAINT group_role_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: group_subject group_subject_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_subject
    ADD CONSTRAINT group_subject_pkey PRIMARY KEY (id);


--
-- Name: groups groups_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT groups_pkey PRIMARY KEY (id);


--
-- Name: identifier_assignment identifier_assignment_identifier_source_id_identifier_organ_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_assignment
    ADD CONSTRAINT identifier_assignment_identifier_source_id_identifier_organ_key UNIQUE (identifier_source_id, identifier, organisation_id);


--
-- Name: identifier_assignment identifier_assignment_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_assignment
    ADD CONSTRAINT identifier_assignment_pkey PRIMARY KEY (id);


--
-- Name: identifier_assignment identifier_assignment_uuid_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_assignment
    ADD CONSTRAINT identifier_assignment_uuid_key UNIQUE (uuid);


--
-- Name: identifier_source identifier_source_name_organisation_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_source
    ADD CONSTRAINT identifier_source_name_organisation_id_key UNIQUE (name, organisation_id);


--
-- Name: identifier_source identifier_source_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_source
    ADD CONSTRAINT identifier_source_pkey PRIMARY KEY (id);


--
-- Name: identifier_source identifier_source_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_source
    ADD CONSTRAINT identifier_source_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: identifier_user_assignment identifier_user_assignment_identifier_source_id_assigned_to_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_user_assignment
    ADD CONSTRAINT identifier_user_assignment_identifier_source_id_assigned_to_key UNIQUE (identifier_source_id, assigned_to_user_id, identifier_start);


--
-- Name: identifier_user_assignment identifier_user_assignment_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_user_assignment
    ADD CONSTRAINT identifier_user_assignment_pkey PRIMARY KEY (id);


--
-- Name: identifier_user_assignment identifier_user_assignment_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_user_assignment
    ADD CONSTRAINT identifier_user_assignment_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: individual individual_legacy_id_organisation_id_uniq_idx; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual
    ADD CONSTRAINT individual_legacy_id_organisation_id_uniq_idx UNIQUE (legacy_id, organisation_id);


--
-- Name: individual individual_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual
    ADD CONSTRAINT individual_pkey PRIMARY KEY (id);


--
-- Name: individual_relation_gender_mapping individual_relation_gender_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relation_gender_mapping
    ADD CONSTRAINT individual_relation_gender_mapping_pkey PRIMARY KEY (id);


--
-- Name: individual_relation individual_relation_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relation
    ADD CONSTRAINT individual_relation_pkey PRIMARY KEY (id);


--
-- Name: individual_relationship individual_relationship_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relationship
    ADD CONSTRAINT individual_relationship_pkey PRIMARY KEY (id);


--
-- Name: individual_relationship_type individual_relationship_type_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relationship_type
    ADD CONSTRAINT individual_relationship_type_pkey PRIMARY KEY (id);


--
-- Name: individual_relative individual_relative_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relative
    ADD CONSTRAINT individual_relative_pkey PRIMARY KEY (id);


--
-- Name: individual individual_uuid_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual
    ADD CONSTRAINT individual_uuid_key UNIQUE (uuid);


--
-- Name: batch_job_instance job_inst_un; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.batch_job_instance
    ADD CONSTRAINT job_inst_un UNIQUE (job_name, job_key);


--
-- Name: location_location_mapping location_location_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.location_location_mapping
    ADD CONSTRAINT location_location_mapping_pkey PRIMARY KEY (id);


--
-- Name: msg91_config msg91_config_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.msg91_config
    ADD CONSTRAINT msg91_config_pkey PRIMARY KEY (id);


--
-- Name: news news_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.news
    ADD CONSTRAINT news_pkey PRIMARY KEY (id);


--
-- Name: non_applicable_form_element non_applicable_form_element_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.non_applicable_form_element
    ADD CONSTRAINT non_applicable_form_element_pkey PRIMARY KEY (id);


--
-- Name: operational_encounter_type operational_encounter_type_encounter_type_organisation_id_uniqu; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_encounter_type
    ADD CONSTRAINT operational_encounter_type_encounter_type_organisation_id_uniqu UNIQUE (encounter_type_id, organisation_id);


--
-- Name: operational_encounter_type operational_encounter_type_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_encounter_type
    ADD CONSTRAINT operational_encounter_type_pkey PRIMARY KEY (id);


--
-- Name: operational_program operational_program_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_program
    ADD CONSTRAINT operational_program_pkey PRIMARY KEY (id);


--
-- Name: operational_program operational_program_program_id_organisation_id_unique; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_program
    ADD CONSTRAINT operational_program_program_id_organisation_id_unique UNIQUE (program_id, organisation_id);


--
-- Name: operational_subject_type operational_subject_type_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_subject_type
    ADD CONSTRAINT operational_subject_type_pkey PRIMARY KEY (id);


--
-- Name: operational_subject_type operational_subject_type_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_subject_type
    ADD CONSTRAINT operational_subject_type_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: organisation_config organisation_config_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_config
    ADD CONSTRAINT organisation_config_pkey PRIMARY KEY (id);


--
-- Name: organisation_config organisation_config_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_config
    ADD CONSTRAINT organisation_config_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: organisation organisation_db_user_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation
    ADD CONSTRAINT organisation_db_user_key UNIQUE (db_user);


--
-- Name: organisation_group_organisation organisation_group_organisation_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_group_organisation
    ADD CONSTRAINT organisation_group_organisation_pkey PRIMARY KEY (id);


--
-- Name: organisation_group organisation_group_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_group
    ADD CONSTRAINT organisation_group_pkey PRIMARY KEY (id);


--
-- Name: organisation organisation_media_directory_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation
    ADD CONSTRAINT organisation_media_directory_key UNIQUE (media_directory);


--
-- Name: organisation organisation_name_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation
    ADD CONSTRAINT organisation_name_key UNIQUE (name);


--
-- Name: organisation organisation_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation
    ADD CONSTRAINT organisation_pkey PRIMARY KEY (id);


--
-- Name: organisation organisation_uuid_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation
    ADD CONSTRAINT organisation_uuid_key UNIQUE (uuid);


--
-- Name: platform_translation platform_translation_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.platform_translation
    ADD CONSTRAINT platform_translation_pkey PRIMARY KEY (id);


--
-- Name: privilege privilege_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.privilege
    ADD CONSTRAINT privilege_pkey PRIMARY KEY (id);


--
-- Name: program_encounter program_encounter_legacy_id_organisation_id_uniq_idx; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_encounter
    ADD CONSTRAINT program_encounter_legacy_id_organisation_id_uniq_idx UNIQUE (legacy_id, organisation_id);


--
-- Name: program_encounter program_encounter_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_encounter
    ADD CONSTRAINT program_encounter_pkey PRIMARY KEY (id);


--
-- Name: program_encounter program_encounter_uuid_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_encounter
    ADD CONSTRAINT program_encounter_uuid_key UNIQUE (uuid);


--
-- Name: program_enrolment program_enrolment_legacy_id_organisation_id_uniq_idx; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_enrolment
    ADD CONSTRAINT program_enrolment_legacy_id_organisation_id_uniq_idx UNIQUE (legacy_id, organisation_id);


--
-- Name: program_enrolment program_enrolment_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_enrolment
    ADD CONSTRAINT program_enrolment_pkey PRIMARY KEY (id);


--
-- Name: program_enrolment program_enrolment_uuid_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_enrolment
    ADD CONSTRAINT program_enrolment_uuid_key UNIQUE (uuid);


--
-- Name: program_organisation_config_at_risk_concept program_organisation_config_at_risk_concept_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_organisation_config_at_risk_concept
    ADD CONSTRAINT program_organisation_config_at_risk_concept_pkey PRIMARY KEY (id);


--
-- Name: program_organisation_config program_organisation_config_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_organisation_config
    ADD CONSTRAINT program_organisation_config_pkey PRIMARY KEY (id);


--
-- Name: program_organisation_config program_organisation_config_uuid_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_organisation_config
    ADD CONSTRAINT program_organisation_config_uuid_key UNIQUE (uuid);


--
-- Name: program_organisation_config program_organisation_unique_constraint; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_organisation_config
    ADD CONSTRAINT program_organisation_unique_constraint UNIQUE (program_id, organisation_id);


--
-- Name: program_outcome program_outcome_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_outcome
    ADD CONSTRAINT program_outcome_pkey PRIMARY KEY (id);


--
-- Name: program_outcome program_outcome_uuid_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_outcome
    ADD CONSTRAINT program_outcome_uuid_key UNIQUE (uuid);


--
-- Name: program program_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program
    ADD CONSTRAINT program_pkey PRIMARY KEY (id);


--
-- Name: program program_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program
    ADD CONSTRAINT program_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: rule_dependency rule_dependency_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule_dependency
    ADD CONSTRAINT rule_dependency_pkey PRIMARY KEY (id);


--
-- Name: rule_dependency rule_dependency_uuid_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule_dependency
    ADD CONSTRAINT rule_dependency_uuid_key UNIQUE (uuid);


--
-- Name: rule_failure_log rule_failure_log_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule_failure_log
    ADD CONSTRAINT rule_failure_log_pkey PRIMARY KEY (id);


--
-- Name: rule_failure_telemetry rule_failure_telemetry_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule_failure_telemetry
    ADD CONSTRAINT rule_failure_telemetry_pkey PRIMARY KEY (id);


--
-- Name: rule rule_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule
    ADD CONSTRAINT rule_pkey PRIMARY KEY (id);


--
-- Name: rule rule_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule
    ADD CONSTRAINT rule_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: schema_version schema_version_pk; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.schema_version
    ADD CONSTRAINT schema_version_pk PRIMARY KEY (installed_rank);


--
-- Name: standard_report_card_type standard_report_card_type_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.standard_report_card_type
    ADD CONSTRAINT standard_report_card_type_pkey PRIMARY KEY (id);


--
-- Name: subject_migration subject_migration_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.subject_migration
    ADD CONSTRAINT subject_migration_pkey PRIMARY KEY (id);


--
-- Name: subject_migration subject_migration_uuid_organisation_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.subject_migration
    ADD CONSTRAINT subject_migration_uuid_organisation_id_key UNIQUE (uuid, organisation_id);


--
-- Name: subject_type subject_type_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.subject_type
    ADD CONSTRAINT subject_type_pkey PRIMARY KEY (id);


--
-- Name: sync_telemetry sync_telemetry_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.sync_telemetry
    ADD CONSTRAINT sync_telemetry_pkey PRIMARY KEY (id);


--
-- Name: translation translation_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.translation
    ADD CONSTRAINT translation_pkey PRIMARY KEY (id);


--
-- Name: translation translation_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.translation
    ADD CONSTRAINT translation_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: rule unique_fn_rule_name; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule
    ADD CONSTRAINT unique_fn_rule_name UNIQUE (organisation_id, fn_name);


--
-- Name: address_level unique_name_per_level; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level
    ADD CONSTRAINT unique_name_per_level UNIQUE (title, type_id, parent_id, organisation_id);


--
-- Name: rule unique_rule_name; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule
    ADD CONSTRAINT unique_rule_name UNIQUE (organisation_id, name);


--
-- Name: user_facility_mapping user_facility_mapping_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.user_facility_mapping
    ADD CONSTRAINT user_facility_mapping_pkey PRIMARY KEY (id);


--
-- Name: user_group user_group_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.user_group
    ADD CONSTRAINT user_group_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: video video_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.video
    ADD CONSTRAINT video_pkey PRIMARY KEY (id);


--
-- Name: video_telemetric video_telemetric_pkey; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.video_telemetric
    ADD CONSTRAINT video_telemetric_pkey PRIMARY KEY (id);


--
-- Name: video video_uuid_org_id_key; Type: CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.video
    ADD CONSTRAINT video_uuid_org_id_key UNIQUE (uuid, organisation_id);


--
-- Name: address_level_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX address_level_organisation_id__index ON public.address_level USING btree (organisation_id);


--
-- Name: address_level_type_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX address_level_type_organisation_id__index ON public.address_level_type USING btree (organisation_id);


--
-- Name: catchment_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX catchment_organisation_id__index ON public.catchment USING btree (organisation_id);


--
-- Name: checklist_checklist_detail_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_checklist_detail_id_index ON public.checklist USING btree (checklist_detail_id);


--
-- Name: checklist_detail_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_detail_organisation_id__index ON public.checklist_detail USING btree (organisation_id);


--
-- Name: checklist_item_checklist_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_item_checklist_id_index ON public.checklist_item USING btree (checklist_id);


--
-- Name: checklist_item_checklist_item_detail_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_item_checklist_item_detail_id_index ON public.checklist_item USING btree (checklist_item_detail_id);


--
-- Name: checklist_item_detail_checklist_detail_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_item_detail_checklist_detail_id_index ON public.checklist_item_detail USING btree (checklist_detail_id);


--
-- Name: checklist_item_detail_concept_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_item_detail_concept_id_index ON public.checklist_item_detail USING btree (concept_id);


--
-- Name: checklist_item_detail_dependent_on_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_item_detail_dependent_on_index ON public.checklist_item_detail USING btree (dependent_on);


--
-- Name: checklist_item_detail_form_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_item_detail_form_id_index ON public.checklist_item_detail USING btree (form_id);


--
-- Name: checklist_item_detail_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_item_detail_organisation_id__index ON public.checklist_item_detail USING btree (organisation_id);


--
-- Name: checklist_item_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_item_organisation_id__index ON public.checklist_item USING btree (organisation_id);


--
-- Name: checklist_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_organisation_id__index ON public.checklist USING btree (organisation_id);


--
-- Name: checklist_program_enrolment_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX checklist_program_enrolment_id_index ON public.checklist USING btree (program_enrolment_id);


--
-- Name: comment_subject_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX comment_subject_id_index ON public.comment USING btree (subject_id);


--
-- Name: comment_thread_uuid_organisation_id_uniq_idx; Type: INDEX; Schema: public; Owner: openchs
--

CREATE UNIQUE INDEX comment_thread_uuid_organisation_id_uniq_idx ON public.comment USING btree (uuid, organisation_id);


--
-- Name: comment_uuid_organisation_id_uniq_idx; Type: INDEX; Schema: public; Owner: openchs
--

CREATE UNIQUE INDEX comment_uuid_organisation_id_uniq_idx ON public.comment USING btree (uuid, organisation_id);


--
-- Name: concept_answer_answer_concept_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX concept_answer_answer_concept_id_index ON public.concept_answer USING btree (answer_concept_id);


--
-- Name: concept_answer_concept_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX concept_answer_concept_id_index ON public.concept_answer USING btree (concept_id);


--
-- Name: concept_answer_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX concept_answer_organisation_id__index ON public.concept_answer USING btree (organisation_id);


--
-- Name: concept_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX concept_organisation_id__index ON public.concept USING btree (organisation_id);


--
-- Name: encounter_encounter_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX encounter_encounter_type_id_index ON public.encounter USING btree (encounter_type_id);


--
-- Name: encounter_individual_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX encounter_individual_id_index ON public.encounter USING btree (individual_id);


--
-- Name: encounter_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX encounter_organisation_id__index ON public.encounter USING btree (organisation_id);


--
-- Name: encounter_type_concept_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX encounter_type_concept_id_index ON public.encounter_type USING btree (concept_id);


--
-- Name: encounter_type_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX encounter_type_organisation_id__index ON public.encounter_type USING btree (organisation_id);


--
-- Name: facility_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX facility_organisation_id__index ON public.facility USING btree (organisation_id);


--
-- Name: form_element_concept_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX form_element_concept_id_index ON public.form_element USING btree (concept_id);


--
-- Name: form_element_form_element_group_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX form_element_form_element_group_id_index ON public.form_element USING btree (form_element_group_id);


--
-- Name: form_element_group_form_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX form_element_group_form_id_index ON public.form_element_group USING btree (form_id);


--
-- Name: form_element_group_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX form_element_group_organisation_id__index ON public.form_element_group USING btree (organisation_id);


--
-- Name: form_element_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX form_element_organisation_id__index ON public.form_element USING btree (organisation_id);


--
-- Name: form_mapping_form_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX form_mapping_form_id_index ON public.form_mapping USING btree (form_id);


--
-- Name: form_mapping_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX form_mapping_organisation_id__index ON public.form_mapping USING btree (organisation_id);


--
-- Name: form_mapping_subject_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX form_mapping_subject_type_id_index ON public.form_mapping USING btree (subject_type_id);


--
-- Name: form_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX form_organisation_id__index ON public.form USING btree (organisation_id);


--
-- Name: gender_concept_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX gender_concept_id_index ON public.gender USING btree (concept_id);


--
-- Name: gender_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX gender_organisation_id__index ON public.gender USING btree (organisation_id);


--
-- Name: group_privilege_checklist_detail_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX group_privilege_checklist_detail_id_index ON public.group_privilege USING btree (checklist_detail_id);


--
-- Name: group_privilege_encounter_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX group_privilege_encounter_type_id_index ON public.group_privilege USING btree (encounter_type_id);


--
-- Name: group_privilege_group_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX group_privilege_group_id_index ON public.group_privilege USING btree (group_id);


--
-- Name: group_privilege_program_encounter_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX group_privilege_program_encounter_type_id_index ON public.group_privilege USING btree (program_encounter_type_id);


--
-- Name: group_privilege_program_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX group_privilege_program_id_index ON public.group_privilege USING btree (program_id);


--
-- Name: group_privilege_subject_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX group_privilege_subject_type_id_index ON public.group_privilege USING btree (subject_type_id);


--
-- Name: group_role_group_subject_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX group_role_group_subject_type_id_index ON public.group_role USING btree (group_subject_type_id);


--
-- Name: group_role_member_subject_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX group_role_member_subject_type_id_index ON public.group_role USING btree (member_subject_type_id);


--
-- Name: group_subject_group_role_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX group_subject_group_role_id_index ON public.group_subject USING btree (group_role_id);


--
-- Name: group_subject_group_subject_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX group_subject_group_subject_id_index ON public.group_subject USING btree (group_subject_id);


--
-- Name: group_subject_member_subject_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX group_subject_member_subject_id_index ON public.group_subject USING btree (member_subject_id);


--
-- Name: identifier_assignment_identifier_source_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX identifier_assignment_identifier_source_id_index ON public.identifier_assignment USING btree (identifier_source_id);


--
-- Name: identifier_assignment_individual_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX identifier_assignment_individual_id_index ON public.identifier_assignment USING btree (individual_id);


--
-- Name: identifier_assignment_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX identifier_assignment_organisation_id__index ON public.identifier_assignment USING btree (organisation_id);


--
-- Name: identifier_assignment_program_enrolment_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX identifier_assignment_program_enrolment_id_index ON public.identifier_assignment USING btree (program_enrolment_id);


--
-- Name: identifier_source_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX identifier_source_organisation_id__index ON public.identifier_source USING btree (organisation_id);


--
-- Name: identifier_user_assignment_identifier_source_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX identifier_user_assignment_identifier_source_id_index ON public.identifier_user_assignment USING btree (identifier_source_id);


--
-- Name: identifier_user_assignment_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX identifier_user_assignment_organisation_id__index ON public.identifier_user_assignment USING btree (organisation_id);


--
-- Name: idx_individual_obs; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX idx_individual_obs ON public.individual USING gin (observations jsonb_path_ops);


--
-- Name: idx_program_encounter_obs; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX idx_program_encounter_obs ON public.program_encounter USING gin (observations jsonb_path_ops);


--
-- Name: idx_program_enrolment_obs; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX idx_program_enrolment_obs ON public.program_enrolment USING gin (observations jsonb_path_ops);


--
-- Name: individual_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_organisation_id__index ON public.individual USING btree (organisation_id);


--
-- Name: individual_relation_gender_mapping_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relation_gender_mapping_organisation_id__index ON public.individual_relation_gender_mapping USING btree (organisation_id);


--
-- Name: individual_relation_gender_mapping_relation_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relation_gender_mapping_relation_id_index ON public.individual_relation_gender_mapping USING btree (relation_id);


--
-- Name: individual_relation_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relation_organisation_id__index ON public.individual_relation USING btree (organisation_id);


--
-- Name: individual_relationship_individual_a_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relationship_individual_a_id_index ON public.individual_relationship USING btree (individual_a_id);


--
-- Name: individual_relationship_individual_b_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relationship_individual_b_id_index ON public.individual_relationship USING btree (individual_b_id);


--
-- Name: individual_relationship_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relationship_organisation_id__index ON public.individual_relationship USING btree (organisation_id);


--
-- Name: individual_relationship_relationship_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relationship_relationship_type_id_index ON public.individual_relationship USING btree (relationship_type_id);


--
-- Name: individual_relationship_type_individual_a_is_to_b_relation_id_i; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relationship_type_individual_a_is_to_b_relation_id_i ON public.individual_relationship_type USING btree (individual_a_is_to_b_relation_id);


--
-- Name: individual_relationship_type_individual_b_is_to_a_relation_id_i; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relationship_type_individual_b_is_to_a_relation_id_i ON public.individual_relationship_type USING btree (individual_b_is_to_a_relation_id);


--
-- Name: individual_relationship_type_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relationship_type_organisation_id__index ON public.individual_relationship_type USING btree (organisation_id);


--
-- Name: individual_relative_individual_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relative_individual_id_index ON public.individual_relative USING btree (individual_id);


--
-- Name: individual_relative_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relative_organisation_id__index ON public.individual_relative USING btree (organisation_id);


--
-- Name: individual_relative_relative_individual_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_relative_relative_individual_id_index ON public.individual_relative USING btree (relative_individual_id);


--
-- Name: individual_subject_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX individual_subject_type_id_index ON public.individual USING btree (subject_type_id);


--
-- Name: location_location_mapping_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX location_location_mapping_organisation_id__index ON public.location_location_mapping USING btree (organisation_id);


--
-- Name: news_published_date_idx; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX news_published_date_idx ON public.news USING btree (organisation_id, published_date);


--
-- Name: news_uuid_organisation_id_uniq_idx; Type: INDEX; Schema: public; Owner: openchs
--

CREATE UNIQUE INDEX news_uuid_organisation_id_uniq_idx ON public.news USING btree (uuid, organisation_id);


--
-- Name: non_applicable_form_element_form_element_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX non_applicable_form_element_form_element_id_index ON public.non_applicable_form_element USING btree (form_element_id);


--
-- Name: non_applicable_form_element_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX non_applicable_form_element_organisation_id__index ON public.non_applicable_form_element USING btree (organisation_id);


--
-- Name: operational_encounter_type_encounter_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX operational_encounter_type_encounter_type_id_index ON public.operational_encounter_type USING btree (encounter_type_id);


--
-- Name: operational_encounter_type_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX operational_encounter_type_organisation_id__index ON public.operational_encounter_type USING btree (organisation_id);


--
-- Name: operational_program_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX operational_program_organisation_id__index ON public.operational_program USING btree (organisation_id);


--
-- Name: operational_program_program_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX operational_program_program_id_index ON public.operational_program USING btree (program_id);


--
-- Name: operational_subject_type_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX operational_subject_type_organisation_id__index ON public.operational_subject_type USING btree (organisation_id);


--
-- Name: operational_subject_type_subject_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX operational_subject_type_subject_type_id_index ON public.operational_subject_type USING btree (subject_type_id);


--
-- Name: program_encounter_encounter_type_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX program_encounter_encounter_type_id_index ON public.program_encounter USING btree (encounter_type_id);


--
-- Name: program_encounter_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX program_encounter_organisation_id__index ON public.program_encounter USING btree (organisation_id);


--
-- Name: program_encounter_program_enrolment_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX program_encounter_program_enrolment_id_index ON public.program_encounter USING btree (program_enrolment_id);


--
-- Name: program_enrolment_individual_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX program_enrolment_individual_id_index ON public.program_enrolment USING btree (individual_id);


--
-- Name: program_enrolment_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX program_enrolment_organisation_id__index ON public.program_enrolment USING btree (organisation_id);


--
-- Name: program_enrolment_program_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX program_enrolment_program_id_index ON public.program_enrolment USING btree (program_id);


--
-- Name: program_organisation_config_at_risk_concept_concept_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX program_organisation_config_at_risk_concept_concept_id_index ON public.program_organisation_config_at_risk_concept USING btree (concept_id);


--
-- Name: program_organisation_config_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX program_organisation_config_organisation_id__index ON public.program_organisation_config USING btree (organisation_id);


--
-- Name: program_organisation_config_program_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX program_organisation_config_program_id_index ON public.program_organisation_config USING btree (program_id);


--
-- Name: program_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX program_organisation_id__index ON public.program USING btree (organisation_id);


--
-- Name: program_outcome_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX program_outcome_organisation_id__index ON public.program_outcome USING btree (organisation_id);


--
-- Name: rule_dependency_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX rule_dependency_organisation_id__index ON public.rule_dependency USING btree (organisation_id);


--
-- Name: rule_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX rule_organisation_id__index ON public.rule USING btree (organisation_id);


--
-- Name: schema_version_s_idx; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX schema_version_s_idx ON public.schema_version USING btree (success);


--
-- Name: subject_type_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX subject_type_organisation_id__index ON public.subject_type USING btree (organisation_id);


--
-- Name: sync_telemetry_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX sync_telemetry_organisation_id__index ON public.sync_telemetry USING btree (organisation_id);


--
-- Name: user_facility_mapping_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX user_facility_mapping_organisation_id__index ON public.user_facility_mapping USING btree (organisation_id);


--
-- Name: user_group_group_id_index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX user_group_group_id_index ON public.user_group USING btree (group_id);


--
-- Name: users_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX users_organisation_id__index ON public.users USING btree (organisation_id);


--
-- Name: users_username_idx; Type: INDEX; Schema: public; Owner: openchs
--

CREATE UNIQUE INDEX users_username_idx ON public.users USING btree (username);


--
-- Name: video_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX video_organisation_id__index ON public.video USING btree (organisation_id);


--
-- Name: video_telemetric_organisation_id__index; Type: INDEX; Schema: public; Owner: openchs
--

CREATE INDEX video_telemetric_organisation_id__index ON public.video_telemetric USING btree (organisation_id);


--
-- Name: account_admin account_admin_account; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.account_admin
    ADD CONSTRAINT account_admin_account FOREIGN KEY (account_id) REFERENCES public.account(id);


--
-- Name: account_admin account_admin_user; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.account_admin
    ADD CONSTRAINT account_admin_user FOREIGN KEY (admin_id) REFERENCES public.users(id);


--
-- Name: address_level address_level_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level
    ADD CONSTRAINT address_level_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: address_level address_level_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level
    ADD CONSTRAINT address_level_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: address_level address_level_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level
    ADD CONSTRAINT address_level_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.address_level(id);


--
-- Name: address_level address_level_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level
    ADD CONSTRAINT address_level_type_id_fkey FOREIGN KEY (type_id) REFERENCES public.address_level_type(id);


--
-- Name: address_level_type address_level_type_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.address_level_type
    ADD CONSTRAINT address_level_type_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.address_level_type(id);


--
-- Name: report_card card_master_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.report_card
    ADD CONSTRAINT card_master_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: report_card card_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.report_card
    ADD CONSTRAINT card_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: catchment_address_mapping catchment_address_mapping_address; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.catchment_address_mapping
    ADD CONSTRAINT catchment_address_mapping_address FOREIGN KEY (addresslevel_id) REFERENCES public.address_level(id);


--
-- Name: catchment_address_mapping catchment_address_mapping_catchment; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.catchment_address_mapping
    ADD CONSTRAINT catchment_address_mapping_catchment FOREIGN KEY (catchment_id) REFERENCES public.catchment(id);


--
-- Name: catchment catchment_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.catchment
    ADD CONSTRAINT catchment_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: catchment catchment_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.catchment
    ADD CONSTRAINT catchment_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: checklist checklist_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist
    ADD CONSTRAINT checklist_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: checklist checklist_checklist_detail_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist
    ADD CONSTRAINT checklist_checklist_detail_id_fkey FOREIGN KEY (checklist_detail_id) REFERENCES public.checklist_detail(id);


--
-- Name: checklist_detail checklist_detail_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_detail
    ADD CONSTRAINT checklist_detail_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: checklist_item checklist_item_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item
    ADD CONSTRAINT checklist_item_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: checklist_item checklist_item_checklist; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item
    ADD CONSTRAINT checklist_item_checklist FOREIGN KEY (checklist_id) REFERENCES public.checklist(id);


--
-- Name: checklist_item checklist_item_checklist_item_detail_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item
    ADD CONSTRAINT checklist_item_checklist_item_detail_id_fkey FOREIGN KEY (checklist_item_detail_id) REFERENCES public.checklist_item_detail(id);


--
-- Name: checklist_item_detail checklist_item_detail_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item_detail
    ADD CONSTRAINT checklist_item_detail_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: checklist_item_detail checklist_item_detail_checklist_detail_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item_detail
    ADD CONSTRAINT checklist_item_detail_checklist_detail_id_fkey FOREIGN KEY (checklist_detail_id) REFERENCES public.checklist_detail(id);


--
-- Name: checklist_item_detail checklist_item_detail_concept_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item_detail
    ADD CONSTRAINT checklist_item_detail_concept_id_fkey FOREIGN KEY (concept_id) REFERENCES public.concept(id);


--
-- Name: checklist_item_detail checklist_item_detail_dependent_on_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item_detail
    ADD CONSTRAINT checklist_item_detail_dependent_on_fkey FOREIGN KEY (dependent_on) REFERENCES public.checklist_item_detail(id);


--
-- Name: checklist_item_detail checklist_item_detail_form_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item_detail
    ADD CONSTRAINT checklist_item_detail_form_id_fkey FOREIGN KEY (form_id) REFERENCES public.form(id);


--
-- Name: checklist_item_detail checklist_item_detail_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item_detail
    ADD CONSTRAINT checklist_item_detail_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: checklist_item checklist_item_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist_item
    ADD CONSTRAINT checklist_item_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: checklist checklist_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist
    ADD CONSTRAINT checklist_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: checklist checklist_program_enrolment; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.checklist
    ADD CONSTRAINT checklist_program_enrolment FOREIGN KEY (program_enrolment_id) REFERENCES public.program_enrolment(id);


--
-- Name: comment comment_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: comment comment_comment_thread_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_comment_thread_id_fkey FOREIGN KEY (comment_thread_id) REFERENCES public.comment_thread(id);


--
-- Name: comment comment_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: comment comment_subject_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.comment
    ADD CONSTRAINT comment_subject_id_fkey FOREIGN KEY (subject_id) REFERENCES public.individual(id);


--
-- Name: comment_thread comment_thread_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.comment_thread
    ADD CONSTRAINT comment_thread_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: comment_thread comment_thread_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.comment_thread
    ADD CONSTRAINT comment_thread_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: concept_answer concept_answer_answer_concept; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept_answer
    ADD CONSTRAINT concept_answer_answer_concept FOREIGN KEY (answer_concept_id) REFERENCES public.concept(id);


--
-- Name: concept_answer concept_answer_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept_answer
    ADD CONSTRAINT concept_answer_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: concept_answer concept_answer_concept; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept_answer
    ADD CONSTRAINT concept_answer_concept FOREIGN KEY (concept_id) REFERENCES public.concept(id);


--
-- Name: concept_answer concept_answer_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept_answer
    ADD CONSTRAINT concept_answer_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: concept concept_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept
    ADD CONSTRAINT concept_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: concept concept_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.concept
    ADD CONSTRAINT concept_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: dashboard_card_mapping dashboard_card_card; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_card_mapping
    ADD CONSTRAINT dashboard_card_card FOREIGN KEY (card_id) REFERENCES public.report_card(id);


--
-- Name: dashboard_card_mapping dashboard_card_dashboard; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_card_mapping
    ADD CONSTRAINT dashboard_card_dashboard FOREIGN KEY (dashboard_id) REFERENCES public.dashboard(id);


--
-- Name: dashboard_card_mapping dashboard_card_master_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_card_mapping
    ADD CONSTRAINT dashboard_card_master_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: dashboard_card_mapping dashboard_card_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_card_mapping
    ADD CONSTRAINT dashboard_card_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: dashboard dashboard_master_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard
    ADD CONSTRAINT dashboard_master_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: dashboard dashboard_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard
    ADD CONSTRAINT dashboard_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: dashboard_section dashboard_section_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section
    ADD CONSTRAINT dashboard_section_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: dashboard_section_card_mapping dashboard_section_card_mapping_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section_card_mapping
    ADD CONSTRAINT dashboard_section_card_mapping_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: dashboard_section_card_mapping dashboard_section_card_mapping_card; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section_card_mapping
    ADD CONSTRAINT dashboard_section_card_mapping_card FOREIGN KEY (card_id) REFERENCES public.report_card(id);


--
-- Name: dashboard_section_card_mapping dashboard_section_card_mapping_dashboard; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section_card_mapping
    ADD CONSTRAINT dashboard_section_card_mapping_dashboard FOREIGN KEY (dashboard_section_id) REFERENCES public.dashboard_section(id);


--
-- Name: dashboard_section_card_mapping dashboard_section_card_mapping_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section_card_mapping
    ADD CONSTRAINT dashboard_section_card_mapping_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: dashboard_section dashboard_section_dashboard; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section
    ADD CONSTRAINT dashboard_section_dashboard FOREIGN KEY (dashboard_id) REFERENCES public.dashboard(id);


--
-- Name: dashboard_section dashboard_section_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.dashboard_section
    ADD CONSTRAINT dashboard_section_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: decision_concept decision_concept_concept; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.decision_concept
    ADD CONSTRAINT decision_concept_concept FOREIGN KEY (concept_id) REFERENCES public.concept(id);


--
-- Name: decision_concept decision_concept_form; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.decision_concept
    ADD CONSTRAINT decision_concept_form FOREIGN KEY (form_id) REFERENCES public.form(id);


--
-- Name: encounter encounter_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter
    ADD CONSTRAINT encounter_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: encounter encounter_encounter_type; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter
    ADD CONSTRAINT encounter_encounter_type FOREIGN KEY (encounter_type_id) REFERENCES public.encounter_type(id);


--
-- Name: encounter encounter_individual; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter
    ADD CONSTRAINT encounter_individual FOREIGN KEY (individual_id) REFERENCES public.individual(id);


--
-- Name: encounter encounter_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter
    ADD CONSTRAINT encounter_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: encounter_type encounter_type_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter_type
    ADD CONSTRAINT encounter_type_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: encounter_type encounter_type_concept; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter_type
    ADD CONSTRAINT encounter_type_concept FOREIGN KEY (concept_id) REFERENCES public.concept(id);


--
-- Name: encounter_type encounter_type_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.encounter_type
    ADD CONSTRAINT encounter_type_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: entity_approval_status entity_approval_status_approval_status; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.entity_approval_status
    ADD CONSTRAINT entity_approval_status_approval_status FOREIGN KEY (approval_status_id) REFERENCES public.approval_status(id);


--
-- Name: entity_approval_status entity_approval_status_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.entity_approval_status
    ADD CONSTRAINT entity_approval_status_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: entity_approval_status entity_approval_status_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.entity_approval_status
    ADD CONSTRAINT entity_approval_status_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: facility facility_address; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.facility
    ADD CONSTRAINT facility_address FOREIGN KEY (address_id) REFERENCES public.address_level(id);


--
-- Name: form form_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form
    ADD CONSTRAINT form_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: form_element form_element_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element
    ADD CONSTRAINT form_element_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: form_element form_element_concept; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element
    ADD CONSTRAINT form_element_concept FOREIGN KEY (concept_id) REFERENCES public.concept(id);


--
-- Name: form_element form_element_form_element_group; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element
    ADD CONSTRAINT form_element_form_element_group FOREIGN KEY (form_element_group_id) REFERENCES public.form_element_group(id);


--
-- Name: form_element_group form_element_group_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element_group
    ADD CONSTRAINT form_element_group_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: form_element_group form_element_group_form; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element_group
    ADD CONSTRAINT form_element_group_form FOREIGN KEY (form_id) REFERENCES public.form(id);


--
-- Name: form_element_group form_element_group_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element_group
    ADD CONSTRAINT form_element_group_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: form_element form_element_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_element
    ADD CONSTRAINT form_element_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: form_mapping form_mapping_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_mapping
    ADD CONSTRAINT form_mapping_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: form_mapping form_mapping_form; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_mapping
    ADD CONSTRAINT form_mapping_form FOREIGN KEY (form_id) REFERENCES public.form(id);


--
-- Name: form_mapping form_mapping_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_mapping
    ADD CONSTRAINT form_mapping_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: form_mapping form_mapping_subject_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form_mapping
    ADD CONSTRAINT form_mapping_subject_type_id_fkey FOREIGN KEY (subject_type_id) REFERENCES public.subject_type(id);


--
-- Name: form form_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.form
    ADD CONSTRAINT form_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: gender gender_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.gender
    ADD CONSTRAINT gender_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: gender gender_concept; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.gender
    ADD CONSTRAINT gender_concept FOREIGN KEY (concept_id) REFERENCES public.concept(id);


--
-- Name: gender gender_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.gender
    ADD CONSTRAINT gender_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: group_dashboard group_dashboard_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_dashboard
    ADD CONSTRAINT group_dashboard_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: group_dashboard group_dashboard_dashboard; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_dashboard
    ADD CONSTRAINT group_dashboard_dashboard FOREIGN KEY (dashboard_id) REFERENCES public.dashboard(id);


--
-- Name: group_dashboard group_dashboard_group; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_dashboard
    ADD CONSTRAINT group_dashboard_group FOREIGN KEY (group_id) REFERENCES public.groups(id);


--
-- Name: group_dashboard group_dashboard_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_dashboard
    ADD CONSTRAINT group_dashboard_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: groups group_master_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT group_master_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: groups group_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.groups
    ADD CONSTRAINT group_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: group_privilege group_privilege_checklist_detail_id; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_privilege
    ADD CONSTRAINT group_privilege_checklist_detail_id FOREIGN KEY (checklist_detail_id) REFERENCES public.checklist_detail(id);


--
-- Name: group_privilege group_privilege_encounter_type_id; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_privilege
    ADD CONSTRAINT group_privilege_encounter_type_id FOREIGN KEY (encounter_type_id) REFERENCES public.encounter_type(id);


--
-- Name: group_privilege group_privilege_group_id; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_privilege
    ADD CONSTRAINT group_privilege_group_id FOREIGN KEY (group_id) REFERENCES public.groups(id);


--
-- Name: group_privilege group_privilege_master_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_privilege
    ADD CONSTRAINT group_privilege_master_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: group_privilege group_privilege_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_privilege
    ADD CONSTRAINT group_privilege_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: group_privilege group_privilege_program_encounter_type_id; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_privilege
    ADD CONSTRAINT group_privilege_program_encounter_type_id FOREIGN KEY (program_encounter_type_id) REFERENCES public.encounter_type(id);


--
-- Name: group_privilege group_privilege_program_id; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_privilege
    ADD CONSTRAINT group_privilege_program_id FOREIGN KEY (program_id) REFERENCES public.program(id);


--
-- Name: group_privilege group_privilege_subject_id; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_privilege
    ADD CONSTRAINT group_privilege_subject_id FOREIGN KEY (subject_type_id) REFERENCES public.subject_type(id);


--
-- Name: group_role group_role_group_subject_type; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_role
    ADD CONSTRAINT group_role_group_subject_type FOREIGN KEY (group_subject_type_id) REFERENCES public.subject_type(id);


--
-- Name: group_role group_role_master_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_role
    ADD CONSTRAINT group_role_master_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: group_role group_role_member_subject_type; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_role
    ADD CONSTRAINT group_role_member_subject_type FOREIGN KEY (member_subject_type_id) REFERENCES public.subject_type(id);


--
-- Name: group_role group_role_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_role
    ADD CONSTRAINT group_role_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: group_subject group_subject_group_role; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_subject
    ADD CONSTRAINT group_subject_group_role FOREIGN KEY (group_role_id) REFERENCES public.group_role(id);


--
-- Name: group_subject group_subject_group_subject; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_subject
    ADD CONSTRAINT group_subject_group_subject FOREIGN KEY (group_subject_id) REFERENCES public.individual(id);


--
-- Name: group_subject group_subject_master_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_subject
    ADD CONSTRAINT group_subject_master_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: group_subject group_subject_member_subject; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_subject
    ADD CONSTRAINT group_subject_member_subject FOREIGN KEY (member_subject_id) REFERENCES public.individual(id);


--
-- Name: group_subject group_subject_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.group_subject
    ADD CONSTRAINT group_subject_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: identifier_assignment identifier_assignment_assigned_to_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_assignment
    ADD CONSTRAINT identifier_assignment_assigned_to_user_id_fkey FOREIGN KEY (assigned_to_user_id) REFERENCES public.users(id);


--
-- Name: identifier_assignment identifier_assignment_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_assignment
    ADD CONSTRAINT identifier_assignment_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: identifier_assignment identifier_assignment_identifier_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_assignment
    ADD CONSTRAINT identifier_assignment_identifier_source_id_fkey FOREIGN KEY (identifier_source_id) REFERENCES public.identifier_source(id);


--
-- Name: identifier_assignment identifier_assignment_individual_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_assignment
    ADD CONSTRAINT identifier_assignment_individual_id_fkey FOREIGN KEY (individual_id) REFERENCES public.individual(id);


--
-- Name: identifier_assignment identifier_assignment_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_assignment
    ADD CONSTRAINT identifier_assignment_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: identifier_assignment identifier_assignment_program_enrolment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_assignment
    ADD CONSTRAINT identifier_assignment_program_enrolment_id_fkey FOREIGN KEY (program_enrolment_id) REFERENCES public.program_enrolment(id);


--
-- Name: identifier_source identifier_source_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_source
    ADD CONSTRAINT identifier_source_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: identifier_source identifier_source_catchment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_source
    ADD CONSTRAINT identifier_source_catchment_id_fkey FOREIGN KEY (catchment_id) REFERENCES public.catchment(id);


--
-- Name: identifier_source identifier_source_facility_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_source
    ADD CONSTRAINT identifier_source_facility_id_fkey FOREIGN KEY (facility_id) REFERENCES public.facility(id);


--
-- Name: identifier_source identifier_source_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_source
    ADD CONSTRAINT identifier_source_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: identifier_user_assignment identifier_user_assignment_assigned_to_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_user_assignment
    ADD CONSTRAINT identifier_user_assignment_assigned_to_user_id_fkey FOREIGN KEY (assigned_to_user_id) REFERENCES public.users(id);


--
-- Name: identifier_user_assignment identifier_user_assignment_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_user_assignment
    ADD CONSTRAINT identifier_user_assignment_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: identifier_user_assignment identifier_user_assignment_identifier_source_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_user_assignment
    ADD CONSTRAINT identifier_user_assignment_identifier_source_id_fkey FOREIGN KEY (identifier_source_id) REFERENCES public.identifier_source(id);


--
-- Name: identifier_user_assignment identifier_user_assignment_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.identifier_user_assignment
    ADD CONSTRAINT identifier_user_assignment_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: individual individual_address; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual
    ADD CONSTRAINT individual_address FOREIGN KEY (address_id) REFERENCES public.address_level(id);


--
-- Name: individual individual_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual
    ADD CONSTRAINT individual_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: individual individual_facility; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual
    ADD CONSTRAINT individual_facility FOREIGN KEY (facility_id) REFERENCES public.facility(id);


--
-- Name: individual individual_gender; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual
    ADD CONSTRAINT individual_gender FOREIGN KEY (gender_id) REFERENCES public.gender(id);


--
-- Name: individual individual_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual
    ADD CONSTRAINT individual_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: individual_relative individual_relation_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relative
    ADD CONSTRAINT individual_relation_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: individual_relation individual_relation_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relation
    ADD CONSTRAINT individual_relation_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: individual_relation_gender_mapping individual_relation_gender_mapping_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relation_gender_mapping
    ADD CONSTRAINT individual_relation_gender_mapping_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: individual_relation_gender_mapping individual_relation_gender_mapping_gender; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relation_gender_mapping
    ADD CONSTRAINT individual_relation_gender_mapping_gender FOREIGN KEY (gender_id) REFERENCES public.gender(id);


--
-- Name: individual_relation_gender_mapping individual_relation_gender_mapping_relation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relation_gender_mapping
    ADD CONSTRAINT individual_relation_gender_mapping_relation FOREIGN KEY (relation_id) REFERENCES public.individual_relation(id);


--
-- Name: individual_relationship individual_relationship_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relationship
    ADD CONSTRAINT individual_relationship_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: individual_relationship individual_relationship_individual_a; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relationship
    ADD CONSTRAINT individual_relationship_individual_a FOREIGN KEY (individual_a_id) REFERENCES public.individual(id);


--
-- Name: individual_relationship individual_relationship_individual_b; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relationship
    ADD CONSTRAINT individual_relationship_individual_b FOREIGN KEY (individual_b_id) REFERENCES public.individual(id);


--
-- Name: individual_relationship individual_relationship_relation_type; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relationship
    ADD CONSTRAINT individual_relationship_relation_type FOREIGN KEY (relationship_type_id) REFERENCES public.individual_relationship_type(id);


--
-- Name: individual_relationship_type individual_relationship_type_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relationship_type
    ADD CONSTRAINT individual_relationship_type_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: individual_relationship_type individual_relationship_type_individual_a_relation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relationship_type
    ADD CONSTRAINT individual_relationship_type_individual_a_relation FOREIGN KEY (individual_a_is_to_b_relation_id) REFERENCES public.individual_relation(id);


--
-- Name: individual_relationship_type individual_relationship_type_individual_b_relation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relationship_type
    ADD CONSTRAINT individual_relationship_type_individual_b_relation FOREIGN KEY (individual_b_is_to_a_relation_id) REFERENCES public.individual_relation(id);


--
-- Name: individual_relative individual_relative_individual; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relative
    ADD CONSTRAINT individual_relative_individual FOREIGN KEY (individual_id) REFERENCES public.individual(id);


--
-- Name: individual_relative individual_relative_relative_individual; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual_relative
    ADD CONSTRAINT individual_relative_relative_individual FOREIGN KEY (relative_individual_id) REFERENCES public.individual(id);


--
-- Name: individual individual_subject_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.individual
    ADD CONSTRAINT individual_subject_type_id_fkey FOREIGN KEY (subject_type_id) REFERENCES public.subject_type(id);


--
-- Name: batch_job_execution_context job_exec_ctx_fk; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.batch_job_execution_context
    ADD CONSTRAINT job_exec_ctx_fk FOREIGN KEY (job_execution_id) REFERENCES public.batch_job_execution(job_execution_id);


--
-- Name: batch_job_execution_params job_exec_params_fk; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.batch_job_execution_params
    ADD CONSTRAINT job_exec_params_fk FOREIGN KEY (job_execution_id) REFERENCES public.batch_job_execution(job_execution_id);


--
-- Name: batch_step_execution job_exec_step_fk; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.batch_step_execution
    ADD CONSTRAINT job_exec_step_fk FOREIGN KEY (job_execution_id) REFERENCES public.batch_job_execution(job_execution_id);


--
-- Name: batch_job_execution job_inst_exec_fk; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.batch_job_execution
    ADD CONSTRAINT job_inst_exec_fk FOREIGN KEY (job_instance_id) REFERENCES public.batch_job_instance(job_instance_id);


--
-- Name: location_location_mapping location_location_mapping_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.location_location_mapping
    ADD CONSTRAINT location_location_mapping_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: location_location_mapping location_location_mapping_location; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.location_location_mapping
    ADD CONSTRAINT location_location_mapping_location FOREIGN KEY (location_id) REFERENCES public.address_level(id);


--
-- Name: location_location_mapping location_location_mapping_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.location_location_mapping
    ADD CONSTRAINT location_location_mapping_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: location_location_mapping location_location_mapping_parent_location; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.location_location_mapping
    ADD CONSTRAINT location_location_mapping_parent_location FOREIGN KEY (parent_location_id) REFERENCES public.address_level(id);


--
-- Name: msg91_config msg91_config_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.msg91_config
    ADD CONSTRAINT msg91_config_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: msg91_config msg91_config_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.msg91_config
    ADD CONSTRAINT msg91_config_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: news news_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.news
    ADD CONSTRAINT news_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: news news_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.news
    ADD CONSTRAINT news_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: non_applicable_form_element non_applicable_form_element_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.non_applicable_form_element
    ADD CONSTRAINT non_applicable_form_element_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: non_applicable_form_element non_applicable_form_element_form_element_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.non_applicable_form_element
    ADD CONSTRAINT non_applicable_form_element_form_element_id_fkey FOREIGN KEY (form_element_id) REFERENCES public.form_element(id);


--
-- Name: non_applicable_form_element non_applicable_form_element_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.non_applicable_form_element
    ADD CONSTRAINT non_applicable_form_element_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: operational_encounter_type operational_encounter_type_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_encounter_type
    ADD CONSTRAINT operational_encounter_type_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: operational_encounter_type operational_encounter_type_encounter_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_encounter_type
    ADD CONSTRAINT operational_encounter_type_encounter_type_id_fkey FOREIGN KEY (encounter_type_id) REFERENCES public.encounter_type(id);


--
-- Name: operational_encounter_type operational_encounter_type_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_encounter_type
    ADD CONSTRAINT operational_encounter_type_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: operational_program operational_program_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_program
    ADD CONSTRAINT operational_program_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: operational_program operational_program_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_program
    ADD CONSTRAINT operational_program_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: operational_program operational_program_program_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_program
    ADD CONSTRAINT operational_program_program_id_fkey FOREIGN KEY (program_id) REFERENCES public.program(id);


--
-- Name: operational_subject_type operational_subject_type_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_subject_type
    ADD CONSTRAINT operational_subject_type_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: operational_subject_type operational_subject_type_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_subject_type
    ADD CONSTRAINT operational_subject_type_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: operational_subject_type operational_subject_type_subject_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.operational_subject_type
    ADD CONSTRAINT operational_subject_type_subject_type_id_fkey FOREIGN KEY (subject_type_id) REFERENCES public.subject_type(id);


--
-- Name: organisation organisation_account; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation
    ADD CONSTRAINT organisation_account FOREIGN KEY (account_id) REFERENCES public.account(id);


--
-- Name: organisation_config organisation_config_master_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_config
    ADD CONSTRAINT organisation_config_master_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: organisation_config organisation_config_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_config
    ADD CONSTRAINT organisation_config_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: organisation_group organisation_group_account; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_group
    ADD CONSTRAINT organisation_group_account FOREIGN KEY (account_id) REFERENCES public.account(id);


--
-- Name: organisation_group_organisation organisation_group_organisation_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_group_organisation
    ADD CONSTRAINT organisation_group_organisation_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: organisation_group_organisation organisation_group_organisation_organisation_group; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation_group_organisation
    ADD CONSTRAINT organisation_group_organisation_organisation_group FOREIGN KEY (organisation_group_id) REFERENCES public.organisation_group(id);


--
-- Name: organisation organisation_parent_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.organisation
    ADD CONSTRAINT organisation_parent_organisation_id_fkey FOREIGN KEY (parent_organisation_id) REFERENCES public.organisation(id);


--
-- Name: platform_translation platform_translation_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.platform_translation
    ADD CONSTRAINT platform_translation_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: program program_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program
    ADD CONSTRAINT program_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: program_encounter program_encounter_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_encounter
    ADD CONSTRAINT program_encounter_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: program_encounter program_encounter_encounter_type; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_encounter
    ADD CONSTRAINT program_encounter_encounter_type FOREIGN KEY (encounter_type_id) REFERENCES public.encounter_type(id);


--
-- Name: program_encounter program_encounter_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_encounter
    ADD CONSTRAINT program_encounter_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: program_encounter program_encounter_program_enrolment; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_encounter
    ADD CONSTRAINT program_encounter_program_enrolment FOREIGN KEY (program_enrolment_id) REFERENCES public.program_enrolment(id);


--
-- Name: program_enrolment program_enrolment_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_enrolment
    ADD CONSTRAINT program_enrolment_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: program_enrolment program_enrolment_individual; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_enrolment
    ADD CONSTRAINT program_enrolment_individual FOREIGN KEY (individual_id) REFERENCES public.individual(id);


--
-- Name: program_enrolment program_enrolment_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_enrolment
    ADD CONSTRAINT program_enrolment_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: program_enrolment program_enrolment_program; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_enrolment
    ADD CONSTRAINT program_enrolment_program FOREIGN KEY (program_id) REFERENCES public.program(id);


--
-- Name: program_enrolment program_enrolment_program_outcome; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_enrolment
    ADD CONSTRAINT program_enrolment_program_outcome FOREIGN KEY (program_outcome_id) REFERENCES public.program_outcome(id);


--
-- Name: program_organisation_config_at_risk_concept program_organisation_config_a_program_organisation_config__fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_organisation_config_at_risk_concept
    ADD CONSTRAINT program_organisation_config_a_program_organisation_config__fkey FOREIGN KEY (program_organisation_config_id) REFERENCES public.program_organisation_config(id);


--
-- Name: program_organisation_config_at_risk_concept program_organisation_config_at_risk_concept_concept_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_organisation_config_at_risk_concept
    ADD CONSTRAINT program_organisation_config_at_risk_concept_concept_id_fkey FOREIGN KEY (concept_id) REFERENCES public.concept(id);


--
-- Name: program_organisation_config program_organisation_config_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_organisation_config
    ADD CONSTRAINT program_organisation_config_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: program_organisation_config program_organisation_config_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_organisation_config
    ADD CONSTRAINT program_organisation_config_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: program_organisation_config program_organisation_config_program_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_organisation_config
    ADD CONSTRAINT program_organisation_config_program_id_fkey FOREIGN KEY (program_id) REFERENCES public.program(id);


--
-- Name: program program_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program
    ADD CONSTRAINT program_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: program_outcome program_outcome_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_outcome
    ADD CONSTRAINT program_outcome_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: program_outcome program_outcome_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.program_outcome
    ADD CONSTRAINT program_outcome_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: report_card report_card_standard_report_card_type; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.report_card
    ADD CONSTRAINT report_card_standard_report_card_type FOREIGN KEY (standard_report_card_type_id) REFERENCES public.standard_report_card_type(id);


--
-- Name: rule rule_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule
    ADD CONSTRAINT rule_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: rule_dependency rule_dependency_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule_dependency
    ADD CONSTRAINT rule_dependency_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: rule_failure_telemetry rule_failure_telemetry_master_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule_failure_telemetry
    ADD CONSTRAINT rule_failure_telemetry_master_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: rule_failure_telemetry rule_failure_telemetry_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule_failure_telemetry
    ADD CONSTRAINT rule_failure_telemetry_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: rule_failure_telemetry rule_failure_telemetry_user; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule_failure_telemetry
    ADD CONSTRAINT rule_failure_telemetry_user FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: rule rule_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule
    ADD CONSTRAINT rule_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: rule rule_rule_dependency_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.rule
    ADD CONSTRAINT rule_rule_dependency_id_fkey FOREIGN KEY (rule_dependency_id) REFERENCES public.rule_dependency(id);


--
-- Name: batch_step_execution_context step_exec_ctx_fk; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.batch_step_execution_context
    ADD CONSTRAINT step_exec_ctx_fk FOREIGN KEY (step_execution_id) REFERENCES public.batch_step_execution(step_execution_id);


--
-- Name: subject_migration subject_migration_audit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.subject_migration
    ADD CONSTRAINT subject_migration_audit_id_fkey FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: subject_migration subject_migration_individual_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.subject_migration
    ADD CONSTRAINT subject_migration_individual_id_fkey FOREIGN KEY (individual_id) REFERENCES public.individual(id);


--
-- Name: subject_migration subject_migration_new_address_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.subject_migration
    ADD CONSTRAINT subject_migration_new_address_level_id_fkey FOREIGN KEY (new_address_level_id) REFERENCES public.address_level(id);


--
-- Name: subject_migration subject_migration_old_address_level_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.subject_migration
    ADD CONSTRAINT subject_migration_old_address_level_id_fkey FOREIGN KEY (old_address_level_id) REFERENCES public.address_level(id);


--
-- Name: subject_type subject_type_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.subject_type
    ADD CONSTRAINT subject_type_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: subject_type subject_type_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.subject_type
    ADD CONSTRAINT subject_type_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: sync_telemetry sync_telemetry_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.sync_telemetry
    ADD CONSTRAINT sync_telemetry_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: sync_telemetry sync_telemetry_user; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.sync_telemetry
    ADD CONSTRAINT sync_telemetry_user FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: translation translation_master_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.translation
    ADD CONSTRAINT translation_master_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: translation translation_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.translation
    ADD CONSTRAINT translation_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: user_facility_mapping user_facility_mapping_facility; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.user_facility_mapping
    ADD CONSTRAINT user_facility_mapping_facility FOREIGN KEY (facility_id) REFERENCES public.facility(id);


--
-- Name: user_facility_mapping user_facility_mapping_user; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.user_facility_mapping
    ADD CONSTRAINT user_facility_mapping_user FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: user_group user_group_group_id; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.user_group
    ADD CONSTRAINT user_group_group_id FOREIGN KEY (group_id) REFERENCES public.groups(id);


--
-- Name: user_group user_group_master_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.user_group
    ADD CONSTRAINT user_group_master_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: user_group user_group_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.user_group
    ADD CONSTRAINT user_group_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: user_group user_group_user_id; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.user_group
    ADD CONSTRAINT user_group_user_id FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: users users_organisation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_organisation_id_fkey FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: video video_audit; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.video
    ADD CONSTRAINT video_audit FOREIGN KEY (audit_id) REFERENCES public.audit(id);


--
-- Name: video video_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.video
    ADD CONSTRAINT video_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: video_telemetric video_telemetric_organisation; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.video_telemetric
    ADD CONSTRAINT video_telemetric_organisation FOREIGN KEY (organisation_id) REFERENCES public.organisation(id);


--
-- Name: video_telemetric video_telemetric_user; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.video_telemetric
    ADD CONSTRAINT video_telemetric_user FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: video_telemetric video_telemetric_video; Type: FK CONSTRAINT; Schema: public; Owner: openchs
--

ALTER TABLE ONLY public.video_telemetric
    ADD CONSTRAINT video_telemetric_video FOREIGN KEY (video_id) REFERENCES public.video(id);


--
-- Name: address_level; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.address_level ENABLE ROW LEVEL SECURITY;

--
-- Name: address_level address_level_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY address_level_orgs ON public.address_level USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: address_level_type; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.address_level_type ENABLE ROW LEVEL SECURITY;

--
-- Name: address_level_type address_level_type_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY address_level_type_orgs ON public.address_level_type USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: report_card card_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY card_orgs ON public.report_card USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: catchment; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.catchment ENABLE ROW LEVEL SECURITY;

--
-- Name: catchment catchment_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY catchment_orgs ON public.catchment USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: checklist; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.checklist ENABLE ROW LEVEL SECURITY;

--
-- Name: checklist_detail; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.checklist_detail ENABLE ROW LEVEL SECURITY;

--
-- Name: checklist_detail checklist_detail_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY checklist_detail_orgs ON public.checklist_detail USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: checklist_item; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.checklist_item ENABLE ROW LEVEL SECURITY;

--
-- Name: checklist_item_detail; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.checklist_item_detail ENABLE ROW LEVEL SECURITY;

--
-- Name: checklist_item_detail checklist_item_detail_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY checklist_item_detail_orgs ON public.checklist_item_detail USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: checklist_item checklist_item_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY checklist_item_orgs ON public.checklist_item USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: checklist checklist_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY checklist_orgs ON public.checklist USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: comment; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.comment ENABLE ROW LEVEL SECURITY;

--
-- Name: comment comment_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY comment_orgs ON public.comment USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: comment_thread; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.comment_thread ENABLE ROW LEVEL SECURITY;

--
-- Name: comment_thread comment_thread_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY comment_thread_orgs ON public.comment_thread USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: concept; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.concept ENABLE ROW LEVEL SECURITY;

--
-- Name: concept_answer; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.concept_answer ENABLE ROW LEVEL SECURITY;

--
-- Name: concept_answer concept_answer_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY concept_answer_orgs ON public.concept_answer USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: concept concept_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY concept_orgs ON public.concept USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: dashboard; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.dashboard ENABLE ROW LEVEL SECURITY;

--
-- Name: dashboard_card_mapping; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.dashboard_card_mapping ENABLE ROW LEVEL SECURITY;

--
-- Name: dashboard_card_mapping dashboard_card_mapping_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY dashboard_card_mapping_orgs ON public.dashboard_card_mapping USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: dashboard dashboard_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY dashboard_orgs ON public.dashboard USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: dashboard_section; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.dashboard_section ENABLE ROW LEVEL SECURITY;

--
-- Name: dashboard_section_card_mapping; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.dashboard_section_card_mapping ENABLE ROW LEVEL SECURITY;

--
-- Name: dashboard_section_card_mapping dashboard_section_card_mapping_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY dashboard_section_card_mapping_orgs ON public.dashboard_section_card_mapping USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: dashboard_section dashboard_section_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY dashboard_section_orgs ON public.dashboard_section USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: encounter; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.encounter ENABLE ROW LEVEL SECURITY;

--
-- Name: encounter encounter_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY encounter_orgs ON public.encounter USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: encounter_type; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.encounter_type ENABLE ROW LEVEL SECURITY;

--
-- Name: encounter_type encounter_type_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY encounter_type_orgs ON public.encounter_type USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: entity_approval_status; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.entity_approval_status ENABLE ROW LEVEL SECURITY;

--
-- Name: entity_approval_status entity_approval_status_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY entity_approval_status_orgs ON public.entity_approval_status USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: facility; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.facility ENABLE ROW LEVEL SECURITY;

--
-- Name: facility facility_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY facility_orgs ON public.facility USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: form; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.form ENABLE ROW LEVEL SECURITY;

--
-- Name: form_element; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.form_element ENABLE ROW LEVEL SECURITY;

--
-- Name: form_element_group; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.form_element_group ENABLE ROW LEVEL SECURITY;

--
-- Name: form_element_group form_element_group_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY form_element_group_orgs ON public.form_element_group USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: form_element form_element_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY form_element_orgs ON public.form_element USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: form_mapping; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.form_mapping ENABLE ROW LEVEL SECURITY;

--
-- Name: form_mapping form_mapping_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY form_mapping_orgs ON public.form_mapping USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: form form_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY form_orgs ON public.form USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: gender; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.gender ENABLE ROW LEVEL SECURITY;

--
-- Name: gender gender_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY gender_orgs ON public.gender USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: group_dashboard; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.group_dashboard ENABLE ROW LEVEL SECURITY;

--
-- Name: group_dashboard group_dashboard_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY group_dashboard_orgs ON public.group_dashboard USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: group_privilege; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.group_privilege ENABLE ROW LEVEL SECURITY;

--
-- Name: group_privilege group_privilege_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY group_privilege_orgs ON public.group_privilege USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: group_role; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.group_role ENABLE ROW LEVEL SECURITY;

--
-- Name: group_role group_role_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY group_role_orgs ON public.group_role USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: group_subject; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.group_subject ENABLE ROW LEVEL SECURITY;

--
-- Name: group_subject group_subject_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY group_subject_orgs ON public.group_subject USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: groups; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

--
-- Name: groups groups_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY groups_orgs ON public.groups USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: identifier_assignment; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.identifier_assignment ENABLE ROW LEVEL SECURITY;

--
-- Name: identifier_assignment identifier_assignment_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY identifier_assignment_orgs ON public.identifier_assignment USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: identifier_source; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.identifier_source ENABLE ROW LEVEL SECURITY;

--
-- Name: identifier_source identifier_source_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY identifier_source_orgs ON public.identifier_source USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: identifier_user_assignment; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.identifier_user_assignment ENABLE ROW LEVEL SECURITY;

--
-- Name: identifier_user_assignment identifier_user_assignment_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY identifier_user_assignment_orgs ON public.identifier_user_assignment USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: individual; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.individual ENABLE ROW LEVEL SECURITY;

--
-- Name: individual individual_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY individual_orgs ON public.individual USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: individual_relation; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.individual_relation ENABLE ROW LEVEL SECURITY;

--
-- Name: individual_relation_gender_mapping; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.individual_relation_gender_mapping ENABLE ROW LEVEL SECURITY;

--
-- Name: individual_relation_gender_mapping individual_relation_gender_mapping_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY individual_relation_gender_mapping_orgs ON public.individual_relation_gender_mapping USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: individual_relation individual_relation_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY individual_relation_orgs ON public.individual_relation USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: individual_relationship; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.individual_relationship ENABLE ROW LEVEL SECURITY;

--
-- Name: individual_relationship individual_relationship_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY individual_relationship_orgs ON public.individual_relationship USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: individual_relationship_type; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.individual_relationship_type ENABLE ROW LEVEL SECURITY;

--
-- Name: individual_relationship_type individual_relationship_type_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY individual_relationship_type_orgs ON public.individual_relationship_type USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: location_location_mapping; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.location_location_mapping ENABLE ROW LEVEL SECURITY;

--
-- Name: location_location_mapping location_location_mapping_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY location_location_mapping_orgs ON public.location_location_mapping USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: msg91_config; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.msg91_config ENABLE ROW LEVEL SECURITY;

--
-- Name: msg91_config msg91_config_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY msg91_config_orgs ON public.msg91_config USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: news; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.news ENABLE ROW LEVEL SECURITY;

--
-- Name: news news_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY news_orgs ON public.news USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: non_applicable_form_element; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.non_applicable_form_element ENABLE ROW LEVEL SECURITY;

--
-- Name: non_applicable_form_element non_applicable_form_element_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY non_applicable_form_element_orgs ON public.non_applicable_form_element USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: operational_encounter_type; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.operational_encounter_type ENABLE ROW LEVEL SECURITY;

--
-- Name: operational_encounter_type operational_encounter_type_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY operational_encounter_type_orgs ON public.operational_encounter_type USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: operational_program; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.operational_program ENABLE ROW LEVEL SECURITY;

--
-- Name: operational_program operational_program_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY operational_program_orgs ON public.operational_program USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: operational_subject_type; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.operational_subject_type ENABLE ROW LEVEL SECURITY;

--
-- Name: operational_subject_type operational_subject_type_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY operational_subject_type_orgs ON public.operational_subject_type USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: organisation; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.organisation ENABLE ROW LEVEL SECURITY;

--
-- Name: organisation_config; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.organisation_config ENABLE ROW LEVEL SECURITY;

--
-- Name: organisation_config organisation_config_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY organisation_config_orgs ON public.organisation_config USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: organisation_group; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.organisation_group ENABLE ROW LEVEL SECURITY;

--
-- Name: organisation_group_organisation; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.organisation_group_organisation ENABLE ROW LEVEL SECURITY;

--
-- Name: organisation_group_organisation organisation_group_organisation_policy; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY organisation_group_organisation_policy ON public.organisation_group_organisation USING ((organisation_group_id IN ( SELECT organisation_group.id
   FROM public.organisation_group
  WHERE ((organisation_group.db_user)::name = CURRENT_USER))));


--
-- Name: organisation_group organisation_group_policy; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY organisation_group_policy ON public.organisation_group USING ((CURRENT_USER = (db_user)::name));


--
-- Name: organisation organisation_policy; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY organisation_policy ON public.organisation USING (((CURRENT_USER = ANY (ARRAY['openchs'::name, 'openchs_impl'::name])) OR (id IN ( SELECT org_ids.id
   FROM public.org_ids)) OR (id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation))));


--
-- Name: program; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.program ENABLE ROW LEVEL SECURITY;

--
-- Name: program_encounter; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.program_encounter ENABLE ROW LEVEL SECURITY;

--
-- Name: program_encounter program_encounter_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY program_encounter_orgs ON public.program_encounter USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: program_enrolment; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.program_enrolment ENABLE ROW LEVEL SECURITY;

--
-- Name: program_enrolment program_enrolment_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY program_enrolment_orgs ON public.program_enrolment USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: program_organisation_config; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.program_organisation_config ENABLE ROW LEVEL SECURITY;

--
-- Name: program_organisation_config program_organisation_config_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY program_organisation_config_orgs ON public.program_organisation_config USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: program program_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY program_orgs ON public.program USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: program_outcome; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.program_outcome ENABLE ROW LEVEL SECURITY;

--
-- Name: program_outcome program_outcome_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY program_outcome_orgs ON public.program_outcome USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: report_card; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.report_card ENABLE ROW LEVEL SECURITY;

--
-- Name: rule; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.rule ENABLE ROW LEVEL SECURITY;

--
-- Name: rule_dependency; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.rule_dependency ENABLE ROW LEVEL SECURITY;

--
-- Name: rule_dependency rule_dependency_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY rule_dependency_orgs ON public.rule_dependency USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: rule_failure_telemetry; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.rule_failure_telemetry ENABLE ROW LEVEL SECURITY;

--
-- Name: rule_failure_telemetry rule_failure_telemetry_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY rule_failure_telemetry_orgs ON public.rule_failure_telemetry USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: rule rule_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY rule_orgs ON public.rule USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: subject_migration; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.subject_migration ENABLE ROW LEVEL SECURITY;

--
-- Name: subject_migration subject_migration_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY subject_migration_orgs ON public.subject_migration USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: subject_type; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.subject_type ENABLE ROW LEVEL SECURITY;

--
-- Name: subject_type subject_type_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY subject_type_orgs ON public.subject_type USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: sync_telemetry; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.sync_telemetry ENABLE ROW LEVEL SECURITY;

--
-- Name: sync_telemetry sync_telemetry_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY sync_telemetry_orgs ON public.sync_telemetry USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: translation; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.translation ENABLE ROW LEVEL SECURITY;

--
-- Name: translation translation_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY translation_orgs ON public.translation USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: user_facility_mapping; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.user_facility_mapping ENABLE ROW LEVEL SECURITY;

--
-- Name: user_facility_mapping user_facility_mapping_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY user_facility_mapping_orgs ON public.user_facility_mapping USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: user_group; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.user_group ENABLE ROW LEVEL SECURITY;

--
-- Name: user_group user_group_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY user_group_orgs ON public.user_group USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: users users_policy; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY users_policy ON public.users USING ((organisation_id IN ( WITH RECURSIVE children(id, parent_organisation_id) AS (
         SELECT organisation.id,
            organisation.parent_organisation_id
           FROM public.organisation
          WHERE ((organisation.db_user)::name = CURRENT_USER)
        UNION ALL
         SELECT grand_children.id,
            grand_children.parent_organisation_id
           FROM public.organisation grand_children,
            children
          WHERE (grand_children.parent_organisation_id = children.id)
        )
(
         SELECT children.id
           FROM children
        UNION
        ( WITH RECURSIVE parents(id, parent_organisation_id) AS (
                 SELECT organisation.id,
                    organisation.parent_organisation_id
                   FROM public.organisation
                  WHERE ((organisation.db_user)::name = CURRENT_USER)
                UNION ALL
                 SELECT grand_parents.id,
                    grand_parents.parent_organisation_id
                   FROM public.organisation grand_parents,
                    parents parents_1
                  WHERE (grand_parents.id = parents_1.parent_organisation_id)
                )
         SELECT parents.id
           FROM parents)
) UNION ALL
 SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.parent_organisation_id IS NULL) AND (CURRENT_USER = 'openchs_impl'::name))))) WITH CHECK ((organisation_id IN ( WITH RECURSIVE children(id, parent_organisation_id) AS (
         SELECT organisation.id,
            organisation.parent_organisation_id
           FROM public.organisation
          WHERE ((organisation.db_user)::name = CURRENT_USER)
        UNION ALL
         SELECT grand_children.id,
            grand_children.parent_organisation_id
           FROM public.organisation grand_children,
            children
          WHERE (grand_children.parent_organisation_id = children.id)
        )
 SELECT children.id
   FROM children
UNION ALL
 SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.parent_organisation_id IS NULL) AND (CURRENT_USER = 'openchs_impl'::name)))));


--
-- Name: users users_user; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY users_user ON public.users USING (((organisation_id IN ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = ANY (ARRAY['openchs'::name, CURRENT_USER])))) OR (id IN ( SELECT account_admin.admin_id
   FROM public.account_admin
  WHERE (account_admin.account_id IN ( SELECT organisation.account_id
           FROM public.organisation
          WHERE ((organisation.db_user)::name = ANY (ARRAY['openchs'::name, CURRENT_USER])))))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id IN ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = ANY (ARRAY['openchs'::name, CURRENT_USER])))));


--
-- Name: video; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.video ENABLE ROW LEVEL SECURITY;

--
-- Name: video video_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY video_orgs ON public.video USING (((organisation_id IN ( SELECT org_ids.id
   FROM public.org_ids
UNION
 SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));


--
-- Name: video_telemetric; Type: ROW SECURITY; Schema: public; Owner: openchs
--

ALTER TABLE public.video_telemetric ENABLE ROW LEVEL SECURITY;

--
-- Name: video_telemetric video_telemetric_orgs; Type: POLICY; Schema: public; Owner: openchs
--

CREATE POLICY video_telemetric_orgs ON public.video_telemetric USING (((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))) OR (organisation_id IN ( SELECT organisation_group_organisation.organisation_id
   FROM public.organisation_group_organisation)))) WITH CHECK ((organisation_id = ( SELECT organisation.id
   FROM public.organisation
  WHERE ((organisation.db_user)::name = CURRENT_USER))));

--
-- PostgreSQL database dump complete
--

select public.create_db_user('test'::text, 'password'::text);
