# ContainerPulse
Monitor and manage your Docker containers with real-time updates and intelligent automation.

## Features
- **Real-time Container Monitoring:** Track all running containers with live status updates
- **Intelligent Update Detection:** Automatically detect when new container images are available
- **Safe Container Updates:** Only updates containers with specified labels, ensuring proper recreation with all original parameters
- **Modern Web Dashboard:** Intuitive interface for monitoring container health and managing updates
- **Webhook Integration:** RESTful endpoints for external systems (DockerHub, GitHub, GitLab) to trigger updates
- **Secure Authentication:** Protected login system and webhook authentication
- **Watchtower Compatible:** Works with existing Watchtower labels for seamless migration
- **Container History:** Maintains backup history of containers before updates
- **Configurable Monitoring:** Set update intervals and logging levels through environment variables
- **Hot Reloading:** Development mode with automatic code reloading

## Getting Started

### Quick Start
1. Create a directory for ContainerPulse:
   ```bash
   mkdir -p containerpulse && cd containerpulse
   ```
2. Create the necessary files:
   ```bash   # Create the script
   cat > containerpulse-updater.sh << 'EOF'
   # Paste the contents of the containerpulse-script.sh here
   EOF

   # Create the Dockerfile
   cat > Dockerfile << 'EOF'
   # Paste the contents of the Dockerfile here
   EOF

   # Create docker-compose.yml
   cat > docker-compose.yml << 'EOF'
   # Paste the contents of the docker-compose.yml here
   EOF
   ```
3. Make the script executable:
   ```bash
   chmod +x containerpulse-updater.sh
   ```
4. Build and run the container:
   ```bash
   # For development (with hot reloading)
   docker-compose up -d
   
   # For production
   docker-compose -f docker-compose.prod.yml up -d
   ```

## Web Interface

The Docker Auto-Updater includes a modern web interface accessible at `http://localhost:3000`.

### Default Login
- **Username:** admin
- **Password:** admin123 (change this!)

### Features
- **Dashboard:** View all containers with auto-update labels
- **Update Status:** See which containers have updates available
- **Manual Updates:** Trigger updates for individual containers
- **Webhook URLs:** Get webhook endpoints for each container
- **Real-time Status:** Auto-refreshing container status

### Development Mode
For development with hot reloading:
```bash
docker-compose up -d
```

Changes to the source code will automatically reload the web interface.

## Configuration Options
Configure the updater by modifying the environment variables in your `docker-compose.yml`:

| Variable         | Description                        | Default      |
|------------------|------------------------------------|--------------|
| UPDATE_INTERVAL  | Time between update checks (secs)  | 86400 (1 day)|
| LOG_LEVEL        | Logging verbosity                  | info         |

## Enabling Auto-Updates for Your Containers
Add any of these labels to your containers to enable automatic updates:

```yaml
labels:
  - "auto-update=true"
  # OR
  - "com.your.auto-update=true"
  # OR (for Watchtower compatibility)
  - "com.github.containrrr.watchtower.enable=true"
  - "com.centurylinklabs.watchtower.enable=true"
```

Example Docker Compose service with auto-update enabled:

```yaml
services:
  my-service:
    image: nginx:latest
    restart: unless-stopped
    labels:
      - "auto-update=true"
```

## Monitoring and Management

### Viewing Logs
```bash
# View container logs
docker logs containerpulse

# Follow logs in real-time
docker logs -f containerpulse
```

### Accessing Container Inventory
The container inventory is stored in the `containerpulse-data` volume. You can explore it by:

```bash
# Create a temporary container to view the data
docker run --rm -it -v containerpulse-data:/data alpine:latest sh -c "cat /data/container-inventory/inventory.json | jq"
```

### Manually Triggering Updates
```bash
# Run update check immediately
docker exec containerpulse kill -USR1 1
```

## How It Works

### Documentation Phase:
- On startup, the updater documents all running containers
- Creates a detailed JSON inventory of container parameters
- Stores full container inspections for reference

### Update Phase:
- Checks for containers with auto-update labels
- Pulls the latest image for each labeled container
- If a new image is available, backs up the container configuration
- Recreates the container with identical parameters using the new image
- Updates the inventory after completion

### Sleep Phase:
- Waits for the configured interval before checking again

## Migration from Watchtower
To migrate from Watchtower:

1. Ensure your containers have either:
   - The standard Watchtower labels: `com.github.containrrr.watchtower.enable=true`
   - Or the new ContainerPulse label: `auto-update=true`
2. Stop and remove your Watchtower container
3. Deploy ContainerPulse as described above

## Limitations
- Currently doesn't support custom per-container update intervals
- Doesn't handle Docker Swarm services (only standalone containers)
- Cannot update itself while running (will update on next container restart)

## Advanced Usage

### Custom Network Configuration
If you need to place ContainerPulse in specific networks:

```yaml
services:
  containerpulse:
    # ... other configuration ...
    networks:
      - your-network-name

networks:
  your-network-name:
    external: true
```

### Notification Integration
For notifications on updates, you can modify the script to integrate with services like Discord, Slack, or email by adding HTTP requests at appropriate points in the update process.

## Webhook Integration

The Docker Auto-Updater provides webhook endpoints for external systems to trigger container updates.

### Webhook Endpoints

Each container with an auto-update label gets its own webhook endpoint:
```
POST http://your-server:3000/webhook/{container-name}
```

### Authentication Methods

The webhook system supports multiple authentication methods:

#### 1. Bearer Token (JWT)
```bash
curl -X POST \
  -H "Authorization: Bearer your-jwt-token" \
  -H "Content-Type: application/json" \
  -d '{"repository":"nginx","tag":"latest"}' \
  http://localhost:3000/webhook/my-container
```

#### 2. Simple Token
```bash
curl -X POST \
  -H "X-Webhook-Token: your-webhook-secret" \
  -H "Content-Type: application/json" \
  -d '{"repository":"nginx","tag":"latest"}' \
  http://localhost:3000/webhook/my-container
```

#### 3. GitHub/GitLab Style Signature
```bash
curl -X POST \
  -H "X-Hub-Signature-256: sha256=signature" \
  -H "Content-Type: application/json" \
  -d '{"repository":"nginx","tag":"latest"}' \
  http://localhost:3000/webhook/my-container
```

### DockerHub Integration

Configure DockerHub to send webhooks to your endpoints:

1. Go to your DockerHub repository
2. Navigate to "Webhooks" tab
3. Add webhook URL: `http://your-server:3000/webhook/{container-name}`
4. Set the webhook secret in your environment variables

### GitHub Container Registry

For GitHub Container Registry, set up a webhook in your repository:

1. Go to repository Settings → Webhooks
2. Add webhook URL: `http://your-server:3000/webhook/{container-name}`
3. Select "Package" events
4. Configure the secret

### Environment Variables for Webhooks

```bash
WEBHOOK_SECRET=your-webhook-secret-for-external-calls
JWT_SECRET=your-jwt-secret-for-tokens
SESSION_SECRET=your-session-secret
```

## GitHub Actions & CI/CD

ContainerPulse includes automated GitHub workflows for building, testing, and deploying Docker images.

### Available Workflows

1. **GitHub Container Registry (GHCR) - Recommended**
   - Automatically builds and pushes to `ghcr.io` on every push to main/master
   - No additional setup required - uses GitHub token automatically
   - Supports multi-architecture builds (amd64, arm64)
   - Path: `.github/workflows/docker-build-push.yml`

2. **Docker Hub**
   - Builds and pushes to Docker Hub
   - Requires Docker Hub credentials setup
   - Path: `.github/workflows/docker-hub-push.yml`

3. **Security Scanning**
   - Weekly vulnerability scans using Trivy
   - Scans on every push and pull request
   - Results uploaded to GitHub Security tab
   - Path: `.github/workflows/security-scan.yml`

### Setup Instructions

#### For GitHub Container Registry (No setup needed)
The GHCR workflow works out of the box. Your images will be available at:
```
ghcr.io/yourusername/containerpulse:latest
```

#### For Docker Hub (Optional)
1. Create a Docker Hub account and repository
2. Generate a Docker Hub access token
3. Add these secrets to your GitHub repository:
   - `DOCKERHUB_USERNAME`: Your Docker Hub username
   - `DOCKERHUB_TOKEN`: Your Docker Hub access token

#### Setting up GitHub Secrets
1. Go to your repository on GitHub
2. Click "Settings" → "Secrets and variables" → "Actions"
3. Click "New repository secret"
4. Add the required secrets

### Using the Published Images

#### From GitHub Container Registry:
```bash
docker pull ghcr.io/yourusername/containerpulse:latest
```

#### From Docker Hub:
```bash
docker pull yourusername/containerpulse:latest
```

#### In docker-compose.yml:
```yaml
services:
  containerpulse:
    image: ghcr.io/yourusername/containerpulse:latest
    # ... rest of configuration
```

## Project Structure and Development

### File Organization
```
containerpulse/
├── .github/
│   └── workflows/                    # GitHub Actions workflows
│       ├── docker-build-push.yml    # GHCR build and push
│       ├── docker-hub-push.yml      # Docker Hub build and push
│       └── security-scan.yml        # Security vulnerability scanning
├── src/
│   └── web/                         # Web application
│       ├── server.js                # Express.js server
│       ├── public/                  # Static assets
│       ├── services/                # Business logic
│       └── views/                   # EJS templates
├── .gitignore                       # Git ignore rules
├── .dockerignore                    # Docker ignore rules
├── containerpulse-updater.sh        # Main container update script
├── docker-compose.yml               # Development configuration
├── docker-compose.prod.yml          # Production configuration
├── Dockerfile                       # Production image
├── Dockerfile.dev                   # Development image
├── startup.sh                       # Container startup script
├── startup-dev.sh                   # Development startup script
└── package.json                     # Node.js dependencies
```

### Development Setup
```bash
# Clone the repository
git clone <your-repo-url>
cd containerpulse

# Install dependencies
npm install

# Run in development mode
docker-compose up -d

# View logs
docker-compose logs -f
```

### Important Files
- **`.gitignore`**: Prevents sensitive data, logs, and dependencies from being committed
- **`.dockerignore`**: Optimizes Docker builds by excluding unnecessary files
- **Environment variables**: Store sensitive configuration in `.env` (never commit this file)

### Security Considerations
- Never commit `.env` files containing secrets
- Use GitHub secrets for CI/CD credentials
- Regularly update dependencies and base images
- Monitor security scan results in GitHub Security tab
