const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { ApiError } = require('./errors');

// Firebase ID token'ni tekshirish uchun faqat projectId yetarli
// (Google'ning ochiq kalitlari bilan tekshiriladi, service account shart emas).
function createFirebaseVerifier(projectId) {
  const app = initializeApp({ projectId }, 'scan-api');
  const auth = getAuth(app);
  return (token) => auth.verifyIdToken(token);
}

function requireAuth(verifyToken) {
  return async (req, _res, next) => {
    const header = req.get('authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) {
      return next(new ApiError(401, 'AUTH_REQUIRED', 'Avval tizimga kiring'));
    }
    try {
      const decoded = await verifyToken(token);
      req.uid = decoded.uid;
      next();
    } catch {
      next(new ApiError(401, 'AUTH_INVALID', 'Sessiya eskirgan, qayta kiring'));
    }
  };
}

module.exports = { createFirebaseVerifier, requireAuth };
