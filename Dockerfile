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

EXPOSE 5000

CMD ["npm", "start"]
