FROM node:20-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

# Create logs directory
RUN mkdir -p logs

# Copy all required files
COPY app.js .
COPY tracing.js .
COPY logger.js .

# Set Jaeger endpoint (will be overridden by environment variable if provided)
ENV JAEGER_ENDPOINT=http://localhost:14268/api/traces

EXPOSE 5000

CMD ["npm", "start"]
