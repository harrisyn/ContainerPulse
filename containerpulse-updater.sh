#!/bin/bash

# containerpulse-updater.sh
# ContainerPulse - A script to document all running Docker containers and safely update those with auto-update label
# Designed to run inside a container with access to the Docker socket

# Configure paths for containerized environment
LOG_FILE="/var/log/containerpulse/auto-updater.log"
INVENTORY_FILE="/var/lib/containerpulse/container-inventory/inventory.json"
BACKUP_DIR="/var/lib/containerpulse/backups"

# Get settings from environment variables
UPDATE_INTERVAL=${UPDATE_INTERVAL:-86400}  # Default: 24 hours
LOG_LEVEL=${LOG_LEVEL:-"info"}
CLEANUP_OLD_IMAGES=${CLEANUP_OLD_IMAGES:-"false"}  # Set to "true" to remove old images after update

# Email notification settings
EMAIL_ENABLED=${EMAIL_ENABLED:-"false"}
EMAIL_TO=${EMAIL_TO:-""}
EMAIL_FROM=${EMAIL_FROM:-"containerpulse@localhost"}
EMAIL_SUBJECT=${EMAIL_SUBJECT:-"ContainerPulse: Container Update Available"}
SMTP_SERVER=${SMTP_SERVER:-"localhost"}
SMTP_PORT=${SMTP_PORT:-"587"}
SMTP_USER=${SMTP_USER:-""}
SMTP_PASSWORD=${SMTP_PASSWORD:-""}

# Create necessary directories
mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$INVENTORY_FILE")" "$BACKUP_DIR"

# Function to log messages
log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Only log if level is appropriate
    case "$LOG_LEVEL" in
        debug)
            # Log everything
            ;;
        info)
            # Skip debug logs
            if [ "$level" == "debug" ]; then return; fi
            ;;
        warn|warning)
            # Skip debug and info logs
            if [ "$level" == "debug" ] || [ "$level" == "info" ]; then return; fi
            ;;
        error)
            # Only log errors
            if [ "$level" != "error" ]; then return; fi
            ;;
    esac
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log "info" "Starting Docker container auto-updater"
log "info" "Update interval set to $UPDATE_INTERVAL seconds"

# Function to send email notifications
send_email_notification() {
    local container_name="$1"
    local current_image="$2"
    local available_update="$3"
    
    if [ "$EMAIL_ENABLED" != "true" ] || [ -z "$EMAIL_TO" ]; then
        log "debug" "Email notifications disabled or no recipient configured"
        return 0
    fi
    
    local email_body
    email_body=$(cat <<EOF
Container Update Available

Container: $container_name
Current Image: $current_image
Update Available: $available_update

This container has the 'update-approach=notify' label, so it will not be automatically updated.
Please review and update manually if desired.

ContainerPulse Auto-Updater
$(date)
EOF
)
    
    # Try to send email using available methods
    if command -v sendmail >/dev/null 2>&1; then
        # Use sendmail if available
        {
            echo "To: $EMAIL_TO"
            echo "From: $EMAIL_FROM"
            echo "Subject: $EMAIL_SUBJECT"
            echo ""
            echo "$email_body"
        } | sendmail "$EMAIL_TO"
        log "info" "Email notification sent via sendmail to $EMAIL_TO for container $container_name"
    elif command -v curl >/dev/null 2>&1 && [ -n "$SMTP_SERVER" ] && [ -n "$SMTP_USER" ]; then
        # Use curl with SMTP if configured
        local temp_email_file="/tmp/containerpulse_email_$$.txt"
        {
            echo "To: $EMAIL_TO"
            echo "From: $EMAIL_FROM"
            echo "Subject: $EMAIL_SUBJECT"
            echo ""
            echo "$email_body"
        } > "$temp_email_file"
        
        if curl --url "smtp://$SMTP_SERVER:$SMTP_PORT" \
                --ssl-reqd \
                --mail-from "$EMAIL_FROM" \
                --mail-rcpt "$EMAIL_TO" \
                --user "$SMTP_USER:$SMTP_PASSWORD" \
                --upload-file "$temp_email_file" >/dev/null 2>&1; then
            log "info" "Email notification sent via SMTP to $EMAIL_TO for container $container_name"
        else
            log "error" "Failed to send email notification via SMTP for container $container_name"
        fi
        
        rm -f "$temp_email_file"
    else
        log "warn" "No email sending method available (sendmail or curl with SMTP). Logging notification instead."
        log "info" "NOTIFICATION: Container $container_name has update available: $current_image -> $available_update"
    fi
}

# Function to document running containers and add to inventory
document_containers() {
    log "info" "Documenting all running containers..."
    
    # Create temporary file for new inventory
    local temp_inventory
    temp_inventory=$(mktemp)
    
    # Get list of running containers
    containers=$(docker ps -q)
    
    echo "[" > "$temp_inventory"
    first=true
    
    for container_id in $containers; do
        # Skip our own container
        self_id=$(cat /proc/self/cgroup | grep "docker" | sed 's/^.*\///' | head -n 1)
        if [ "$container_id" == "$self_id" ]; then
            log "debug" "Skipping our own container"
            continue
        fi

        # Check for auto-update labels (supports multiple formats)
        labels=$(docker inspect --format '{{json .Config.Labels}}' "$container_id" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
        auto_update=false
        for label in $labels; do
            case "$label" in
                "auto-update=true"|"com.your.auto-update=true"|"com.github.containrrr.watchtower.enable=true"|"com.centurylinklabs.watchtower.enable=true")
                    auto_update=true
                    ;;
            esac
        done
        if [ "$auto_update" != true ]; then
            log "debug" "Skipping container $container_id (no auto-update label)"
            continue
        fi

        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$temp_inventory"
        fi

        log "debug" "Documenting and backing up container: $container_id"

        # Get container name
        container_name=$(docker inspect --format '{{.Name}}' "$container_id" | sed 's/^\///')

        # Create container backup directory
        container_backup_dir="$BACKUP_DIR/$container_name"
        mkdir -p "$container_backup_dir"

        # Save full container inspect data
        docker inspect "$container_id" > "$container_backup_dir/inspect.json"

        # Extract creation command and args for easier recreation
        creation_args=$(docker inspect --format '{{ range $index, $value := .Config.Cmd }}{{ if $index }} {{ end }}{{ json . }}{{ end }}' "$container_id")
        creation_entrypoint=$(docker inspect --format '{{ range $index, $value := .Config.Entrypoint }}{{ if $index }} {{ end }}{{ json . }}{{ end }}' "$container_id")

        # Extract key container details for our inventory
        container_info=$(docker inspect --format '{
            "id": "{{.Id}}",
            "name": "{{.Name}}",
            "image": "{{.Config.Image}}",
            "imageId": "{{.Image}}",
            "command": [{{ range $index, $value := .Config.Cmd }}{{if $index}}, {{end}}{{json .}}{{end}}],
            "entrypoint": [{{ range $index, $value := .Config.Entrypoint }}{{if $index}}, {{end}}{{json .}}{{end}}],
            "created": "{{.Created}}",
            "state": {{json .State}},
            "restartPolicy": {{json .HostConfig.RestartPolicy}},
            "network": {{json .NetworkSettings.Networks}},
            "mounts": {{json .Mounts}},
            "ports": {{json .NetworkSettings.Ports}},
            "labels": {{json .Config.Labels}},
            "env": {{json .Config.Env}},
            "hostConfig": {
                "privileged": {{.HostConfig.Privileged}},
                "devices": {{json .HostConfig.Devices}},
                "capAdd": {{json .HostConfig.CapAdd}},
                "capDrop": {{json .HostConfig.CapDrop}},
                "dns": {{json .HostConfig.Dns}},
                "dnsSearch": {{json .HostConfig.DnsSearch}},
                "extraHosts": {{json .HostConfig.ExtraHosts}},
                "logConfig": {{json .HostConfig.LogConfig}}
            }
        }' "$container_id")

        echo "$container_info" >> "$temp_inventory"
    done
    
    echo "]" >> "$temp_inventory"
    
    # Replace inventory file with new data
    mv "$temp_inventory" "$INVENTORY_FILE"
    log "info" "Container documentation complete. Inventory saved to $INVENTORY_FILE"
}

# Function to check if an image is locally built
is_locally_built_image() {
    local image_name="$1"
    
    # Check for Docker Compose naming patterns (contains underscore or hyphen without slash)
    if [[ "$image_name" =~ ^[^/]*[_-][^/]*$ ]]; then
        return 0  # Is locally built
    fi
    
    # Check if image has no registry and no tag (indicating custom build)
    # Standard Docker Hub images like "nginx", "alpine", etc. are NOT locally built
    # Only images without slashes AND with custom patterns are locally built
    if [[ ! "$image_name" =~ [./] ]] && [[ "$image_name" =~ [_-] ]]; then
        return 0  # Is locally built (custom name with underscore/hyphen)
    fi
    
    return 1  # Not locally built
}

# Function to check and update containers with auto-update label
update_containers() {
    log "info" "Checking containers with auto-update label for updates..."
    
    # Read inventory file
    if [ ! -f "$INVENTORY_FILE" ]; then
        log "error" "Inventory file does not exist. Run documentation first."
        return 1
    fi
    
    # Get containers with auto-update label (supports multiple label formats)
    auto_update_containers=$(cat "$INVENTORY_FILE" | jq -r '.[] | 
        select(
            .labels["com.your.auto-update"] == "true" or 
            .labels["auto-update"] == "true" or 
            .labels["com.github.containrrr.watchtower.enable"] == "true" or
            .labels["com.centurylinklabs.watchtower.enable"] == "true"
        ) | .name' | sed 's/^\///')
    
    if [ -z "$auto_update_containers" ]; then
        log "info" "No containers found with auto-update labels"
        return 0
    fi
    
    for container_name in $auto_update_containers; do
        log "info" "Processing container for update: $container_name"
        
        # Get current container details from inventory
        container_data=$(cat "$INVENTORY_FILE" | jq -r --arg name "/$container_name" '.[] | select(.name == $name)')
        
        if [ -z "$container_data" ]; then
            log "warn" "Container $container_name not found in inventory, skipping"
            continue
        fi
        
        # Extract image name
        image_name=$(echo "$container_data" | jq -r '.image')
        
        log "info" "Current image: $image_name"
        
        # Check if this is a locally built image
        if is_locally_built_image "$image_name"; then
            log "info" "Image $image_name appears to be locally built. Skipping update check."
            continue
        fi
        
        # Pull the latest image for registry images
        log "info" "Pulling latest image for $image_name"
        if ! docker pull "$image_name"; then
            log "error" "Failed to pull latest image for $container_name. Skipping update."
            continue
        fi
        
        # Get new image ID
        new_image_id=$(docker inspect --format '{{.Id}}' "$image_name")
        
        # Get current image ID from inventory
        current_image_id=$(echo "$container_data" | jq -r '.imageId')
         # Check if image was updated
        if [ "$new_image_id" = "$current_image_id" ]; then
            log "info" "No new image available for $container_name. Skipping update."
            continue
        fi

        log "info" "New image available for $container_name."
        
        # Check update approach label
        update_approach=$(docker inspect "$container_name" --format '{{ index .Config.Labels "update-approach" }}' 2>/dev/null || echo "")
        
        if [ "$update_approach" = "notify" ]; then
            log "info" "Container $container_name has 'update-approach=notify' label. Sending notification instead of updating."
            send_email_notification "$container_name" "$current_image_id" "$new_image_id"
            continue
        fi
        
        log "info" "Proceeding with automatic update for $container_name..."
        
        # Back up container configuration
        container_backup_dir="$BACKUP_DIR/$container_name"
        backup_file="$container_backup_dir/pre-update-$(date '+%Y%m%d%H%M%S').json"
        echo "$container_data" > "$backup_file"
        log "debug" "Container configuration backed up to $backup_file"
        
        # Stop the container
        log "info" "Stopping container $container_name"
        if ! docker stop "$container_name"; then
            log "error" "Failed to stop container $container_name. Skipping update."
            continue
        fi
        
        # Generate docker run command using the container's existing configuration
        create_command="docker create"
        
        # Basic container settings
        create_command="$create_command --name \"$container_name\""
        
        # Network settings
        network_modes=$(echo "$container_data" | jq -r '.network | keys[]')
        for network in $network_modes; do
            # Skip default bridge if container connects to other networks
            if [ "$network" == "bridge" ] && [ $(echo "$network_modes" | wc -l) -gt 1 ]; then
                continue
            fi
            create_command="$create_command --network=\"$network\""
            
            # If container has specific IP in this network, add it
            network_ip=$(echo "$container_data" | jq -r --arg net "$network" '.network[$net].IPAddress')
            if [ -n "$network_ip" ] && [ "$network_ip" != "null" ] && [ "$network_ip" != "" ]; then
                create_command="$create_command --ip=\"$network_ip\""
            fi
        done
        
        # Port mappings
        ports=$(echo "$container_data" | jq -r '.ports | keys[]')
        for port in $ports; do
            if [ "$port" != "null" ]; then
                host_bindings=$(echo "$container_data" | jq -r --arg port "$port" '.ports[$port] | if . == null then [] else . end | .[] | "\(.HostIp):\(.HostPort)"')
                for binding in $host_bindings; do
                    container_port=$(echo "$port" | cut -d'/' -f1)
                    protocol=$(echo "$port" | cut -d'/' -f2)
                    if [ "$binding" == ":" ]; then
                        create_command="$create_command -p $container_port/$protocol"
                    else
                        create_command="$create_command -p $binding:$container_port/$protocol"
                    fi
                done
            fi
        done
        
        # Volume mounts
        volumes=$(echo "$container_data" | jq -r '.mounts[] | "\(.Source):\(.Destination):\(.Mode)"')
        for volume in $volumes; do
            create_command="$create_command -v \"$volume\""
        done
        
        # Environment variables
        env_vars=$(echo "$container_data" | jq -r '.env[] | @sh')
        for env_var in $env_vars; do
            create_command="$create_command -e $env_var"
        done
        
        # Labels
        labels=$(echo "$container_data" | jq -r '.labels | to_entries[] | "\(.key)=\(.value)"')
        for label in $labels; do
            create_command="$create_command --label \"$label\""
        done
        
        # Restart policy
        restart_policy=$(echo "$container_data" | jq -r '.restartPolicy.Name')
        if [ "$restart_policy" != "null" ] && [ "$restart_policy" != "no" ]; then
            max_retry=$(echo "$container_data" | jq -r '.restartPolicy.MaximumRetryCount')
            if [ "$max_retry" != "0" ] && [ "$restart_policy" == "on-failure" ]; then
                create_command="$create_command --restart=\"$restart_policy:$max_retry\""
            else
                create_command="$create_command --restart=\"$restart_policy\""
            fi
        fi
        
        # Advanced host configs
        privileged=$(echo "$container_data" | jq -r '.hostConfig.privileged')
        if [ "$privileged" == "true" ]; then
            create_command="$create_command --privileged"
        fi
        
        # Capabilities
        cap_add=$(echo "$container_data" | jq -r '.hostConfig.capAdd | .[]?')
        for cap in $cap_add; do
            create_command="$create_command --cap-add=\"$cap\""
        done
        
        cap_drop=$(echo "$container_data" | jq -r '.hostConfig.capDrop | .[]?')
        for cap in $cap_drop; do
            create_command="$create_command --cap-drop=\"$cap\""
        done
        
        # DNS settings
        dns_servers=$(echo "$container_data" | jq -r '.hostConfig.dns | .[]?')
        for dns in $dns_servers; do
            create_command="$create_command --dns=\"$dns\""
        done
        
        dns_search=$(echo "$container_data" | jq -r '.hostConfig.dnsSearch | .[]?')
        for dns in $dns_search; do
            create_command="$create_command --dns-search=\"$dns\""
        done
        
        # Extra hosts
        extra_hosts=$(echo "$container_data" | jq -r '.hostConfig.extraHosts | .[]?')
        for host in $extra_hosts; do
            create_command="$create_command --add-host=\"$host\""
        done
        
        # Log configuration
        log_driver=$(echo "$container_data" | jq -r '.hostConfig.logConfig.Type')
        if [ "$log_driver" != "null" ] && [ "$log_driver" != "json-file" ]; then
            create_command="$create_command --log-driver=\"$log_driver\""
            
            log_opts=$(echo "$container_data" | jq -r '.hostConfig.logConfig.Config | to_entries[] | "\(.key)=\(.value)"')
            for opt in $log_opts; do
                create_command="$create_command --log-opt=\"$opt\""
            done
        fi
        
        # Add image name
        create_command="$create_command \"$image_name\""
        
        # Add command/entrypoint if specified
        cmd=$(echo "$container_data" | jq -r '.command | .[]?')
        if [ -n "$cmd" ]; then
            for arg in $cmd; do
                create_command="$create_command $arg"
            done
        fi
        
        # Remove the old container but keep volumes
        log "info" "Removing container $container_name (keeping volumes)"
        if ! docker rm "$container_name"; then
            log "error" "Failed to remove container $container_name. Skipping update."
            continue
        fi
        
        # Create the new container
        log "info" "Creating new container with command: $create_command"
        container_id=""
        if ! container_id=$(eval "$create_command"); then
            log "error" "Failed to create new container $container_name. Command: $create_command"
            continue
        fi
         # Start the container
        log "info" "Starting container $container_name"
        if ! docker start "$container_id"; then
            log "error" "Failed to start container $container_name. Skipping update."
            continue
        fi

        log "info" "Container $container_name successfully updated to image $new_image_id"
        
        # Clean up old image if enabled
        if [ "$CLEANUP_OLD_IMAGES" = "true" ]; then
            log "info" "Cleaning up old image: $current_image_id"
            if docker rmi "$current_image_id" 2>/dev/null; then
                log "info" "Successfully removed old image $current_image_id"
            else
                log "warn" "Could not remove old image $current_image_id (may be in use by other containers)"
            fi
        fi
    done
    
    # Update inventory after updates
    document_containers
}

# Main execution loop
while true; do
    # Document all containers on startup and after each update cycle
    document_containers
    
    # Run the update check
    update_containers
    
    log "info" "Sleeping for $UPDATE_INTERVAL seconds until next update check"
    sleep "$UPDATE_INTERVAL"
done