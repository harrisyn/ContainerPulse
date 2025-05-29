FROM node:18-alpine

LABEL maintainer="Harrison <harrison@example.com>"
LABEL description="ContainerPulse - A Docker container that documents and safely updates other containers with web interface"

# Install dependencies
RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    jq

# Set up directories
RUN mkdir -p /var/log/containerpulse \
    /var/lib/containerpulse/container-inventory \
    /var/lib/containerpulse/backups

# Set working directory
WORKDIR /app

# Copy package.json and install Node.js dependencies
COPY package.json ./
RUN npm install

# Copy Tailwind config files for CSS build
COPY tailwind.config.js postcss.config.js ./

# Copy the application
COPY src/ ./src/

# Build Tailwind CSS to generate output.css from styles.css
RUN npx tailwindcss -i ./src/web/public/css/styles.css -o ./src/web/public/css/output.css --minify

# Copy the script into the image
COPY containerpulse-updater.sh /usr/local/bin/
COPY startup.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/containerpulse-updater.sh /usr/local/bin/startup.sh

# Environment variables with defaults
ENV UPDATE_INTERVAL=86400
ENV LOG_LEVEL=info
ENV NODE_ENV=production
ENV PORT=3000

# Expose web interface port
EXPOSE 3000

# Volume for persistent data
VOLUME ["/var/lib/containerpulse", "/var/log/containerpulse"]

# Run both the web interface and updater script
CMD ["/usr/local/bin/startup.sh"]