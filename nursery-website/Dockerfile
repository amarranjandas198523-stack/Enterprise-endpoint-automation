# Use official Node runtime as a parent image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package.json and package-lock.json from backend
COPY backend/package*.json ./backend/

# Install dependencies in the backend directory
RUN cd backend && npm install

# Copy the rest of the application code
COPY . .

# Expose the port the app runs on
EXPOSE 3000

# Set the working directory to the backend to run the server
WORKDIR /app/backend

# Initialize the database on startup and then start the Express server
CMD ["node", "server.js"]
