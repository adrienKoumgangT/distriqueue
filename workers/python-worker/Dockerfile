FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir \
    pika==1.3.2 \
    requests==2.31.0

# Copy worker script
COPY worker.py .

# Create non-root user
RUN useradd -m -u 1000 distriqueue && chown -R distriqueue:distriqueue /app
USER distriqueue

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import socket; socket.create_connection(('localhost', 5672), timeout=5)" || exit 1

# Run worker
CMD ["python", "-u", "worker.py"]
