# syntax=docker/dockerfile:1
#
# storyteller-railway: thin wrapper around the official Storyteller image for Railway.
# Adds a first-boot administrator bootstrap (so the unauthenticated setup page is never public)
# and variable validation. Application code, Readium, whisper.cpp and ffmpeg are unchanged.
#
# Base image is pinned by tag AND digest. Update STORYTELLER_IMAGE and STORYTELLER_VERSION together.
ARG STORYTELLER_IMAGE=registry.gitlab.com/storyteller-platform/storyteller:web-v2.14.21@sha256:f063fcd838ffd9723d581d7a190135069c58c595e6ce9ac41b5e2f8bec090db7

FROM ${STORYTELLER_IMAGE}

ARG STORYTELLER_VERSION=2.14.21
ARG WRAPPER_VERSION=0.0.0-dev
ARG VCS_REF=unknown
ARG BUILD_DATE=1970-01-01T00:00:00Z

COPY licenses/ /usr/share/licenses/storyteller-railway/
COPY --chmod=0755 scripts/entrypoint.sh /usr/local/bin/storyteller-railway-entrypoint
COPY scripts/bootstrap-admin.mjs /usr/local/lib/storyteller-railway/bootstrap-admin.mjs
# the bootstrap runs as the unprivileged storyteller user; prove it can read the script at build time
RUN chmod 755 /usr/local/lib/storyteller-railway && chmod 644 /usr/local/lib/storyteller-railway/bootstrap-admin.mjs \
    && gosu storyteller test -r /usr/local/lib/storyteller-railway/bootstrap-admin.mjs \
    && gosu storyteller node -e "require('/app/.next/standalone/node_modules/argon2')"

# Railway injects PORT; the app must listen on all interfaces for the Railway edge.
ENV HOSTNAME=0.0.0.0 \
    STORYTELLER_DATA_DIR=/data

LABEL org.opencontainers.image.title="storyteller-railway" \
      org.opencontainers.image.description="Community Railway wrapper for Storyteller (ebook + audiobook alignment, read-along books). Not affiliated with the Storyteller project." \
      org.opencontainers.image.source="https://github.com/youssefsiam38/storyteller-railway" \
      org.opencontainers.image.url="https://github.com/youssefsiam38/storyteller-railway" \
      org.opencontainers.image.documentation="https://github.com/youssefsiam38/storyteller-railway#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${WRAPPER_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.base.name="registry.gitlab.com/storyteller-platform/storyteller:web-v${STORYTELLER_VERSION}" \
      io.storyteller-railway.upstream.version="${STORYTELLER_VERSION}"

VOLUME ["/data"]
EXPOSE 8001

ENTRYPOINT ["/usr/local/bin/storyteller-railway-entrypoint"]
CMD ["node", "--enable-source-maps", "server.js"]
