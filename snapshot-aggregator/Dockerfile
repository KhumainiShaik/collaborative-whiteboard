FROM node:18-alpine

WORKDIR /app

# Install dependencies
COPY package.json package-lock.json* ./
RUN npm ci --only=production

# Copy application
COPY index.js .

# Health check
HEALTHCHECK --interval=10s --timeout=5s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:9090/health', (r) => { if (r.statusCode !== 200) throw new Error(r.statusCode) })"

# Run aggregator
CMD ["node", "index.js"]
