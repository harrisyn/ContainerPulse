const crypto = require('crypto');
const jwt = require('jsonwebtoken');

class WebhookService {
    constructor() {
        this.webhookSecret = process.env.WEBHOOK_SECRET || 'your-webhook-secret';
        this.jwtSecret = process.env.JWT_SECRET || 'your-jwt-secret';
    }

    // Middleware to authenticate webhook calls
    authenticateWebhook = (req, res, next) => {
        try {
            const authHeader = req.headers.authorization;
            const signature = req.headers['x-hub-signature-256'] || req.headers['x-signature'];
            const webhookToken = req.headers['x-webhook-token'];
            
            // Method 1: Bearer token (JWT)
            if (authHeader?.startsWith('Bearer ')) {
                const token = authHeader.substring(7);
                try {
                    const decoded = jwt.verify(token, this.jwtSecret);
                    req.webhookAuth = decoded;
                    return next();
                } catch (error) {
                    console.error('JWT verification failed:', error);
                    return res.status(401).json({ error: 'Invalid JWT token' });
                }
            }
            
            // Method 2: Simple webhook token
            if (webhookToken) {
                if (webhookToken === this.webhookSecret) {
                    req.webhookAuth = { method: 'token' };
                    return next();
                } else {
                    return res.status(401).json({ error: 'Invalid webhook token' });
                }
            }
            
            // Method 3: GitHub/GitLab style signature
            if (signature) {
                const body = JSON.stringify(req.body);
                const isValid = this.verifySignature(signature, body, this.webhookSecret);
                if (isValid) {
                    req.webhookAuth = { method: 'signature' };
                    return next();
                } else {
                    return res.status(401).json({ error: 'Invalid signature' });
                }
            }
            
            // Method 4: DockerHub style (no authentication, just log)
            // Allow unauthenticated requests but log them
            console.log('Unauthenticated webhook request from:', req.ip);
            req.webhookAuth = { method: 'none', ip: req.ip };
            return next();
            
        } catch (error) {
            console.error('Webhook authentication error:', error);
            return res.status(500).json({ error: 'Authentication failed' });
        }
    };

    verifySignature(signature, body, secret) {
        try {
            let expectedSignature;
            
            if (signature.startsWith('sha256=')) {
                // GitHub style
                const hmac = crypto.createHmac('sha256', secret);
                hmac.update(body, 'utf-8');
                expectedSignature = 'sha256=' + hmac.digest('hex');
            } else if (signature.startsWith('sha1=')) {
                // GitLab style
                const hmac = crypto.createHmac('sha1', secret);
                hmac.update(body, 'utf-8');
                expectedSignature = 'sha1=' + hmac.digest('hex');
            } else {
                return false;
            }
            
            return crypto.timingSafeEqual(
                Buffer.from(signature, 'utf-8'),
                Buffer.from(expectedSignature, 'utf-8')
            );
        } catch (error) {
            console.error('Signature verification error:', error);
            return false;
        }
    }

    generateWebhookToken(containerName, expiresIn = '30d') {
        try {
            const payload = {
                container: containerName,
                purpose: 'webhook',
                iat: Math.floor(Date.now() / 1000)
            };
            
            return jwt.sign(payload, this.jwtSecret, { expiresIn });
        } catch (error) {
            console.error('Token generation error:', error);
            throw error;
        }
    }

    parseDockerHubWebhook(body) {
        try {
            // DockerHub webhook format
            return {
                repository: body.repository?.name,
                tag: body.push_data?.tag,
                pushed_at: body.push_data?.pushed_at,
                pusher: body.push_data?.pusher
            };
        } catch (error) {
            console.error('DockerHub webhook parsing error:', error);
            return null;
        }
    }

    parseGitHubWebhook(body) {
        try {
            // GitHub webhook format (for container registry)
            return {
                repository: body.repository?.name,
                tag: body.package?.version,
                action: body.action,
                sender: body.sender?.login
            };
        } catch (error) {
            console.error('GitHub webhook parsing error:', error);
            return null;
        }
    }

    parseGitLabWebhook(body) {
        try {
            // GitLab webhook format
            return {
                repository: body.project?.name,
                tag: body.ref?.replace('refs/tags/', ''),
                action: body.event_name,
                user: body.user_name
            };
        } catch (error) {
            console.error('GitLab webhook parsing error:', error);
            return null;
        }
    }

    logWebhookCall(containerName, source, data, success) {
        const logEntry = {
            timestamp: new Date().toISOString(),
            container: containerName,
            source: source,
            data: data,
            success: success,
            ip: data.ip || 'unknown'
        };
        
        console.log('Webhook call:', JSON.stringify(logEntry, null, 2));
        
        // In a production environment, you might want to store this in a database
        // or write to a specific log file
    }
}

module.exports = new WebhookService();
