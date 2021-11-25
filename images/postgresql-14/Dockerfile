# NOTE: This docker file supports Postgresql V14.*. To use V12 or V13
# comment/uncomment code as needed.

# https://hub.docker.com/_/postgres/
# FROM postgres:12.9
# FROM postgres:13.5
FROM postgres:14.1

RUN apt update
# RUN apt -y install postgresql-12-cron
# RUN apt -y install postgresql-13-cron
RUN apt -y install postgresql-14-cron
# RUN echo "shared_preload_libraries = 'pg_cron'" >> /usr/share/postgresql/12/postgresql.conf.sample
# RUN echo "shared_preload_libraries = 'pg_cron'" >> /usr/share/postgresql/13/postgresql.conf.sample
RUN echo "shared_preload_libraries = 'pg_cron'" >> /usr/share/postgresql/14/postgresql.conf.sample

# NOTE: Database name is example. If you change the database name, then you
# will also need to change the database name here
# RUN echo "cron.database_name = 'example'" >> /usr/share/postgresql/12/postgresql.conf.sample
# RUN echo "cron.database_name = 'example'" >> /usr/share/postgresql/13/postgresql.conf.sample
RUN echo "cron.database_name = 'example'" >> /usr/share/postgresql/14/postgresql.conf.sample

COPY /migration/ /docker-entrypoint-initdb.d/

# NOTE: other config files in postgres image are
# /usr/share/postgresql/postgresql.conf.sample.dpkg
# /usr/share/postgresql/postgresql.conf.sampled