# Use a current LTS Node runtime compatible with google-auth-library
FROM node:20-slim

# Create application directory
RUN mkdir -p /usr/src/app

# Change this as work directory
WORKDIR /usr/src/app

# Copy package.json to work directory
COPY package*.json ./

# Run npm install to install packages
RUN npm install

# Copy the application
COPY . /usr/src/app

# Expose port 3000
EXPOSE 3000

# Run the script to start server
CMD [ "npm", "run", "start" ]
