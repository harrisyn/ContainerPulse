#!/bin/bash

# ContainerPulse Deployment Script
# Handles safe deployment and updates of ContainerPulse with rollback capability

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.prod.yml"
SERVICE_NAME="containerpulse"
IMAGE_NAME="harrisyn/containerpulse:latest"
BACKUP_DIR="${SCRIPT_DIR}/deployment-backups"
LOG_FILE="${SCRIPT_DIR}/deployment.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

# Function to check if ContainerPulse is healthy
check_health() {
    local timeout=${1:-30}
    local count=0
    
    log "Checking ContainerPulse health..."
    
    while [ $count -lt $timeout ]; do
        if curl -f -s http://localhost:3000/api/health > /dev/null 2>&1; then
            success "ContainerPulse is healthy"
            return 0
        fi
        sleep 2
        count=$((count + 2))
        echo -n "."
    done
    
    error "ContainerPulse health check failed after ${timeout} seconds"
    return 1
}

# Function to backup current configuration
backup_current_state() {
    local backup_timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_path="${BACKUP_DIR}/${backup_timestamp}"
    
    mkdir -p "$backup_path"
    
    log "Backing up current state to: $backup_path"
    
    # Backup container configuration
    if docker ps --format "{{.Names}}" | grep -q "^${SERVICE_NAME}$"; then
        docker inspect "$SERVICE_NAME" > "${backup_path}/container_inspect.json"
        docker logs "$SERVICE_NAME" > "${backup_path}/container_logs.txt" 2>&1
    fi
    
    # Backup compose file
    if [ -f "$COMPOSE_FILE" ]; then
        cp "$COMPOSE_FILE" "${backup_path}/docker-compose.prod.yml"
    fi
    
    # Save current image info
    if docker images --format "{{.Repository}}:{{.Tag}},{{.ID}}" | grep -q "$IMAGE_NAME"; then
        docker images --format "{{.Repository}}:{{.Tag}},{{.ID}},{{.CreatedAt}}" | grep "$IMAGE_NAME" > "${backup_path}/image_info.txt"
    fi
    
    echo "$backup_timestamp" > "${BACKUP_DIR}/latest_backup"
    success "Backup completed: $backup_path"
}

# Function to rollback to previous state
rollback() {
    local backup_timestamp="$1"
    
    if [ -z "$backup_timestamp" ]; then
        if [ -f "${BACKUP_DIR}/latest_backup" ]; then
            backup_timestamp=$(cat "${BACKUP_DIR}/latest_backup")
        else
            error "No backup timestamp provided and no latest backup found"
            return 1
        fi
    fi
    
    local backup_path="${BACKUP_DIR}/${backup_timestamp}"
    
    if [ ! -d "$backup_path" ]; then
        error "Backup not found: $backup_path"
        return 1
    fi
    
    warn "Rolling back to backup: $backup_timestamp"
    
    # Stop current container
    docker-compose -f "$COMPOSE_FILE" down || true
    
    # Restore compose file if it was backed up
    if [ -f "${backup_path}/docker-compose.prod.yml" ]; then
        cp "${backup_path}/docker-compose.prod.yml" "$COMPOSE_FILE"
    fi
    
    # Start with backed up configuration
    docker-compose -f "$COMPOSE_FILE" up -d
    
    if check_health; then
        success "Rollback completed successfully"
        return 0
    else
        error "Rollback failed - service is not healthy"
        return 1
    fi
}

# Function to deploy/update ContainerPulse
deploy() {
    local force_update="$1"
    
    log "Starting ContainerPulse deployment..."
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Check if service is currently running
    local is_running=false
    if docker ps --format "{{.Names}}" | grep -q "^${SERVICE_NAME}$"; then
        is_running=true
        log "ContainerPulse is currently running"
    else
        log "ContainerPulse is not currently running"
    fi
    
    # Backup current state if running
    if [ "$is_running" = true ]; then
        backup_current_state
    fi
    
    # Pull latest image
    log "Pulling latest image: $IMAGE_NAME"
    if ! docker pull "$IMAGE_NAME"; then
        error "Failed to pull latest image"
        return 1
    fi
    
    # Check if update is needed (unless forced)
    if [ "$force_update" != "force" ] && [ "$is_running" = true ]; then
        local current_image_id=$(docker inspect --format '{{.Image}}' "$SERVICE_NAME" 2>/dev/null || echo "")
        local latest_image_id=$(docker inspect --format '{{.Id}}' "$IMAGE_NAME" 2>/dev/null || echo "")
        
        if [ "$current_image_id" = "$latest_image_id" ]; then
            success "ContainerPulse is already running the latest image"
            return 0
        fi
    fi
    
    # Deploy the service
    log "Deploying ContainerPulse..."
    
    # Use docker-compose for deployment
    if ! docker-compose -f "$COMPOSE_FILE" up -d --remove-orphans; then
        error "Failed to start ContainerPulse with docker-compose"
        
        # Attempt rollback if we had a backup
        if [ "$is_running" = true ]; then
            warn "Attempting automatic rollback..."
            if rollback; then
                warn "Rollback successful, but deployment failed"
                return 1
            else
                error "Both deployment and rollback failed!"
                return 1
            fi
        fi
        return 1
    fi
    
    # Wait for service to be healthy
    log "Waiting for ContainerPulse to become healthy..."
    if check_health 60; then
        success "ContainerPulse deployment successful!"
        
        # Clean up old images (keep last 2)
        log "Cleaning up old images..."
        docker images "$IMAGE_NAME" --format "{{.ID}}" | tail -n +3 | xargs -r docker rmi 2>/dev/null || true
        
        return 0
    else
        error "ContainerPulse deployment failed - service is not healthy"
        
        # Attempt rollback
        if [ "$is_running" = true ]; then
            warn "Attempting automatic rollback..."
            if rollback; then
                warn "Rollback successful, but deployment failed"
                return 1
            else
                error "Both deployment and rollback failed!"
                return 1
            fi
        fi
        return 1
    fi
}

# Function to show usage
usage() {
    echo "ContainerPulse Deployment Script"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  deploy          Deploy/update ContainerPulse (default)"
    echo "  deploy force    Force deployment even if no update needed"
    echo "  rollback        Rollback to latest backup"
    echo "  rollback <id>   Rollback to specific backup"
    echo "  status          Check current status"
    echo "  health          Check health status"
    echo "  logs            Show logs"
    echo "  backup          Create manual backup"
    echo "  list-backups    List available backups"
    echo ""
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 rollback 20241129_143022"
    echo "  $0 status"
}

# Function to show status
show_status() {
    log "ContainerPulse Status:"
    
    if docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -q "$SERVICE_NAME"; then
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | head -1
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "$SERVICE_NAME"
        echo ""
        
        if check_health 5; then
            success "Service is running and healthy"
        else
            warn "Service is running but not healthy"
        fi
    else
        warn "ContainerPulse is not running"
    fi
    
    # Show image info
    echo ""
    log "Image Information:"
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}" | head -1
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}" | grep "$IMAGE_NAME" || echo "Image not found locally"
}

# Function to list backups
list_backups() {
    log "Available backups:"
    if [ -d "$BACKUP_DIR" ]; then
        ls -la "$BACKUP_DIR" | grep "^d" | awk '{print $9}' | grep -E "^[0-9]{8}_[0-9]{6}$" | sort -r
        
        if [ -f "${BACKUP_DIR}/latest_backup" ]; then
            echo ""
            echo "Latest backup: $(cat "${BACKUP_DIR}/latest_backup")"
        fi
    else
        warn "No backup directory found"
    fi
}

# Main script logic
case "${1:-deploy}" in
    deploy)
        deploy "$2"
        ;;
    rollback)
        rollback "$2"
        ;;
    status)
        show_status
        ;;
    health)
        check_health
        ;;
    logs)
        docker-compose -f "$COMPOSE_FILE" logs -f
        ;;
    backup)
        backup_current_state
        ;;
    list-backups)
        list_backups
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        error "Unknown command: $1"
        usage
        exit 1
        ;;
esac
