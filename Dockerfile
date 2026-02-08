FROM node:18-alpine

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY app.js .

EXPOSE 5000

CMD ["npm", "start"]
