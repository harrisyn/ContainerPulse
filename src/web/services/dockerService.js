const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const { promisify } = require('util');
const Docker = require('dockerode');

const execAsync = promisify(exec);
const docker = new Docker({ socketPath: '/var/run/docker.sock' });

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
            
            // Pull latest image to check for updates
            await execAsync(`docker pull "${container.image}"`);
            
            const { stdout: latestImageId } = await execAsync(
                `docker inspect --format '{{.Id}}' "${container.image}"`
            );
            
            const currentId = currentImageId.trim();
            const latestId = latestImageId.trim();
            
            return {
                currentImageId: currentId,
                latestImageId: latestId,
                updateAvailable: currentId !== latestId,
                lastChecked: new Date().toISOString()
            };
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
            const container = await this.getContainer(containerId);
            const containerInfo = await container.inspect();
            
            // Get current image
            const currentImage = containerInfo.Config.Image;
            const currentImageInfo = await docker.getImage(currentImage).inspect();
            
            // Pull latest image
            await docker.pull(currentImage);
            
            // Get latest image info
            const latestImageInfo = await docker.getImage(currentImage).inspect();
            
            // Compare digests to check if update is available
            const updateAvailable = currentImageInfo.Id !== latestImageInfo.Id;
            
            return {
                currentImageId: currentImageInfo.Id,
                latestImageId: latestImageInfo.Id,
                updateAvailable,
                checkedAt: new Date().toISOString()
            };
        } catch (error) {
            console.error(`Error checking updates for container ${containerId}:`, error);
            throw error;
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
}

// Create and export a single instance
const dockerService = new DockerService();
module.exports = dockerService;
