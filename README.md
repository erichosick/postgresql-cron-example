# Postgresql: Caching with pg_cron and Materialized Views

## Introduction

[Materialized views](https://www.postgresql.org/docs/14/rules-materializedviews.html) can be used to cache the results of long-running queries. However, to refresh a materialized view we need to run `REFRESH MATERIALIZED VIEW {view_name}`. Leveraging [pg_cron](https://github.com/citusdata/pg_cron), we can automate the refreshing of materialized views.

## Example

Our product allows users to give opinions on content. We would like to display to other users the top 100 active users over the past 50 days who had the most opinions on content. The list can be delayed up to 5 minutes.

This query to do this is:

```sql
-- Takes about 100ms to run with our test data
SELECT
  uo.user_id,
  uo.opinion_type_id,
  st.opinion_type_display,
  COUNT(uo.opinion_type_id) AS opinion_count
FROM example.user_opinion AS uo
INNER JOIN example.opinion_type AS st ON st.opinion_type_id = uo.opinion_type_id
-- filter for only those users who had opinions in the last 50 days
WHERE uo.added_on >= NOW() - INTERVAL '50 days'
GROUP BY uo.user_id, uo.opinion_type_id, st.opinion_type_display
-- ordering by the opinion_count will give us the most active users
ORDER BY opinion_count DESC
-- Limit to the top 100 users
LIMIT 100;
```

With our test data, running this query takes around 100ms. This isn't slow but we want our service to be really performant. We can wrap that query in a materialized query view as follows:

```sql
-- Takes about 100ms to create using our test data
CREATE MATERIALIZED VIEW IF NOT EXISTS example.opinion_activity AS
SELECT
  uo.user_id,
  uo.opinion_type_id,
  st.opinion_type_display,
  COUNT(uo.opinion_type_id) AS opinion_count
FROM example.user_opinion AS uo
INNER JOIN example.opinion_type AS st ON st.opinion_type_id = uo.opinion_type_id
-- filter for only those users who had opinions in the last 50 days
WHERE uo.added_on >= NOW() - INTERVAL '50 days'
GROUP BY uo.user_id, uo.opinion_type_id, st.opinion_type_display
-- ordering by the opinion_count will give us the most active users
ORDER BY opinion_count DESC
-- Limit to the top 100 users
LIMIT 100;
```

Using the `MATERIALIZED VIEW` drops our query time to as low as 2ms.

```sql
-- Takes as low as 2ms to execute
SELECT *
FROM example.opinion_activity;
```

Finally, we need refresh our `MATERIALIZED VIEW` every 5 minutes.

```sql
-- Refresh
SELECT cron.schedule('opinion_activity', '*/5 * * * *',
  $CRON$ REFRESH MATERIALIZED VIEW example.opinion_activity; $CRON$
);

-- See what jobs have been scheduled

SELECT *
FROM cron.job;

-- See details on execution of cron jobs
SELECT *
FROM cron.job_run_details;

-- Unschedule a cron job

SELECT cron.unschedule('opinion_activity');

```

If everything went well you will see the following log output in about 5 minutes:

```bash
# Example output of a successful pg_cron task
cron-example-db  | 2063-04-05 19:28:00.005 UTC [71] LOG:  cron job 1 starting:
  REFRESH MATERIALIZED VIEW example.opinion_activity;
cron-example-db  | 2063-04-05 19:28:00.138 UTC [71] LOG:
  cron job 1 COMMAND completed: REFRESH MATERIALIZED VIEW
```

If you make a mistake, you would see something like the following:

```bash
# Example output of an unsuccessful pg_cron task
cron-example-db  | 2063-04-05 19:20:00.001 UTC [71]
  LOG:  cron job 1 starting:  REFRESH MATERIALIZED VIEW example2.opinion_activity;
cron-example-db  | 2063-04-05 19:20:00.009 UTC [9722]
  ERROR:  schema "example2" does not exist
cron-example-db  | 2063-04-05 19:20:00.009 UTC [9722]
  STATEMENT:   REFRESH MATERIALIZED VIEW example2.opinion_activity;
```

## Setup

### Run This Example

You will need to:

1. Setup [Docker Desktop](https://www.docker.com/products/docker-desktop)
2. Run:

   ```bash
   # clone the repository
   git clone https://github.com/erichosick/postgresql-cron-example.git
   cd postgresql-cron-example
   # see docker-compose.yml
   docker compose up
   ```

3. Use a tool to query the Postgresql instance. Connection information is (see .env.local):
   - Nickname: Example Localhost
   - Host: localhost
   - Port: 5432
   - User: postgres
   - Password: localpassword
   - Database: example

### Setting up pg_cron

#### In Docker

Create a `Dockerfile` to install and configure `pg_cron` (see images/postgresql):

```Dockerfile
# NOTE: This docker file supports Postgresql V14.*. To use 12 or 13 change all 14's to 12/13.
FROM postgres:14.1

RUN apt update
RUN apt -y install postgresql-14-cron
RUN echo "shared_preload_libraries = 'pg_cron'" >> /usr/share/postgresql/14/postgresql.conf.sample
RUN echo "cron.database_name = 'example'" >> /usr/share/postgresql/14/postgresql.conf.sample
```

##### Resetting Build

If you want to retry building a container from scratch, use the following `docker` commands to remove images and containers created in this example.

```bash
docker compose stop
# docker ps -a
docker rm cron-example-db
# docker images
docker rmi cron-example-db
# docker volume ls
docker volume rm postgresql-cron-example_db_data
```

#### In AWS RDS

You will need to enable `pg_cron` for each RDS instance you want to use `pg_cron`.

- With the Parameter group for the database instance:
  - Set `cron.databse_name` to "example".
  - Add `pg_cron` to `shared_preload_libraries`.

#### Possible pg_cron Errors

Potential errors you see while trying to use the `pg_cron` extension.

```sql
-- Have not installed extension
CREATE EXTENSION IF NOT EXISTS pg_cron;
-- ERROR:  could not open extension control file "/usr/share/postgresql/14/extension/pg_cron.control": No such file or directory
```

```sql
-- Installed extension but have not setup a database name
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ERROR:  unrecognized configuration parameter "cron.database_name"
-- CONTEXT:  PL/pgSQL function inline_code_block line 3 at IF
```

```sql
-- Incorrect database name
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ERROR:  can only create extension in database example2
-- DETAIL:  Jobs must be scheduled from the database configured in cron.database_name, since the pg_cron background worker reads job descriptions from this database.
-- HINT:  Add cron.database_name = 'example' in postgresql.conf to use the current database.
-- CONTEXT:  PL/pgSQL function inline_code_block line 4 at RAISE
```

```sql
-- Everything setup correctly
CREATE EXTENSION IF NOT EXISTS pg_cron;
-- CREATE EXTENSION
```
