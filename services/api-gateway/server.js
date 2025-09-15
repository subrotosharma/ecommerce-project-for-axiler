// API Gateway Service - services/api-gateway/server.js

const express = require('express');
const prometheus = require('prom-client');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');
const { createProxyMiddleware } = require('http-proxy-middleware');

const app = express();
const PORT = process.env.PORT || 8080;

// Prometheus metrics
const register = new prometheus.Registry();
prometheus.collectDefaultMetrics({ register });

const httpRequestDuration = new prometheus.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.1, 0.5, 1, 2, 5]
});
register.registerMetric(httpRequestDuration);

const httpRequestTotal = new prometheus.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status']
});
register.registerMetric(httpRequestTotal);

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('combined'));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use('/api', limiter);

// Request tracking middleware
app.use((req, res, next) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    httpRequestDuration
      .labels(req.method, req.route?.path || req.path, res.statusCode)
      .observe(duration);
    httpRequestTotal
      .labels(req.method, req.route?.path || req.path, res.statusCode)
      .inc();
  });
  
  next();
});

// Health checks
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/ready', async (req, res) => {
  try {
    // Check downstream services
    const checks = await Promise.all([
      checkService('product-service', process.env.PRODUCT_SERVICE_URL),
      checkService('order-service', process.env.ORDER_SERVICE_URL),
      checkService('user-service', process.env.USER_SERVICE_URL)
    ]);
    
    const allHealthy = checks.every(check => check.healthy);
    
    if (allHealthy) {
      res.json({ status: 'ready', services: checks });
    } else {
      res.status(503).json({ status: 'not ready', services: checks });
    }
  } catch (error) {
    res.status(503).json({ status: 'not ready', error: error.message });
  }
});

// Metrics endpoint
app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

// Service proxies
const services = {
  '/api/products': {
    target: process.env.PRODUCT_SERVICE_URL || 'http://product-service:8081',
    changeOrigin: true,
    pathRewrite: { '^/api/products': '' }
  },
  '/api/orders': {
    target: process.env.ORDER_SERVICE_URL || 'http://order-service:8082',
    changeOrigin: true,
    pathRewrite: { '^/api/orders': '' }
  },
  '/api/users': {
    target: process.env.USER_SERVICE_URL || 'http://user-service:8083',
    changeOrigin: true,
    pathRewrite: { '^/api/users': '' }
  }
};

Object.entries(services).forEach(([path, config]) => {
  app.use(path, createProxyMiddleware(config));
});

// API routes
app.get('/api', (req, res) => {
  res.json({
    name: 'E-Commerce API Gateway',
    version: '1.0.0',
    endpoints: Object.keys(services)
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(err.status || 500).json({
    error: {
      message: err.message || 'Internal Server Error',
      status: err.status || 500
    }
  });
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: {
      message: 'Not Found',
      status: 404
    }
  });
});

// Helper function to check service health
async function checkService(name, url) {
  try {
    const fetch = (await import('node-fetch')).default;
    const response = await fetch(`${url}/health`, { timeout: 5000 });
    return { name, healthy: response.ok, status: response.status };
  } catch (error) {
    return { name, healthy: false, error: error.message };
  }
}

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM signal received: closing HTTP server');
  server.close(() => {
    console.log('HTTP server closed');
    process.exit(0);
  });
});

// Start server
const server = app.listen(PORT, () => {
  console.log(`API Gateway running on port ${PORT}`);
  console.log('Environment:', process.env.NODE_ENV || 'development');
});

module.exports = app;