const express = require('express');
const app = express();

const APP_POOL = process.env.APP_POOL || 'unknown';
const RELEASE_ID = process.env.RELEASE_ID || 'unknown';
const PORT = process.env.PORT || 3000;

let chaosMode = null;

app.use(express.json());

app.get('/version', (req, res) => {
  if (chaosMode === 'error') {
    return res.status(500).json({ error: 'Chaos mode: error' });
  }
  if (chaosMode === 'timeout') {
    return;
  }
  
  res.set('X-App-Pool', APP_POOL);
  res.set('X-Release-Id', RELEASE_ID);
  res.json({
    version: '1.0.0',
    pool: APP_POOL,
    releaseId: RELEASE_ID,
    timestamp: new Date().toISOString()
  });
});

app.get('/healthz', (req, res) => {
  if (chaosMode) {
    return res.status(503).json({ status: 'unhealthy', chaos: chaosMode });
  }
  res.json({ status: 'healthy' });
});

app.post('/chaos/start', (req, res) => {
  const mode = req.query.mode || 'error';
  chaosMode = mode;
  console.log(`Chaos mode started: ${mode}`);
  res.json({ chaos: mode, status: 'started' });
});

app.post('/chaos/stop', (req, res) => {
  chaosMode = null;
  console.log('Chaos mode stopped');
  res.json({ chaos: null, status: 'stopped' });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server running on port ${PORT}`);
  console.log(`Pool: ${APP_POOL}`);
  console.log(`Release: ${RELEASE_ID}`);
});
