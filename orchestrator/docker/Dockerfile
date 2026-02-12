FROM erlang:26-alpine

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache git make gcc g++ musl-dev linux-headers

# Copy rebar.config and source code
COPY rebar.config .
COPY src/ src/
COPY config/ config/

# Build the application
RUN rebar3 compile

# Create release
RUN rebar3 as prod tar

# Extract release
RUN mkdir -p /opt/distriqueue && \
    tar -xzf _build/prod/rel/distriqueue/distriqueue-1.0.0.tar.gz -C /opt/distriqueue

# Switch to runtime environment
FROM erlang:26-alpine

WORKDIR /opt/distriqueue

# Copy release from build stage
COPY --from=0 /opt/distriqueue .

# Create non-root user
RUN addgroup -g 1000 distriqueue && \
    adduser -u 1000 -G distriqueue -s /bin/sh -D distriqueue && \
    chown -R distriqueue:distriqueue /opt/distriqueue

USER distriqueue

# Create log directory
RUN mkdir -p /opt/distriqueue/log

# Expose ports
EXPOSE 8081 9100

# Set environment variables
ENV NODE_NAME=orchestrator1@distriqueue \
    COOKIE=distriqueue-cookie \
    RABBITMQ_HOST=rabbitmq1 \
    RABBITMQ_PORT=5672 \
    RABBITMQ_USERNAME=admin \
    RABBITMQ_PASSWORD=admin \
    HTTP_PORT=8081 \
    METRICS_PORT=9100

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8081/api/health || exit 1

# Start the application
CMD ["/opt/distriqueue/bin/distriqueue", "foreground"]
