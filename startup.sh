#!/bin/bash

# Startup script for ContainerPulse with Web Interface

echo "Starting ContainerPulse..."

# Wait for Docker socket to be available
while [ ! -S /var/run/docker.sock ]; do
    echo "Waiting for Docker socket..."
    sleep 2
done

echo "Docker socket available, starting services..."

# Start the web interface in background
echo "Starting ContainerPulse web interface on port ${PORT:-3000}..."
cd /app
node src/web/server.js &
WEB_PID=$!

echo "ContainerPulse web interface started with PID $WEB_PID"

# Give the web interface a moment to start
sleep 5

# Start the container monitoring script
echo "Starting container monitoring script..."
exec /usr/local/bin/containerpulse-updater.sh
