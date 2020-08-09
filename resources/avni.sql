create extension if not exists "uuid-ossp";
create extension if not exists "ltree";
create role demo with NOINHERIT NOLOGIN;
grant demo to openchs;
create role openchs_impl;
grant openchs_impl to openchs;
create role organisation_user createrole admin openchs_impl;
