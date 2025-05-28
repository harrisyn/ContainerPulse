#!/bin/bash

echo "Starting ContainerPulse in DEVELOPMENT mode with hot reloading..."

# Wait for Docker socket to be available
while [ ! -S /var/run/docker.sock ]; do
    echo "Waiting for Docker socket..."
    sleep 2
done

echo "Docker socket available, starting services..."

# Start the web interface with nodemon for hot reloading
echo "Starting ContainerPulse web interface with hot reloading on port ${PORT:-3000}..."
cd /app
nodemon --watch src --ext js,ejs,json src/web/server.js &
WEB_PID=$!

echo "Web interface started with PID $WEB_PID (hot reloading enabled)"

# Give the web interface a moment to start
sleep 5

# Start the auto-updater script with shorter intervals for development
echo "Starting auto-updater script in development mode..."
exec /usr/local/bin/containerpulse-updater.sh
