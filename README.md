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

Configure ContainerPulse by modifying the environment variables in your `docker-compose.yml`:

### Core Settings

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `NODE_ENV` | Application environment | `development` | `development`, `production` |
| `UPDATE_INTERVAL` | Time between update checks (seconds) | `300` (5 min) | Any positive integer |
| `LOG_LEVEL` | Logging verbosity | `debug` | `debug`, `info`, `warn`, `error` |
| `PORT` | Web interface port | `3000` | Any valid port number |
| `CLEANUP_OLD_IMAGES` | Remove old images after updates | `false` | `true`, `false` |

### Security Settings

| Variable | Description | Default | Notes |
|----------|-------------|---------|-------|
| `SESSION_SECRET` | Session encryption key | `dev-session-secret-change-in-production` | **Change in production!** |
| `JWT_SECRET` | JWT token encryption key | `dev-jwt-secret-change-in-production` | **Change in production!** |
| `WEBHOOK_SECRET` | Webhook authentication secret | `dev-webhook-secret` | Used for external webhook calls |
| `ADMIN_USERNAME` | Web interface admin username | `admin` | Change for security |
| `ADMIN_PASSWORD` | Web interface admin password | `admin123` | **Change in production!** |

### Email Notification Settings

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `EMAIL_ENABLED` | Enable email notifications | `false` | `true`, `false` |
| `EMAIL_TO` | Recipient email address | (empty) | `admin@example.com` |
| `EMAIL_FROM` | Sender email address | `containerpulse@localhost` | `noreply@company.com` |
| `EMAIL_SUBJECT` | Email subject template | `ContainerPulse Container Update Available` | Custom subject |
| `SMTP_SERVER` | SMTP server hostname | (empty) | `smtp.gmail.com`, `smtp.office365.com` |
| `SMTP_PORT` | SMTP server port | `587` | `587` (STARTTLS), `465` (SSL), `25` (plain) |
| `SMTP_USER` | SMTP username | (empty) | `user@gmail.com` |
| `SMTP_PASSWORD` | SMTP password | (empty) | App password or account password |

## Container Labels and Update Approaches

ContainerPulse supports multiple labeling strategies for maximum compatibility and flexibility.

### Basic Auto-Update Labels

Add any of these labels to enable automatic updates:

```yaml
labels:
  - "auto-update=true"
  # OR for namespaced approach
  - "com.containerpulse.auto-update=true"
  # OR for Watchtower compatibility
  - "com.github.containrrr.watchtower.enable=true"
  - "com.centurylinklabs.watchtower.enable=true"
```

### Update Approach Labels

Control how updates are handled with the `update-approach` label:

#### Automatic Updates (Default)
```yaml
labels:
  - "auto-update=true"
  - "update-approach=auto"  # Optional - this is the default
```
- Containers are automatically updated when new images are available
- No manual intervention required

#### Notification Only
```yaml
labels:
  - "auto-update=true"
  - "update-approach=notify"
```
- ContainerPulse detects updates but doesn't apply them automatically
- Sends email notifications when updates are available
- Requires manual update through web interface or webhook

### Complete Docker Compose Examples

#### Example 1: Web Server with Auto-Updates
```yaml
services:
  nginx-app:
    image: nginx:latest
    restart: unless-stopped
    ports:
      - "80:80"
    labels:
      - "auto-update=true"
      - "update-approach=auto"
    volumes:
      - ./html:/usr/share/nginx/html:ro
```

#### Example 2: Database with Notification-Only Updates
```yaml
services:
  postgres-db:
    image: postgres:15
    restart: unless-stopped
    environment:
      POSTGRES_DB: myapp
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
    labels:
      - "auto-update=true"
      - "update-approach=notify"  # Only notify, don't auto-update
    volumes:
      - postgres-data:/var/lib/postgresql/data
```

#### Example 3: Application with Custom Labels
```yaml
services:
  my-app:
    image: myregistry.com/myapp:latest
    restart: unless-stopped
    labels:
      - "com.containerpulse.auto-update=true"
      - "com.containerpulse.update-approach=auto"
      - "com.containerpulse.description=My awesome application"
```

## Email Notification Setup

### Gmail Configuration
```yaml
environment:
  - EMAIL_ENABLED=true
  - EMAIL_TO=admin@company.com
  - EMAIL_FROM=containerpulse@company.com
  - SMTP_SERVER=smtp.gmail.com
  - SMTP_PORT=587
  - SMTP_USER=your-gmail@gmail.com
  - SMTP_PASSWORD=your-app-password  # Use App Password, not account password
```

### Office 365 Configuration
```yaml
environment:
  - EMAIL_ENABLED=true
  - EMAIL_TO=admin@company.com
  - EMAIL_FROM=containerpulse@company.com
  - SMTP_SERVER=smtp.office365.com
  - SMTP_PORT=587
  - SMTP_USER=your-email@company.com
  - SMTP_PASSWORD=your-password
```

### Custom SMTP Server Configuration
```yaml
environment:
  - EMAIL_ENABLED=true
  - EMAIL_TO=admin@company.com
  - EMAIL_FROM=containerpulse@company.com
  - SMTP_SERVER=mail.company.com
  - SMTP_PORT=587
  - SMTP_USER=containerpulse@company.com
  - SMTP_PASSWORD=smtp-password
```

### Email Notification Triggers

Email notifications are sent when:
1. **Update Available**: A container with `update-approach=notify` has an available update
2. **Update Success**: A container was successfully updated (if enabled)
3. **Update Failure**: A container update failed (always sent if email is enabled)

### Email Content Example

```
Subject: ContainerPulse Container Update Available

Container Update Notification
============================

Container: nginx-app
Current Image: nginx:1.20
Available Update: nginx:latest
Update Approach: notify

A new version is available for this container. 
Log into the ContainerPulse dashboard to review and apply the update.

Dashboard: http://your-server:3000
Container Details: http://your-server:3000/containers/nginx-app

This is an automated message from ContainerPulse.
```

### Email Troubleshooting

#### Gmail Setup Issues
1. **Enable 2-Factor Authentication** on your Google account
2. **Generate an App Password**: Go to Google Account Settings → Security → App passwords
3. **Use the App Password** in `SMTP_PASSWORD`, not your account password
4. **Check Less Secure Apps**: If not using 2FA, you may need to enable "Less secure app access"

#### Common SMTP Issues
- **Port 587**: Use with STARTTLS (most common)
- **Port 465**: Use with SSL/TLS
- **Port 25**: Usually blocked by ISPs
- **Authentication**: Ensure username/password are correct
- **Firewall**: Check that outbound SMTP ports are not blocked

#### Testing Email Configuration
```bash
# Check if emails are being sent (look for SMTP logs)
docker-compose logs containerpulse | grep -i smtp

# Test with a container that has notify approach
docker run -d --name test-notify --label "auto-update=true" --label "update-approach=notify" nginx:1.20
```

#### Email Logs
Enable debug logging to see detailed email information:
```yaml
environment:
  - LOG_LEVEL=debug
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

## Production Configuration

### Production Environment File (.env)

Create a `.env` file in your project directory with production values:

```bash
# Core Settings
NODE_ENV=production
UPDATE_INTERVAL=86400  # Check once daily in production
LOG_LEVEL=info
PORT=3000

# Security Settings (CHANGE THESE!)
SESSION_SECRET=your-very-long-random-session-secret-here
JWT_SECRET=your-very-long-random-jwt-secret-here
WEBHOOK_SECRET=your-webhook-secret-for-external-systems
ADMIN_USERNAME=your-admin-username
ADMIN_PASSWORD=your-secure-admin-password

# Email Configuration
EMAIL_ENABLED=true
EMAIL_TO=admin@yourcompany.com
EMAIL_FROM=containerpulse@yourcompany.com
EMAIL_SUBJECT=ContainerPulse: Container Update Available
SMTP_SERVER=smtp.yourcompany.com
SMTP_PORT=587
SMTP_USER=containerpulse@yourcompany.com
SMTP_PASSWORD=your-smtp-password

# Image Management
CLEANUP_OLD_IMAGES=true  # Clean up old images in production
```

### Production Docker Compose

```yaml
services:
  containerpulse:
    image: containerpulse:latest  # Use a specific tag in production
    container_name: containerpulse
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - containerpulse-data:/var/lib/containerpulse
      - containerpulse-logs:/var/log/containerpulse
    env_file:
      - .env  # Load environment variables from file
    labels:
      - "auto-update=true"
    # Security: Run as non-root user (optional)
    # user: "1000:1000"
    
    # Resource limits (optional)
    deploy:
      resources:
        limits:
          memory: 256M
          cpus: '0.5'
        reservations:
          memory: 128M
          cpus: '0.1'

volumes:
  containerpulse-data:
  containerpulse-logs:
```

### Security Best Practices

1. **Change Default Credentials**: Always change default usernames and passwords
2. **Use Strong Secrets**: Generate long, random strings for all secret environment variables
3. **Secure .env Files**: Never commit `.env` files to version control
4. **Network Security**: Consider placing ContainerPulse in a private network
5. **Resource Limits**: Set appropriate CPU and memory limits
6. **Regular Updates**: Keep the ContainerPulse image updated
7. **Log Monitoring**: Monitor logs for suspicious activity


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

## Quick Reference

### Essential Environment Variables
```bash
# Production Essentials
NODE_ENV=production
SESSION_SECRET=your-random-secret
JWT_SECRET=your-jwt-secret
ADMIN_PASSWORD=your-secure-password

# Email Notifications
EMAIL_ENABLED=true
EMAIL_TO=admin@company.com
SMTP_SERVER=smtp.gmail.com
SMTP_USER=your-email@gmail.com
SMTP_PASSWORD=your-app-password
```

### Container Labels Cheat Sheet
```yaml
# Basic auto-update
labels:
  - "auto-update=true"

# Auto-update with immediate application
labels:
  - "auto-update=true"
  - "update-approach=auto"

# Update detection with email notification only
labels:
  - "auto-update=true"
  - "update-approach=notify"

# Watchtower compatibility
labels:
  - "com.github.containrrr.watchtower.enable=true"
```

### Common Commands
```bash
# Build and start
docker-compose up -d --build

# View logs
docker-compose logs -f containerpulse

# Restart service
docker-compose restart containerpulse

# Force update check
docker exec containerpulse kill -USR1 1

# View container inventory
docker exec containerpulse cat /var/lib/containerpulse/container-inventory/inventory.json
```
