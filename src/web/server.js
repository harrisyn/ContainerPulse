const express = require('express');
const session = require('express-session');
const bcrypt = require('bcryptjs');
const bodyParser = require('body-parser');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const helmet = require('helmet');
const cors = require('cors');
require('dotenv').config();

const dockerService = require('./services/dockerService');
const authService = require('./services/authService');
const webhookService = require('./services/webhookService');

const app = express();
const PORT = process.env.PORT || 3000;

// Security middleware with adjusted CSP
app.use(helmet({
    contentSecurityPolicy: {
        directives: {
            defaultSrc: ["'self'"],
            scriptSrc: ["'self'", "'unsafe-inline'", "'unsafe-eval'", "https://cdnjs.cloudflare.com"],
            styleSrc: ["'self'", "'unsafe-inline'", "https:", "http:"],
            fontSrc: ["'self'", "https:", "http:", "data:"],
            imgSrc: ["'self'", "data:", "https:"],
            connectSrc: ["'self'"],
        },
    },
}));
app.use(cors());

// Serve static files from public directory with proper MIME types
app.use(express.static(path.join(__dirname, 'public'), {
    setHeaders: (res, path, stat) => {
        if (path.endsWith('.css')) {
            res.set('Content-Type', 'text/css');
        }
    }
}));

// Serve node_modules files
app.use('/node_modules', express.static(path.join(__dirname, '../../node_modules'), {
    setHeaders: (res, path, stat) => {
        if (path.endsWith('.js')) {
            res.set('Content-Type', 'application/javascript');
        }
    }
}));

// Body parsing middleware
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Session middleware
app.use(session({
    secret: process.env.SESSION_SECRET || 'your-secret-key',
    resave: false,
    saveUninitialized: false,
    cookie: {
        secure: false, // Set to true in production with HTTPS
        maxAge: 24 * 60 * 60 * 1000 // 24 hours
    }
}));

// View engine setup
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Static files
app.use('/static', express.static(path.join(__dirname, 'public')));

// Debug route to check file paths
app.get('/debug/paths', (req, res) => {
    const publicPath = path.join(__dirname, 'public');
    const cssPath = path.join(__dirname, 'public', 'css', 'output.css');
    const fileExists = fs.existsSync(cssPath);
    
    res.json({
        __dirname,
        publicPath,
        cssPath,
        fileExists,
        currentWorkingDir: process.cwd()
    });
});

// Health check endpoint (no authentication required)
app.get('/api/health', (req, res) => {
    try {
        const uptime = process.uptime();
        const memoryUsage = process.memoryUsage();
        
        res.json({
            status: 'healthy',
            timestamp: new Date().toISOString(),
            uptime: `${Math.floor(uptime / 60)} minutes`,
            memory: {
                used: Math.round(memoryUsage.heapUsed / 1024 / 1024) + ' MB',
                total: Math.round(memoryUsage.heapTotal / 1024 / 1024) + ' MB'
            },
            version: process.env.npm_package_version || 'unknown'
        });
    } catch (error) {
        res.status(500).json({
            status: 'unhealthy',
            error: error.message
        });
    }
});

// Middleware to check if user is authenticated
const requireAuth = (req, res, next) => {
    if (req.session && req.session.user) {
        return next();
    }
    // If it's an API request, return JSON error
    if (req.path.startsWith('/api/')) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    // For regular page requests, redirect to login
    res.redirect('/login');
};

// Routes
app.get('/', requireAuth, async (req, res) => {
    try {
        const containers = await dockerService.getContainersWithUpdateStatus();        res.render('dashboard', { 
            user: req.session.user,
            containers: containers,
            title: 'ContainerPulse - Container Monitoring Dashboard'
        });
    } catch (error) {
        console.error('Dashboard error:', error);        res.render('dashboard', { 
            user: req.session.user,
            containers: [],
            error: 'Failed to load container information',
            title: 'ContainerPulse - Container Monitoring Dashboard'
        });
    }
});

app.get('/login', (req, res) => {
    res.render('login', { title: 'Login - ContainerPulse' });
});

app.post('/login', async (req, res) => {
    const { username, password } = req.body;
    
    try {
        const user = await authService.authenticate(username, password);
        if (user) {
            req.session.user = user;
            res.redirect('/');
        } else {            res.render('login', { 
                error: 'Invalid username or password',
                title: 'Login - ContainerPulse'
            });
        }
    } catch (error) {
        console.error('Login error:', error);        res.render('login', { 
            error: 'Login failed. Please try again.',
            title: 'Login - ContainerPulse'
        });
    }
});

app.get('/logout', (req, res) => {
    req.session.destroy();
    res.redirect('/login');
});

// API Routes
app.get('/api/containers', requireAuth, async (req, res) => {
    try {
        const containers = await dockerService.getContainersWithUpdateStatus();
        res.json(containers);
    } catch (error) {
        console.error('API containers error:', error);
        res.status(500).json({ error: 'Failed to fetch containers' });
    }
});

app.post('/api/containers/:name/update', requireAuth, async (req, res) => {
    try {
        const { name } = req.params;
        const result = await dockerService.updateContainer(name);
        res.json({ success: true, message: `Container ${name} update initiated`, result });
    } catch (error) {
        console.error('Container update error:', error);
        res.status(500).json({ error: `Failed to update container ${req.params.name}` });
    }
});

app.post('/api/containers/:id/check-update', requireAuth, async (req, res) => {
    try {
        const containerId = req.params.id;
        const result = await dockerService.checkForUpdates(containerId);
        res.json(result);
    } catch (error) {
        console.error('Error checking for updates:', error);
        res.status(500).json({ error: error.message });
    }
});

app.get('/api/containers/:id/inspect', requireAuth, async (req, res) => {
    try {
        const containerId = req.params.id;
        const containerInfo = await dockerService.inspectContainer(containerId);
        res.json(containerInfo);
    } catch (error) {
        console.error('Error inspecting container:', error);
        res.status(500).json({ error: error.message });
    }
});

// Webhook endpoint for external triggers (DockerHub, GitHub, etc.)
app.post('/webhook/:containerName', webhookService.authenticateWebhook, async (req, res) => {
    try {
        const { containerName } = req.params;
        const { repository, tag } = req.body;
        
        console.log(`Webhook received for container: ${containerName}`);
        console.log(`Repository: ${repository}, Tag: ${tag}`);
        
        const result = await dockerService.updateContainer(containerName);
        res.json({ 
            success: true, 
            message: `Update triggered for ${containerName}`,
            result 
        });
    } catch (error) {
        console.error('Webhook error:', error);
        res.status(500).json({ error: 'Webhook processing failed' });
    }
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ 
        status: 'healthy', 
        timestamp: new Date().toISOString(),
        version: '1.0.0'
    });
});

// Error handling middleware
app.use((err, req, res, next) => {
    console.error('Unhandled error:', err);
    res.status(500).json({ error: 'Internal server error' });
});

// 404 handler
app.use((req, res) => {
    res.status(404).render('404', { title: '404 - Page Not Found' });
});

app.listen(PORT, () => {
    console.log(`ContainerPulse Web Interface running on port ${PORT}`);
    console.log(`Dashboard: http://localhost:${PORT}`);
    console.log(`Default login: admin/admin123 (change these!)`);
    console.log('🔥 Hot reloading is active - file changes will restart the server automatically!');
});

module.exports = app;
