# Docker Configuration Guide

## Environment Variables

This application is designed to be configured through environment variables rather than embedding configuration files in the Docker image. This approach provides better security and flexibility.

### Why Not Copy .env Into the Image?

- **Security**: Sensitive data (like secrets, passwords) should not be baked into Docker images
- **Flexibility**: Different environments (dev, staging, prod) can use the same image with different configs
- **Best Practices**: Images should be environment-agnostic and configurable at runtime

## Configuration Methods

### Method 1: Using .env File (Development)

1. Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your actual values:
   ```bash
   # Security (change these!)
   SESSION_SECRET=your-strong-session-secret
   JWT_SECRET=your-strong-jwt-secret
   WEBHOOK_SECRET=your-webhook-secret
   ADMIN_PASSWORD=your-strong-password
   ```

3. Run with docker-compose (automatically picks up .env):
   ```bash
   docker-compose up -d
   ```

### Method 2: Environment Variables in docker-compose.yml

Edit the `environment` section in your docker-compose file:

```yaml
environment:
  - SESSION_SECRET=your-strong-session-secret
  - JWT_SECRET=your-strong-jwt-secret
  - WEBHOOK_SECRET=your-webhook-secret
  - ADMIN_PASSWORD=your-strong-password
```

### Method 3: Docker Run with Environment Variables

```bash
docker run -d \
  --name containerpulse \
  -p 3000:3000 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -e SESSION_SECRET="your-strong-session-secret" \
  -e JWT_SECRET="your-strong-jwt-secret" \
  -e WEBHOOK_SECRET="your-webhook-secret" \
  -e ADMIN_PASSWORD="your-strong-password" \
  containerpulse:latest
```

### Method 4: Environment File with Docker Run

```bash
docker run -d \
  --name containerpulse \
  -p 3000:3000 \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  --env-file .env \
  containerpulse:latest
```

## Required Environment Variables

| Variable | Description | Required | Default |
|----------|-------------|----------|---------|
| `SESSION_SECRET` | Session encryption secret | Yes | None |
| `JWT_SECRET` | JWT token secret | Yes | None |
| `WEBHOOK_SECRET` | Webhook authentication secret | Yes | None |
| `ADMIN_PASSWORD` | Admin user password | Yes | None |
| `ADMIN_USERNAME` | Admin username | No | `admin` |
| `PORT` | Web interface port | No | `3000` |
| `UPDATE_INTERVAL` | Update check interval (seconds) | No | `86400` |
| `LOG_LEVEL` | Logging level | No | `info` |

## Security Best Practices

1. **Never commit .env files** - They're excluded in .gitignore
2. **Use strong secrets** - Generate random strings for SESSION_SECRET and JWT_SECRET
3. **Change default passwords** - Don't use default admin passwords in production
4. **Rotate secrets regularly** - Update secrets periodically
5. **Use environment-specific values** - Different secrets for dev/staging/prod

## Building and Running

### Development
```bash
docker-compose up -d
```

### Production
```bash
docker-compose -f docker-compose.prod.yml up -d
```

### Build Only
```bash
docker build -t containerpulse:latest .
```

## Troubleshooting

### Missing Environment Variables
If you see errors about missing environment variables:
1. Check that your .env file exists and has the required variables
2. Verify the .env file is in the same directory as docker-compose.yml
3. Ensure environment variables are properly set if not using .env file

### Permission Issues
If you get Docker permission errors:
```bash
# Add your user to docker group (Linux)
sudo usermod -aG docker $USER
# Then logout and login again
```

### Health Check
Check if the container is running properly:
```bash
docker logs containerpulse
curl http://localhost:3000/health
```
