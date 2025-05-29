#!/bin/bash

# Self-Update Handler for ContainerPulse
# This script handles the special case of ContainerPulse updating itself

# Check if this is a self-update
check_self_update() {
    local container_name="$1"
    local my_name
    my_name=$(hostname)
    
    # Check if we're updating ourselves
    if [ "$container_name" == "$my_name" ] || [ "$container_name" == "containerpulse" ]; then
        return 0  # This is a self-update
    fi
    return 1  # Not a self-update
}

# Handle self-update with delayed restart
handle_self_update() {
    local container_name="$1"
    local image_name="$2"
    local container_data="$3"
    
    log "warn" "SELF-UPDATE DETECTED: Preparing to update ContainerPulse itself"
    
    # Create a restart script that will run after this container stops
    cat > /tmp/restart-containerpulse.sh << 'EOF'
#!/bin/bash
sleep 10  # Wait for old container to fully stop

CONTAINER_NAME="containerpulse"
IMAGE_NAME="harrisyn/containerpulse:latest"

# Remove old container
docker rm -f "$CONTAINER_NAME" 2>/dev/null

# Check if docker-compose is available
if [ -f "/var/lib/containerpulse/docker-compose.prod.yml" ]; then
    cd /var/lib/containerpulse
    docker-compose -f docker-compose.prod.yml up -d containerpulse
else
    # Fallback to docker run with basic configuration
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p 3000:3000 \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -v containerpulse-data:/var/lib/containerpulse \
        -v containerpulse-logs:/var/log/containerpulse \
        -e NODE_ENV=production \
        -e UPDATE_INTERVAL=86400 \
        -e LOG_LEVEL=info \
        -e SESSION_SECRET="${SESSION_SECRET:-change-this-session-secret}" \
        -e JWT_SECRET="${JWT_SECRET:-change-this-jwt-secret}" \
        -e WEBHOOK_SECRET="${WEBHOOK_SECRET:-change-this-webhook-secret}" \
        -e ADMIN_USERNAME="${ADMIN_USERNAME:-admin}" \
        -e ADMIN_PASSWORD="${ADMIN_PASSWORD:-change-this-password}" \
        --label "auto-update=true" \
        "$IMAGE_NAME"
fi

# Clean up this script
rm -f /tmp/restart-containerpulse.sh
EOF

    chmod +x /tmp/restart-containerpulse.sh
    
    # Copy docker-compose file to a persistent location for restart script
    if [ -f "/app/docker-compose.prod.yml" ]; then
        cp /app/docker-compose.prod.yml /var/lib/containerpulse/
    fi
    
    log "info" "Self-update restart script created. Scheduling delayed restart..."
    
    # Schedule the restart script to run in background
    nohup /tmp/restart-containerpulse.sh > /var/log/containerpulse/self-restart.log 2>&1 &
    
    # Log the self-update and exit
    log "info" "SELF-UPDATE: ContainerPulse will restart with new image in 10 seconds"
    log "info" "Exiting to allow restart..."
    
    # Exit the current process, allowing the container to stop
    exit 0
}

# Example usage in the main update function:
# if check_self_update "$container_name"; then
#     handle_self_update "$container_name" "$image_name" "$container_data"
# fi
