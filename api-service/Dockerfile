# Use official Node.js runtime as a base image
FROM node:18-alpine AS builder

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Use a smaller image for runtime
FROM node:18-alpine

# Install security updates
RUN apk --no-cache upgrade

# Create a non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S api-user -u 1001

# Set working directory
WORKDIR /app

# Copy built application
COPY --from=builder --chown=api-user:nodejs /app/node_modules ./node_modules
COPY --chown=api-user:nodejs . .

# Create a simple healthcheck script
RUN echo "const http = require('http'); const options = { host: 'localhost', port: 3000, path: '/api/health', timeout: 2000 }; const request = http.request(options, (res) => { process.exit(res.statusCode === 200 ? 0 : 1); }); request.on('error', () => { process.exit(1); }); request.on('timeout', () => { process.exit(1); }); request.end();" > healthcheck.js

# Switch to non-root user
USER api-user

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node healthcheck.js

# Start the application
CMD ["node", "src/index.js"]