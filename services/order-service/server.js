const express = require('express');
const prometheus = require('prom-client');

const app = express();
const PORT = process.env.PORT || 8082;

const register = new prometheus.Registry();
prometheus.collectDefaultMetrics({ register });

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'order-service' });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/orders', (req, res) => {
  res.json([
    { id: 1, userId: 1, total: 99.99, status: 'completed' },
    { id: 2, userId: 2, total: 149.99, status: 'pending' }
  ]);
});

app.listen(PORT, () => {
  console.log(`Order service running on port ${PORT}`);
});