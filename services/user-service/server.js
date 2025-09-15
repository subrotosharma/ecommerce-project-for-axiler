const express = require('express');
const prometheus = require('prom-client');

const app = express();
const PORT = process.env.PORT || 8083;

const register = new prometheus.Registry();
prometheus.collectDefaultMetrics({ register });

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'user-service' });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/users', (req, res) => {
  res.json([
    { id: 1, name: 'John Doe', email: 'john@example.com' },
    { id: 2, name: 'Jane Smith', email: 'jane@example.com' }
  ]);
});

app.listen(PORT, () => {
  console.log(`User service running on port ${PORT}`);
});