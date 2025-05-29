#!/bin/bash

# ContainerPulse Watchdog
# Monitors ContainerPulse container and restarts it if it goes down

CONTAINERPULSE_NAME="containerpulse"
CHECK_INTERVAL=30  # Check every 30 seconds
LOG_FILE="/var/log/watchdog.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "ContainerPulse Watchdog started. Monitoring container: $CONTAINERPULSE_NAME"

while true; do
    # Check if ContainerPulse container is running
    if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINERPULSE_NAME}$"; then
        log "WARNING: ContainerPulse container is not running. Attempting restart..."
        
        # Try to start the existing container first
        if docker start "$CONTAINERPULSE_NAME" 2>/dev/null; then
            log "SUCCESS: Restarted existing ContainerPulse container"
        else
            log "INFO: Could not restart existing container. Checking for updated image..."
            
            # Pull latest image
            if docker pull harrisyn/containerpulse:latest; then
                log "INFO: Pulled latest ContainerPulse image"
                
                # Remove the old container if it exists
                docker rm "$CONTAINERPULSE_NAME" 2>/dev/null
                
                # Start with docker-compose if available
                if [ -f "/app/docker-compose.prod.yml" ]; then
                    log "INFO: Starting ContainerPulse with docker-compose"
                    cd /app && docker-compose -f docker-compose.prod.yml up -d containerpulse
                else
                    log "INFO: Starting ContainerPulse with docker run"
                    docker run -d \
                        --name "$CONTAINERPULSE_NAME" \
                        --restart unless-stopped \
                        -p 3000:3000 \
                        -v /var/run/docker.sock:/var/run/docker.sock:ro \
                        -v containerpulse-data:/var/lib/containerpulse \
                        -v containerpulse-logs:/var/log/containerpulse \
                        -e NODE_ENV=production \
                        -e UPDATE_INTERVAL=86400 \
                        -e LOG_LEVEL=info \
                        --label "auto-update=true" \
                        harrisyn/containerpulse:latest
                fi
                
                log "SUCCESS: ContainerPulse container restarted with latest image"
            else
                log "ERROR: Failed to pull ContainerPulse image"
            fi
        fi
    else
        log "INFO: ContainerPulse container is running normally"
    fi
    
    sleep "$CHECK_INTERVAL"
done
