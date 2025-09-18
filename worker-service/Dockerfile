# Use official Python runtime as a base image
FROM python:3.11-alpine

# Install security updates and build dependencies
RUN apk --no-cache upgrade && \
    apk add --no-cache --virtual .build-deps gcc musl-dev

# Set working directory
WORKDIR /app

# Copy requirements file
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt && \
    apk del .build-deps

# Create a non-root user
RUN addgroup -g 1001 -S python && \
    adduser -S worker-user -u 1001

# Copy application code
COPY --chown=worker-user:python . .

# Switch to non-root user
USER worker-user

# Start the application
CMD ["python", "src/worker.py"]