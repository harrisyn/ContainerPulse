# ContainerPulse Features

## Container Update Management

ContainerPulse provides flexible container update management with two main approaches:

### 1. Automatic Updates (Default)
Containers are automatically updated when new images are available.

```yaml
services:
  myapp:
    image: nginx:latest
    labels:
      - "auto-update=true"  # Enable automatic updates
```

### 2. Notification-Only Updates
For critical containers where you want manual control, use the `update-approach=notify` label:

```yaml
services:
  database:
    image: postgres:15
    labels:
      - "auto-update=true"
      - "update-approach=notify"  # Send email notifications instead of auto-updating
```

## Email Notifications

Configure email notifications for containers with `update-approach=notify`:

### Environment Variables

```yaml
environment:
  # Email notification settings
  - EMAIL_ENABLED=true
  - EMAIL_TO=admin@company.com
  - EMAIL_FROM=containerpulse@yourserver.com
  - EMAIL_SUBJECT=Container Update Available
  
  # SMTP Configuration
  - SMTP_SERVER=smtp.gmail.com
  - SMTP_PORT=587
  - SMTP_USER=your-email@gmail.com
  - SMTP_PASSWORD=your-app-password
```

### Supported Email Methods

1. **Sendmail** - If available in the container
2. **SMTP** - Using curl with SMTP authentication
3. **Fallback** - Logs notification messages if no email method is available

## Image Cleanup

Automatically remove old Docker images after successful container updates:

```yaml
environment:
  - CLEANUP_OLD_IMAGES=true  # Remove old images after updates
```

**Note**: Old images are only removed if they're not being used by other containers.

## Configuration Examples

### Production Setup with Notifications
```yaml
services:
  containerpulse:
    image: containerpulse:latest
    environment:
      - UPDATE_INTERVAL=86400  # Check daily
      - CLEANUP_OLD_IMAGES=true
      - EMAIL_ENABLED=true
      - EMAIL_TO=admin@company.com
      - SMTP_SERVER=smtp.company.com
      - SMTP_USER=containerpulse@company.com
      - SMTP_PASSWORD=secure-password
    labels:
      - "auto-update=true"

  webapp:
    image: myapp:latest
    labels:
      - "auto-update=true"  # Auto-update enabled

  database:
    image: postgres:15
    labels:
      - "auto-update=true"
      - "update-approach=notify"  # Notify only, don't auto-update
```

### Development Setup
```yaml
services:
  containerpulse:
    build: .
    environment:
      - UPDATE_INTERVAL=300    # Check every 5 minutes
      - LOG_LEVEL=debug
      - CLEANUP_OLD_IMAGES=false  # Keep old images for debugging
      - EMAIL_ENABLED=false       # Disable email in dev
    labels:
      - "auto-update=true"
```

## Container Labels Reference

| Label | Values | Description |
|-------|--------|-------------|
| `auto-update` | `true`, `false` | Enable/disable automatic update checking |
| `update-approach` | `auto`, `notify` | `auto`: Update automatically, `notify`: Send email notification only |

## Environment Variables Reference

### Core Settings
| Variable | Default | Description |
|----------|---------|-------------|
| `UPDATE_INTERVAL` | `86400` | Update check interval in seconds |
| `LOG_LEVEL` | `info` | Log level: `debug`, `info`, `warn`, `error` |

### Image Management
| Variable | Default | Description |
|----------|---------|-------------|
| `CLEANUP_OLD_IMAGES` | `false` | Remove old images after successful updates |

### Email Notifications
| Variable | Default | Description |
|----------|---------|-------------|
| `EMAIL_ENABLED` | `false` | Enable email notifications |
| `EMAIL_TO` | - | Recipient email address |
| `EMAIL_FROM` | `containerpulse@localhost` | Sender email address |
| `EMAIL_SUBJECT` | `ContainerPulse Container Update Available` | Email subject |
| `SMTP_SERVER` | `localhost` | SMTP server hostname |
| `SMTP_PORT` | `587` | SMTP server port |
| `SMTP_USER` | - | SMTP username |
| `SMTP_PASSWORD` | - | SMTP password |

## Security Considerations

1. **Email Passwords**: Use app-specific passwords for Gmail and other providers
2. **SMTP SSL**: The system uses SSL/TLS for SMTP connections when available
3. **Sensitive Data**: Store SMTP credentials securely using Docker secrets in production
4. **Network Access**: Ensure the container can reach your SMTP server

## Troubleshooting

### Email Not Sending
1. Check container logs for email-related errors
2. Verify SMTP settings and credentials
3. Ensure firewall allows SMTP traffic
4. Test with `sendmail` if SMTP fails

### Images Not Cleaning Up
1. Verify `CLEANUP_OLD_IMAGES=true` is set
2. Check if old images are used by other containers
3. Review container logs for cleanup messages

### Notifications Not Working
1. Ensure container has `update-approach=notify` label
2. Verify `EMAIL_ENABLED=true` is set
3. Check email configuration settings
