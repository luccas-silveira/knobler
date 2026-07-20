// Geração e hashing dos segredos do relay.
const crypto = require('crypto');

/** Token de 256 bits (32 bytes) em base64url sem padding → 43 chars. */
function genToken() {
  return crypto.randomBytes(32).toString('base64url');
}

/** SHA-256 hex — guardamos só o hash dos segredos, nunca o valor cru. */
function sha256(input) {
  return crypto.createHash('sha256').update(input, 'utf8').digest('hex');
}

module.exports = { genToken, sha256 };
