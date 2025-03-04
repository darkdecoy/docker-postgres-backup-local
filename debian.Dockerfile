ARG BASETAG=latest
FROM postgres:$BASETAG

ARG GOCRONVER=v0.0.10
ARG TARGETOS
ARG TARGETARCH

# FIX Debian cross build
ARG DEBIAN_FRONTEND=noninteractive
RUN set -x \
	&& ln -s /usr/bin/dpkg-split /usr/sbin/dpkg-split \
	&& ln -s /usr/bin/dpkg-deb /usr/sbin/dpkg-deb \
	&& ln -s /bin/tar /usr/sbin/tar \
	&& ln -s /bin/rm /usr/sbin/rm \
	&& ln -s /usr/bin/dpkg-split /usr/local/sbin/dpkg-split \
	&& ln -s /usr/bin/dpkg-deb /usr/local/sbin/dpkg-deb \
	&& ln -s /bin/tar /usr/local/sbin/tar \
	&& ln -s /bin/rm /usr/local/sbin/rm
#

RUN set -x \
	&& apt-get update && apt-get install -y --no-install-recommends ca-certificates curl procps && apt-get clean && rm -rf /var/lib/apt/lists/* \
	&& curl -o /usr/local/bin/go-cron.gz -L https://github.com/prodrigestivill/go-cron/releases/download/$GOCRONVER/go-cron-$TARGETOS-$TARGETARCH.gz \
	&& gzip -vnd /usr/local/bin/go-cron.gz && chmod a+x /usr/local/bin/go-cron

ENV POSTGRES_DB="**None**" \
    POSTGRES_DB_FILE="**None**" \
    POSTGRES_HOST="**None**" \
    POSTGRES_PORT=5432 \
    POSTGRES_USER="**None**" \
    POSTGRES_USER_FILE="**None**" \
    POSTGRES_PASSWORD="**None**" \
    POSTGRES_PASSWORD_FILE="**None**" \
    POSTGRES_PASSFILE_STORE="**None**" \
    POSTGRES_EXTRA_OPTS="-Z6" \
    POSTGRES_CLUSTER="FALSE" \
    SCHEDULE="@daily" \
    BACKUP_DIR="/backups" \
    BACKUP_SUFFIX=".sql.gz" \
    BACKUP_KEEP_DAYS=7 \
    BACKUP_KEEP_WEEKS=4 \
    BACKUP_KEEP_MONTHS=6 \
    BACKUP_KEEP_MINS=1440 \
    BACKUP_WEEK_DAY="Sunday" \
    BACKUP_MONTH_DAY=1 \
    BACKUP_VERBOSITY=6 \
    BACKUP_MATRIX_VERBOSITY=0 \
    BACKUP_ELEMENT_SERVER="**None**" \
    BACKUP_ROOM_ID="**None**" \
    BACKUP_ACCESS_TOKEN="**None**" \
    LOGDIR=/backups/logs \
    HEALTHCHECK_PORT=8080 \
    WEBHOOK_URL="**None**" \
    WEBHOOK_EXTRA_ARGS=""

COPY hooks /hooks
COPY backup.sh /backup.sh
COPY log.sh /log.sh

VOLUME /backups
VOLUME /backups/logs/

ENTRYPOINT ["/bin/sh", "-c"]
CMD ["exec /usr/local/bin/go-cron -s \"$SCHEDULE\" -p \"$HEALTHCHECK_PORT\" -- /backup.sh -a"]

HEALTHCHECK --interval=5m --timeout=3s \
  CMD curl -f "http://localhost:$HEALTHCHECK_PORT/" || exit 1
