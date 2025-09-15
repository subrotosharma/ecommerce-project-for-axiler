const express = require('express');
const prometheus = require('prom-client');

const app = express();
const PORT = process.env.PORT || 8081;

const register = new prometheus.Registry();
prometheus.collectDefaultMetrics({ register });

app.use(express.json());

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', service: 'product-service' });
});

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.get('/products', (req, res) => {
  res.json([
    { id: 1, name: 'Product 1', price: 99.99 },
    { id: 2, name: 'Product 2', price: 149.99 }
  ]);
});

app.listen(PORT, () => {
  console.log(`Product service running on port ${PORT}`);
});