import assert from 'node:assert/strict';
import test from 'node:test';

import {
  describeSdkError,
  describeValidation,
  isFatalSdkError,
} from '../src/renderer/sdk/error-messages.mjs';

test('maps known SDK errors to user-facing messages', () => {
  const error = describeSdkError(2, 'raw message', true);
  assert.equal(error.code, 2);
  assert.equal(error.title, 'API key not accepted');
  assert.match(error.message, /SMARTSPECTRA_API_KEY/);
  assert.equal(error.fatal, true);
  assert.equal(error.retryable, true);
});

test('falls back for unknown SDK errors', () => {
  const error = describeSdkError(99, 'custom detail');
  assert.equal(error.title, 'The session was interrupted');
  assert.equal(error.message, 'custom detail');
  assert.equal(error.fatal, true);
  assert.equal(error.retryable, false);
});

test('recognizes fatal SDK error codes', () => {
  assert.equal(isFatalSdkError(4), true);
  assert.equal(isFatalSdkError(0), true);
  assert.equal(isFatalSdkError(99), false);
});

test('describes validation hints', () => {
  assert.deepEqual(describeValidation(0), {
    code: 0,
    message: 'Signal looks good. Breathe naturally.',
    level: 'good',
  });

  const warning = describeValidation(12);
  assert.equal(warning.level, 'warn');
  assert.match(warning.message, /motion/i);

  const hinted = describeValidation(999, 'Custom hint');
  assert.equal(hinted.message, 'Custom hint');
  assert.equal(hinted.level, 'warn');
});

test('uses a generic validation fallback without a hint', () => {
  const result = describeValidation(999);
  assert.equal(result.message, 'Adjust your position and lighting.');
});
