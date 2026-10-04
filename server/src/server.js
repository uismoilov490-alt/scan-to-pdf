const config = require('./config');
const { openDb } = require('./db');
const { createAi } = require('./ai');
const { createFirebaseVerifier } = require('./auth');
const { createApp } = require('./app');

const db = openDb(config.dbPath);
const ai = createAi(config);
const verifyToken = createFirebaseVerifier(config.firebaseProjectId);

const app = createApp({ config, db, ai, verifyToken });

app.listen(config.port, config.host, () => {
  console.log(
    `[scan-api] ${config.host}:${config.port} | ai=${ai.enabled ? 'on' : 'OFF'} | ` +
      `free=${config.freeDailyFiles} fayl/kun oylik=${config.planUnits.monthly} sahifa/oy`,
  );
});
