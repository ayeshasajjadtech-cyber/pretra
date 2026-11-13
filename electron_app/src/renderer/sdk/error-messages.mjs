const SDK_ERRORS = {
  0: {
    title: 'The session hit an unexpected snag',
    message: 'The SDK reported an unknown issue. Stop the camera and try again.',
    fatal: true,
  },
  1: {
    title: 'The session needs a fresh start',
    message: 'The SDK was in an unexpected state. Stop the camera and start a new session.',
    fatal: true,
  },
  2: {
    title: 'API key not accepted',
    message:
      'Check SMARTSPECTRA_API_KEY in your .env file, then restart Breathe Garden. ' +
      'You can create or manage keys in the Presage physiology portal.',
    fatal: true,
  },
  3: {
    title: 'The SDK could not configure this session',
    message:
      'Your API key may not have access to the requested signals. Restart the app and try ' +
      'again, or check your Presage plan and key permissions.',
    fatal: true,
  },
  4: {
    title: 'No measurement credits remaining',
    message:
      'Your Presage account has no remaining credits for this session. Check your plan or ' +
      'add credits, then try again.',
    fatal: true,
  },
  5: {
    title: 'Network connection interrupted',
    message:
      'The SDK could not reach Presage. Check your connection, then stop the camera and try again.',
    fatal: true,
  },
  6: {
    title: 'Presage service is unavailable',
    message:
      'The measurement service could not respond. Wait a moment, then stop the camera and try again.',
    fatal: true,
  },
  7: {
    title: 'Camera input is unavailable',
    message:
      'No usable camera was found, or another app is using it. Close other camera apps, check ' +
      'your camera connection, then try again.',
    fatal: true,
  },
  8: {
    title: 'Processing could not start',
    message:
      'The measurement graph did not reach a running state. Check your connection and the ' +
      'terminal for SDK details, then try again.',
    fatal: true,
  },
  9: {
    title: 'Camera frame format was not supported',
    message: 'The camera produced a frame the SDK could not read. Try a different camera or restart the app.',
    fatal: true,
  },
  10: {
    title: 'Camera timing glitch',
    message: 'The camera timestamps were not monotonic. Stop the camera and start a new session.',
    fatal: true,
  },
  11: {
    title: 'Camera timing gap',
    message: 'The camera skipped frames. Close other camera apps, then stop the camera and try again.',
    fatal: true,
  },
};

const VALIDATION_MESSAGES = {
  0: 'Signal looks good. Breathe naturally.',
  1: 'No face detected. Center your face in the preview.',
  2: 'More than one face is in view. Keep one face in frame.',
  3: 'Move your face toward the center of the frame.',
  4: 'Adjust your distance from the camera.',
  5: 'The scene is too dark. Add soft, even light.',
  6: 'The scene is too bright. Reduce direct light.',
  7: 'Chest not visible. Sit back so your upper body is in frame.',
  10: 'The camera is still adjusting. Hold still for a moment.',
  11: 'Frame rate is low. Close other camera apps.',
  12: 'Too much motion. Settle into a comfortable, still position.',
  13: 'Move a little farther from the camera.',
  14: 'Move a little closer to the camera.',
  15: 'Lower your face slightly in the frame.',
  16: 'Raise your face slightly in the frame.',
  17: 'Face the camera more directly.',
};

export function describeSdkError(code, message = '', retryable = false) {
  const known = SDK_ERRORS[code];
  if (known) {
    return {
      ...known,
      code,
      retryable: Boolean(retryable),
    };
  }

  return {
    code,
    title: 'The session was interrupted',
    message:
      message ||
      'The SDK reported an issue that Breathe Garden does not recognize. Stop the camera and try again.',
    retryable: Boolean(retryable),
    fatal: true,
  };
}

export function describeValidation(code, hint = '') {
  if (Number(code) === 0) {
    return {
      code: 0,
      message: VALIDATION_MESSAGES[0],
      level: 'good',
    };
  }

  const message = VALIDATION_MESSAGES[code] || hint || 'Adjust your position and lighting.';
  return {
    code,
    message,
    level: 'warn',
  };
}

export function isFatalSdkError(code) {
  return Boolean(SDK_ERRORS[code]?.fatal);
}
