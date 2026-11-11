FROM postgres:18.3-bookworm

RUN apt-mark hold postgresql-18 postgresql-client-18 \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       postgresql-18-hypopg locales \
    && localedef -i ru_RU -c -f UTF-8 ru_RU.UTF-8 \
    && postgres --version | grep -E 'PostgreSQL\) 18\.3([[:space:]]|$)' \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=ru_RU.UTF-8
