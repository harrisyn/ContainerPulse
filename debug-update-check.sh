#!/bin/bash
# Debug script for ContainerPulse update issues

echo "=== ContainerPulse Debug Script ==="
echo "Timestamp: $(date)"
echo ""

# Test 1: Check if Docker daemon is accessible
echo "1. Testing Docker daemon access..."
if docker info > /dev/null 2>&1; then
    echo "✅ Docker daemon is accessible"
    echo "   Docker version: $(docker --version)"
else
    echo "❌ Docker daemon is NOT accessible"
    echo "   Error: $(docker info 2>&1)"
    exit 1
fi
echo ""

# Test 2: Check Docker socket permissions
echo "2. Checking Docker socket permissions..."
if [ -S /var/run/docker.sock ]; then
    echo "✅ Docker socket exists: /var/run/docker.sock"
    ls -la /var/run/docker.sock
else
    echo "❌ Docker socket not found at /var/run/docker.sock"
fi
echo ""

# Test 3: List containers
echo "3. Testing container listing..."
CONTAINER_COUNT=$(docker ps -q | wc -l)
echo "✅ Found $CONTAINER_COUNT running containers"
if [ $CONTAINER_COUNT -gt 0 ]; then
    echo "   Running containers:"
    docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}"
fi
echo ""

# Test 4: Test API endpoint (if container ID provided)
if [ ! -z "$1" ]; then
    CONTAINER_ID="$1"
    echo "4. Testing update check for container: $CONTAINER_ID"
    
    # Check if container exists
    if docker inspect "$CONTAINER_ID" > /dev/null 2>&1; then
        echo "✅ Container $CONTAINER_ID exists"
        
        # Get container image
        IMAGE=$(docker inspect "$CONTAINER_ID" --format '{{.Config.Image}}')
        echo "   Container image: $IMAGE"
        
        # Test image pull
        echo "   Testing image pull..."
        if docker pull "$IMAGE" > /dev/null 2>&1; then
            echo "✅ Successfully pulled image: $IMAGE"
        else
            echo "❌ Failed to pull image: $IMAGE"
            echo "   Error: $(docker pull "$IMAGE" 2>&1)"
        fi
    else
        echo "❌ Container $CONTAINER_ID does not exist"
    fi
else
    echo "4. Skipping container-specific tests (no container ID provided)"
    echo "   Usage: $0 <container-id>"
fi
echo ""

# Test 5: Check ContainerPulse logs (if running in container)
echo "5. Checking ContainerPulse application status..."
if [ -f "/app/src/web/server.js" ]; then
    echo "✅ ContainerPulse application files found"
    if pgrep -f "node.*server.js" > /dev/null; then
        echo "✅ ContainerPulse web server is running"
    else
        echo "⚠️  ContainerPulse web server may not be running"
    fi
else
    echo "ℹ️  Not running inside ContainerPulse container"
fi

echo ""
echo "=== Debug Complete ==="
