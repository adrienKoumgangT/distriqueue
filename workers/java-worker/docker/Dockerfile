FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Create non-root user
RUN addgroup -S distriqueue && adduser -S distriqueue -G distriqueue

# Copy JAR file produced by `./mvnw clean package`
COPY target/java-worker-0.0.1-SNAPSHOT.jar app.jar

# Set permissions
RUN chown -R distriqueue:distriqueue /app
USER distriqueue

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8082/worker/actuator/health || exit 1

# Expose port
EXPOSE 8082

# Environment variables
ENV WORKER_ID=java-worker-${HOSTNAME} \
    WORKER_TYPE=java \
    WORKER_CAPACITY=10 \
    RABBITMQ_HOST=rabbitmq1 \
    RABBITMQ_PORT=5672 \
    SERVER_PORT=8082

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
