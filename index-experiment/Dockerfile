FROM postgres:18.3-bookworm

RUN mv /etc/apt/sources.list.d/pgdg.list /tmp/pgdg.list \
    && apt-get -o Acquire::Retries=3 --error-on=any update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && update-ca-certificates \
    && mv /tmp/pgdg.list /etc/apt/sources.list.d/pgdg.list

RUN sed -i 's|http://apt.postgresql.org|https://apt.postgresql.org|g' \
       /etc/apt/sources.list.d/pgdg.list \
    && apt-mark hold postgresql-18 postgresql-client-18 \
    && apt-get -o Acquire::Retries=3 --error-on=any update \
    && apt-get install -y --no-install-recommends \
       postgresql-18-hypopg locales \
    && localedef -i ru_RU -c -f UTF-8 ru_RU.UTF-8 \
    && postgres --version | grep -E 'PostgreSQL\) 18\.3([[:space:]]|$)' \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=ru_RU.UTF-8