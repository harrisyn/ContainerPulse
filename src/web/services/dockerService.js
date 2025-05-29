const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');
const Docker = require('dockerode');

const execAsync = promisify(exec);

// Try different Docker socket paths for better compatibility
let docker;
try {
    // First try the standard Unix socket
    docker = new Docker({ socketPath: '/var/run/docker.sock' });
} catch (error) {
    console.warn('Failed to connect to /var/run/docker.sock, trying alternative methods...');
    try {
        // Try with default settings (for Docker Desktop on Windows)
        docker = new Docker();
    } catch (fallbackError) {
        console.error('Failed to initialize Docker connection:', fallbackError);
        throw new Error('Unable to connect to Docker daemon. Ensure Docker is running and accessible.');
    }
}

const INVENTORY_FILE = process.env.INVENTORY_FILE || '/var/lib/containerpulse/container-inventory/inventory.json';
const UPDATE_SCRIPT = '/usr/local/bin/containerpulse-updater.sh';

class DockerService {
    async listContainers(options = {}) {
        try {
            const containers = await docker.listContainers({
                all: options.all || false,
                filters: options.filters || {}
            });
            return containers;
        } catch (error) {
            console.error('Error listing containers:', error);
            throw error;
        }
    }

    async getContainer(id) {
        try {
            return docker.getContainer(id);
        } catch (error) {
            console.error(`Error getting container ${id}:`, error);
            throw error;
        }
    }

    async getContainersWithUpdateStatus() {
        try {
            const containers = await this.getInventoryContainers();
            const containersWithStatus = await Promise.all(
                containers.map(async (container) => {
                    const updateStatus = await this.checkImageUpdateStatus(container);
                    return {
                        ...container,
                        updateStatus
                    };
                })
            );
            
            return containersWithStatus;
        } catch (error) {
            console.error('Error getting containers with update status:', error);
            throw error;
        }
    }

    async getInventoryContainers() {
        try {
            if (!fs.existsSync(INVENTORY_FILE)) {
                return [];
            }
            
            const data = fs.readFileSync(INVENTORY_FILE, 'utf8');
            const containers = JSON.parse(data);
            
            return containers.map(container => ({
                id: container.id,
                name: container.name.replace(/^\//, ''), // Remove leading slash
                image: container.image,
                imageId: container.imageId,
                state: container.state,
                created: container.created,
                labels: container.labels || {},
                ports: container.ports || {},
                mounts: container.mounts || [],
                restartPolicy: container.restartPolicy || {}
            }));
        } catch (error) {
            console.error('Error reading inventory file:', error);
            return [];
        }
    }

    async checkImageUpdateStatus(container) {
        try {
            const { stdout: currentImageId } = await execAsync(
                `docker inspect --format '{{.Id}}' "${container.image}"`
            );
            
            const currentId = currentImageId.trim();
            
            // Check if this is a locally built image (Docker Compose or custom built)
            const isLocallyBuilt = this.isLocallyBuiltImage(container.image);
            
            if (isLocallyBuilt) {
                console.log(`Image ${container.image} appears to be locally built. Skipping update check.`);
                return {
                    currentImageId: currentId,
                    latestImageId: currentId,
                    updateAvailable: false,
                    isLocallyBuilt: true,
                    lastChecked: new Date().toISOString()
                };
            }
            
            // For registry images, pull latest to check for updates
            try {
                await execAsync(`docker pull "${container.image}"`);
                
                const { stdout: latestImageId } = await execAsync(
                    `docker inspect --format '{{.Id}}' "${container.image}"`
                );
                
                const latestId = latestImageId.trim();
                
                return {
                    currentImageId: currentId,
                    latestImageId: latestId,
                    updateAvailable: currentId !== latestId,
                    isLocallyBuilt: false,
                    lastChecked: new Date().toISOString()
                };
            } catch (pullError) {
                // Handle pull failures gracefully (image not found, auth issues, etc.)
                console.warn(`Failed to pull image ${container.image}: ${pullError.message}`);
                return {
                    currentImageId: currentId,
                    latestImageId: null,
                    updateAvailable: false,
                    error: `Cannot check updates: ${pullError.message}`,
                    lastChecked: new Date().toISOString()
                };
            }
        } catch (error) {
            console.error(`Error checking update status for ${container.name}:`, error);
            return {
                currentImageId: container.imageId,
                latestImageId: null,
                updateAvailable: false,
                error: error.message,
                lastChecked: new Date().toISOString()
            };
        }
    }

    async updateContainer(containerName) {
        try {
            console.log(`Triggering update for container: ${containerName}`);
            
            // Read the inventory to find the container
            const containers = await this.getInventoryContainers();
            const container = containers.find(c => c.name === containerName);
            
            if (!container) {
                throw new Error(`Container ${containerName} not found in inventory`);
            }
            
            // Check if container has auto-update label
            const hasUpdateLabel = this.hasAutoUpdateLabel(container.labels);
            if (!hasUpdateLabel) {
                throw new Error(`Container ${containerName} does not have auto-update label`);
            }
            
            // Pull the latest image
            const { stdout: pullOutput } = await execAsync(`docker pull "${container.image}"`);
            console.log(`Pull output for ${container.image}:`, pullOutput);
            
            // Get the new image ID
            const { stdout: newImageId } = await execAsync(
                `docker inspect --format '{{.Id}}' "${container.image}"`
            );
            
            // Check if update is needed
            if (newImageId.trim() === container.imageId) {
                return {
                    success: true,
                    message: 'No update needed - container is already running the latest image',
                    updated: false
                };
            }
            
            // Trigger the update by calling the update script
            const { stdout: updateOutput } = await execAsync(
                'cd /usr/local/bin && ./containerpulse-updater.sh update_single_container ' + containerName
            );
            
            return {
                success: true,
                message: `Container ${containerName} updated successfully`,
                updated: true,
                output: updateOutput
            };
        } catch (error) {
            console.error(`Error updating container ${containerName}:`, error);
            throw error;
        }
    }

    hasAutoUpdateLabel(labels) {
        if (!labels) return false;
        
        const updateLabels = [
            'auto-update',
            'com.your.auto-update',
            'com.github.containrrr.watchtower.enable',
            'com.centurylinklabs.watchtower.enable'
        ];
        
        return updateLabels.some(label => labels[label] === 'true');
    }

    async getDockerInfo() {
        try {
            const { stdout } = await execAsync('docker info --format "{{json .}}"');
            return JSON.parse(stdout);
        } catch (error) {
            console.error('Error getting Docker info:', error);
            throw error;
        }
    }

    async getContainerLogs(containerName, lines = 100) {
        try {
            const { stdout } = await execAsync(`docker logs --tail ${lines} "${containerName}"`);
            return stdout;
        } catch (error) {
            console.error(`Error getting logs for ${containerName}:`, error);
            throw error;
        }
    }

    async checkForUpdates(containerId) {
        try {
            console.log(`Checking updates for container: ${containerId}`);
            
            // Validate container ID format
            if (!containerId || containerId.length < 12) {
                throw new Error('Invalid container ID provided');
            }
            
            // Get container
            const container = await this.getContainer(containerId);
            const containerInfo = await container.inspect();
            console.log(`Container found: ${containerInfo.Name}, Image: ${containerInfo.Config.Image}`);
            
            // Get current image
            const currentImage = containerInfo.Config.Image;
            if (!currentImage) {
                throw new Error('Container has no image information');
            }
            
            // Check if this is a locally built image (Docker Compose generates names like "project_service")
            const isLocallyBuilt = currentImage.includes('_') || currentImage.includes('-') && !currentImage.includes('/');
            
            if (isLocallyBuilt) {
                console.log(`Image ${currentImage} appears to be locally built. Skipping update check.`);
                return {
                    containerId,
                    containerName: containerInfo.Name,
                    currentImage,
                    currentImageId: 'locally-built',
                    latestImageId: 'locally-built',
                    updateAvailable: false,
                    isLocallyBuilt: true,
                    message: 'This container uses a locally built image. No updates available from registry.',
                    checkedAt: new Date().toISOString()
                };
            }
            
            let currentImageInfo;
            try {
                currentImageInfo = await docker.getImage(currentImage).inspect();
            } catch (imageError) {
                console.error(`Error inspecting current image ${currentImage}:`, imageError);
                throw new Error(`Failed to inspect current image: ${currentImage}`);
            }
            
            console.log(`Current image ID: ${currentImageInfo.Id}`);
            
            // Only try to pull if it's a registry image (contains / or is a known registry format)
            if (!currentImage.includes('/') && !currentImage.match(/^[a-zA-Z0-9][a-zA-Z0-9_.-]*$/)) {
                console.log(`Image ${currentImage} doesn't appear to be from a registry. Skipping pull.`);
                return {
                    containerId,
                    containerName: containerInfo.Name,
                    currentImage,
                    currentImageId: currentImageInfo.Id,
                    latestImageId: currentImageInfo.Id,
                    updateAvailable: false,
                    isLocallyBuilt: true,
                    message: 'This image is not from a public registry. No updates available.',
                    checkedAt: new Date().toISOString()
                };
            }
            
            // Pull latest image with timeout
            try {
                console.log(`Pulling latest image: ${currentImage}`);
                const pullStream = await docker.pull(currentImage);
                
                // Wait for pull to complete with timeout
                await new Promise((resolve, reject) => {
                    const timeout = setTimeout(() => {
                        reject(new Error('Image pull timeout (60 seconds)'));
                    }, 60000);
                    
                    docker.modem.followProgress(pullStream, (err, output) => {
                        clearTimeout(timeout);
                        if (err) {
                            console.error('Pull error:', err);
                            reject(new Error(`Pull failed: ${err.message || err}`));
                        } else {
                            console.log('Pull completed successfully');
                            resolve(output);
                        }
                    });
                });
            } catch (pullError) {
                console.error(`Error pulling image ${currentImage}:`, pullError);
                
                // If it's a 404 or authentication error, treat as locally built
                if (pullError.statusCode === 404 || pullError.message.includes('pull access denied')) {
                    console.log(`Image ${currentImage} not found in registry. Treating as locally built.`);
                    return {
                        containerId,
                        containerName: containerInfo.Name,
                        currentImage,
                        currentImageId: currentImageInfo.Id,
                        latestImageId: currentImageInfo.Id,
                        updateAvailable: false,
                        isLocallyBuilt: true,
                        message: 'This image is not available in any public registry. Likely locally built.',
                        checkedAt: new Date().toISOString()
                    };
                }
                
                throw new Error(`Failed to pull latest image: ${pullError.message}`);
            }
            
            // Get latest image info
            let latestImageInfo;
            try {
                latestImageInfo = await docker.getImage(currentImage).inspect();
            } catch (latestImageError) {
                console.error(`Error inspecting latest image ${currentImage}:`, latestImageError);
                throw new Error(`Failed to inspect latest image: ${currentImage}`);
            }
            
            console.log(`Latest image ID: ${latestImageInfo.Id}`);
            
            // Compare digests to check if update is available
            const updateAvailable = currentImageInfo.Id !== latestImageInfo.Id;
            
            const result = {
                containerId,
                containerName: containerInfo.Name,
                currentImage,
                currentImageId: currentImageInfo.Id,
                latestImageId: latestImageInfo.Id,
                updateAvailable,
                isLocallyBuilt: false,
                checkedAt: new Date().toISOString()
            };
            
            console.log(`Update check completed for ${containerId}: ${updateAvailable ? 'Update available' : 'Up to date'}`);
            return result;
            
        } catch (error) {
            console.error(`Error checking updates for container ${containerId}:`, error);
            // Return a more detailed error response
            throw new Error(`Update check failed: ${error.message}`);
        }
    }

    async inspectContainer(containerId) {
        try {
            const container = await this.getContainer(containerId);
            return await container.inspect();
        } catch (error) {
            console.error(`Error inspecting container ${containerId}:`, error);
            throw error;
        }
    }

    // Test Docker daemon connectivity
    async testConnection() {
        try {
            await docker.ping();
            console.log('Docker daemon connection successful');
            return { connected: true, message: 'Docker daemon is accessible' };
        } catch (error) {
            console.error('Docker daemon connection failed:', error);
            return { connected: false, message: `Docker daemon not accessible: ${error.message}` };
        }
    }
}

// Create and export a single instance
const dockerService = new DockerService();
module.exports = dockerService;
