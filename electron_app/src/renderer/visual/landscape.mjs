const TAU = Math.PI * 2;
const REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)';

function mulberry32(seed) {
  let value = seed >>> 0;
  return function random() {
    value = (value + 0x6d2b79f5) | 0;
    let t = Math.imul(value ^ (value >>> 15), 1 | value);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function lerp(from, to, amount) {
  return from + (to - from) * amount;
}

function rgba(r, g, b, alpha) {
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

export function createLandscape(canvas, { reducedMotion } = {}) {
  const ctx = canvas.getContext('2d', { alpha: false });
  if (!ctx) throw new Error('Canvas 2D is unavailable');

  const motionQuery = window.matchMedia?.(REDUCED_MOTION_QUERY);
  let reduceMotion = reducedMotion ?? Boolean(motionQuery?.matches);
  let width = 1;
  let height = 1;
  let dpr = 1;
  let running = false;
  let rafId = 0;
  let lastTimestamp = 0;
  let mode = 'ambient';
  let phaseBreath = 0;
  let phasePulse = 0;

  const target = {
    active: false,
    simulated: false,
    breathing: null,
    pulse: null,
    breathingRate: null,
    pulseRate: null,
    confidence: 0,
  };

  const current = {
    active: false,
    simulated: false,
    breathing: 0.42,
    pulse: 0.5,
    confidence: 0,
  };

  const scene = {
    stars: [],
    hills: [],
    mist: [],
    grass: [],
    flowers: [],
    fireflies: [],
  };

  function buildScene() {
    const random = mulberry32(0xb4ea7);

    scene.stars = Array.from({ length: 100 }, () => ({
      x: random(),
      y: random() * 0.58,
      radius: 0.35 + random() * 1.45,
      phase: random() * TAU,
      speed: 0.15 + random() * 0.8,
    }));

    scene.hills = Array.from({ length: 3 }, (_, index) => ({
      baseY: 0.52 + index * 0.095,
      amplitude: 0.026 + index * 0.014,
      frequency: 1.05 + index * 0.55,
      frequencyB: 2.3 + index * 0.8,
      phase: random() * TAU,
      phaseB: random() * TAU,
      drift: 0.012 + index * 0.006,
      hue: 158 + index * 4,
      lightness: 10 + index * 4,
      alpha: 0.96 - index * 0.13,
    }));

    scene.mist = Array.from({ length: 7 }, (_, index) => ({
      x: random(),
      y: 0.34 + random() * 0.24,
      width: 0.28 + random() * 0.34,
      height: 0.025 + random() * 0.035,
      speed: 0.0015 + random() * 0.003,
      alpha: 0.025 + random() * 0.035,
      phase: random() * TAU,
      index,
    }));

    scene.grass = Array.from({ length: 150 }, () => ({
      x: random(),
      y: 0.79 + random() * 0.22,
      height: 0.025 + random() * 0.105,
      lean: (random() - 0.5) * 0.9,
      phase: random() * TAU,
      speed: 0.35 + random() * 0.7,
      hue: 148 + random() * 22,
      lightness: 17 + random() * 15,
      alpha: 0.3 + random() * 0.45,
    }));

    scene.flowers = Array.from({ length: 28 }, () => {
      const warm = random();
      return {
        x: random(),
        y: 0.8 + random() * 0.18,
        height: 0.04 + random() * 0.1,
        size: 2.2 + random() * 4.6,
        petals: 5 + Math.floor(random() * 3),
        phase: random() * TAU,
        speed: 0.25 + random() * 0.55,
        warm,
        hue: warm > 0.62 ? 38 : warm > 0.32 ? 16 : 338,
        alpha: 0.55 + random() * 0.4,
      };
    });

    scene.fireflies = Array.from({ length: 48 }, () => ({
      x: random(),
      y: 0.36 + random() * 0.56,
      radius: 0.7 + random() * 1.6,
      phase: random() * TAU,
      speed: 0.2 + random() * 0.7,
      driftX: (random() - 0.5) * 0.022,
      driftY: (random() - 0.5) * 0.012,
      hue: 38 + random() * 22,
    }));
  }

  function resize() {
    const rect = canvas.getBoundingClientRect();
    width = Math.max(1, Math.round(rect.width || window.innerWidth));
    height = Math.max(1, Math.round(rect.height || window.innerHeight));
    dpr = Math.min(2, window.devicePixelRatio || 1);

    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.imageSmoothingEnabled = true;

    buildScene();
    if (!running) draw(performance.now());
  }

  function drawSky() {
    const breath = current.breathing;
    const gradient = ctx.createLinearGradient(0, 0, 0, height);
    gradient.addColorStop(0, `hsl(${lerp(205, 192, breath)} 48% ${lerp(6, 9, breath)}%)`);
    gradient.addColorStop(0.46, `hsl(${lerp(192, 172, breath)} 44% ${lerp(11, 15, breath)}%)`);
    gradient.addColorStop(0.76, `hsl(${lerp(172, 28, breath * 0.7)} 46% ${lerp(17, 31, breath)}%)`);
    gradient.addColorStop(1, `hsl(${lerp(156, 20, breath * 0.5)} 40% ${lerp(8, 13, breath)}%)`);
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, width, height);
  }

  function drawStars(time) {
    const horizon = height * 0.58;
    ctx.save();
    for (const star of scene.stars) {
      const x = star.x * width;
      const y = star.y * horizon;
      const twinkle = reduceMotion
        ? 0.55
        : 0.35 + 0.65 * (0.5 + 0.5 * Math.sin(time * 0.001 * star.speed + star.phase));
      ctx.fillStyle = rgba(221, 247, 237, twinkle * 0.8);
      ctx.beginPath();
      ctx.arc(x, y, star.radius, 0, TAU);
      ctx.fill();
    }
    ctx.restore();
  }

  function drawSun(time) {
    const x = width * (0.71 + Math.sin(phaseBreath * 0.18) * 0.012);
    const y = height * (0.235 - current.breathing * 0.028);
    const radius = Math.min(width, height) * (0.036 + current.pulse * 0.012);

    const glow = ctx.createRadialGradient(x, y, 0, x, y, radius * 6.5);
    glow.addColorStop(0, rgba(255, 242, 199, 0.92));
    glow.addColorStop(0.18, rgba(255, 214, 143, 0.55));
    glow.addColorStop(0.55, rgba(245, 166, 107, 0.16));
    glow.addColorStop(1, rgba(245, 166, 107, 0));
    ctx.fillStyle = glow;
    ctx.beginPath();
    ctx.arc(x, y, radius * 6.5, 0, TAU);
    ctx.fill();

    ctx.fillStyle = rgba(255, 244, 209, 0.96);
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, TAU);
    ctx.fill();

    ctx.strokeStyle = rgba(255, 236, 182, 0.24 + current.pulse * 0.2);
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    ctx.arc(x, y, radius * (1.55 + Math.sin(phasePulse) * 0.08), 0, TAU);
    ctx.stroke();
  }

  function drawMist(time) {
    ctx.save();
    for (const band of scene.mist) {
      const drift = reduceMotion ? 0 : time * 0.001 * band.speed * width * 8;
      const x = ((band.x * width + drift) % (width * 1.5)) - width * 0.25;
      const y = band.y * height + Math.sin(time * 0.0004 + band.phase) * 6;
      const radiusX = band.width * width;
      const radiusY = band.height * height;
      ctx.save();
      ctx.translate(x, y);
      ctx.scale(1, Math.max(0.05, radiusY / radiusX));
      const gradient = ctx.createRadialGradient(0, 0, 0, 0, 0, radiusX);
      gradient.addColorStop(0, rgba(196, 240, 222, band.alpha));
      gradient.addColorStop(1, rgba(196, 240, 222, 0));
      ctx.fillStyle = gradient;
      ctx.beginPath();
      ctx.arc(0, 0, radiusX, 0, TAU);
      ctx.fill();
      ctx.restore();
    }
    ctx.restore();
  }

  function drawHills(time) {
    for (let index = 0; index < scene.hills.length; index += 1) {
      const hill = scene.hills[index];
      const breathLift = (current.breathing - 0.5) * height * 0.026;
      const pulseLift = current.pulse * height * 0.004;
      const baseY = hill.baseY * height + breathLift + pulseLift;
      const amplitude = hill.amplitude * height;
      const drift = reduceMotion ? 0 : time * 0.001 * hill.drift;

      ctx.beginPath();
      ctx.moveTo(0, height);
      const step = Math.max(5, Math.round(width / 120));
      for (let x = 0; x <= width + step; x += step) {
        const y = baseY
          + Math.sin(x * (hill.frequency / width) + hill.phase + drift) * amplitude
          + Math.sin(x * (hill.frequencyB / width) + hill.phaseB - drift * 1.7) * amplitude * 0.38;
        ctx.lineTo(x, y);
      }
      ctx.lineTo(width, height);
      ctx.closePath();

      const gradient = ctx.createLinearGradient(0, baseY - amplitude, 0, height);
      gradient.addColorStop(0, `hsla(${hill.hue}, 44%, ${hill.lightness + 5}%, ${hill.alpha})`);
      gradient.addColorStop(1, `hsla(${hill.hue - 6}, 48%, ${hill.lightness}%, ${hill.alpha})`);
      ctx.fillStyle = gradient;
      ctx.fill();

      ctx.strokeStyle = `hsla(${hill.hue + 10}, 58%, ${hill.lightness + 18}%, 0.16)`;
      ctx.lineWidth = 1;
      ctx.stroke();
    }
  }

  function drawMeadow(time) {
    const meadowTop = height * 0.7;
    const gradient = ctx.createLinearGradient(0, meadowTop, 0, height);
    gradient.addColorStop(0, 'rgba(8, 33, 27, 0)');
    gradient.addColorStop(0.35, 'rgba(7, 31, 25, 0.52)');
    gradient.addColorStop(1, 'rgba(3, 18, 16, 0.94)');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, meadowTop, width, height - meadowTop);

    const breath = current.breathing;
    const pulse = current.pulse;

    ctx.save();
    for (const blade of scene.grass) {
      const x = blade.x * width;
      const baseY = blade.y * height;
      const bladeHeight = blade.height * height * (0.7 + breath * 0.55);
      const sway = reduceMotion
        ? 0
        : Math.sin(time * 0.001 * blade.speed + blade.phase + x * 0.007) * (0.25 + breath * 0.75);
      const tipX = x + blade.lean * bladeHeight * 0.34 + sway * bladeHeight * 0.2;
      const tipY = baseY - bladeHeight;
      const controlX = x + blade.lean * bladeHeight * 0.1 + sway * bladeHeight * 0.08;
      const controlY = baseY - bladeHeight * 0.58;

      ctx.strokeStyle = `hsla(${blade.hue}, 46%, ${blade.lightness + pulse * 4}%, ${blade.alpha})`;
      ctx.lineWidth = 0.8 + blade.height * 6;
      ctx.beginPath();
      ctx.moveTo(x, baseY);
      ctx.quadraticCurveTo(controlX, controlY, tipX, tipY);
      ctx.stroke();
    }
    ctx.restore();

    ctx.save();
    for (const flower of scene.flowers) {
      const x = flower.x * width;
      const baseY = flower.y * height;
      const stemHeight = flower.height * height * (0.72 + breath * 0.55);
      const sway = reduceMotion
        ? 0
        : Math.sin(time * 0.001 * flower.speed + flower.phase) * (0.2 + breath * 0.8);
      const tipX = x + sway * stemHeight * 0.14;
      const tipY = baseY - stemHeight;
      const bloom = 0.25 + breath * 0.75;
      const size = flower.size * bloom * (0.8 + pulse * 0.35);

      ctx.strokeStyle = 'rgba(91, 166, 113, 0.58)';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(x, baseY);
      ctx.quadraticCurveTo(x + sway * 2, baseY - stemHeight * 0.6, tipX, tipY);
      ctx.stroke();

      ctx.save();
      ctx.translate(tipX, tipY);
      ctx.rotate(sway * 0.25);
      for (let petal = 0; petal < flower.petals; petal += 1) {
        const angle = (petal / flower.petals) * TAU + flower.phase * 0.1;
        ctx.save();
        ctx.rotate(angle);
        ctx.fillStyle = `hsla(${flower.hue + pulse * 10}, 76%, ${64 + pulse * 6}%, ${flower.alpha})`;
        ctx.beginPath();
        ctx.ellipse(size * 0.58, 0, size * 0.62, size * 0.3, 0, 0, TAU);
        ctx.fill();
        ctx.restore();
      }
      ctx.fillStyle = 'rgba(255, 235, 170, 0.9)';
      ctx.beginPath();
      ctx.arc(0, 0, Math.max(1, size * 0.22), 0, TAU);
      ctx.fill();
      ctx.restore();
    }
    ctx.restore();
  }

  function drawBreathHalo(time) {
    if (!current.active) return;

    const centerX = width * 0.5;
    const centerY = height * 0.46;
    const baseRadius = Math.min(width, height) * (0.09 + current.breathing * 0.055);
    const pulse = 1 + Math.sin(phasePulse) * 0.035;
    const alpha = 0.04 + current.confidence / 100 * 0.08;

    ctx.save();
    ctx.strokeStyle = rgba(182, 247, 206, alpha);
    ctx.lineWidth = 1.4;
    ctx.beginPath();
    ctx.arc(centerX, centerY, baseRadius * pulse, 0, TAU);
    ctx.stroke();

    ctx.strokeStyle = rgba(255, 213, 154, alpha * 0.7);
    ctx.beginPath();
    ctx.arc(centerX, centerY, baseRadius * 1.32 * (1 + Math.sin(phaseBreath) * 0.02), 0, TAU);
    ctx.stroke();
    ctx.restore();
  }

  function drawFireflies(time) {
    const pulse = current.pulse;
    ctx.save();
    ctx.globalCompositeOperation = 'lighter';
    for (const fly of scene.fireflies) {
      const driftX = reduceMotion ? 0 : Math.sin(time * 0.0004 * fly.speed + fly.phase) * fly.driftX;
      const driftY = reduceMotion ? 0 : Math.cos(time * 0.0003 * fly.speed + fly.phase * 1.3) * fly.driftY;
      const x = (fly.x + driftX) * width;
      const y = (fly.y + driftY) * height;
      const glow = 0.25 + 0.75 * (0.5 + 0.5 * Math.sin(time * 0.001 * fly.speed + fly.phase));
      const radius = fly.radius * (0.8 + pulse * 0.9);

      ctx.fillStyle = `hsla(${fly.hue}, 90%, 72%, ${0.08 + glow * 0.16})`;
      ctx.beginPath();
      ctx.arc(x, y, radius * 3.2, 0, TAU);
      ctx.fill();

      ctx.fillStyle = `hsla(${fly.hue}, 96%, 82%, ${0.32 + glow * 0.6})`;
      ctx.beginPath();
      ctx.arc(x, y, radius, 0, TAU);
      ctx.fill();
    }
    ctx.restore();
  }

  function drawVignette() {
    const gradient = ctx.createRadialGradient(
      width * 0.5,
      height * 0.46,
      Math.min(width, height) * 0.18,
      width * 0.5,
      height * 0.46,
      Math.max(width, height) * 0.76,
    );
    gradient.addColorStop(0, 'rgba(0, 0, 0, 0)');
    gradient.addColorStop(0.68, 'rgba(0, 0, 0, 0.08)');
    gradient.addColorStop(1, 'rgba(0, 0, 0, 0.54)');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, width, height);

    if (mode === 'summary') {
      ctx.fillStyle = 'rgba(38, 24, 8, 0.12)';
      ctx.fillRect(0, 0, width, height);
    }
  }

  function draw(time) {
    const dt = lastTimestamp ? Math.min(0.06, (time - lastTimestamp) / 1000) : 0.016;
    lastTimestamp = time;

    const smoothing = reduceMotion ? 1 : 0.055;
    current.active = target.active;
    current.simulated = target.simulated;
    current.breathing = lerp(current.breathing, target.breathing ?? 0.42, smoothing);
    current.pulse = lerp(current.pulse, target.pulse ?? 0.5, smoothing);
    current.confidence = lerp(current.confidence, target.confidence ?? 0, smoothing);

    if (Number.isFinite(target.breathingRate) && target.breathingRate > 0) {
      phaseBreath += dt * (target.breathingRate / 60) * TAU;
    } else {
      phaseBreath += dt * 0.34;
    }

    if (Number.isFinite(target.pulseRate) && target.pulseRate > 0) {
      phasePulse += dt * (target.pulseRate / 60) * TAU;
    } else {
      phasePulse += dt * 1.15;
    }

    drawSky();
    drawStars(time);
    drawSun(time);
    drawMist(time);
    drawHills(time);
    drawMeadow(time);
    drawBreathHalo(time);
    drawFireflies(time);
    drawVignette();
  }

  function loop(time) {
    if (!running) return;
    draw(time);
    rafId = requestAnimationFrame(loop);
  }

  function setSignal(signal = {}) {
    target.active = Boolean(signal.active);
    target.simulated = Boolean(signal.simulated);
    target.breathing = Number.isFinite(signal.breathing) ? signal.breathing : null;
    target.pulse = Number.isFinite(signal.pulse) ? signal.pulse : null;
    target.breathingRate = Number.isFinite(signal.breathingRate) ? signal.breathingRate : null;
    target.pulseRate = Number.isFinite(signal.pulseRate) ? signal.pulseRate : null;
    target.confidence = Number.isFinite(signal.confidence) ? signal.confidence : 0;
  }

  function setMode(nextMode) {
    mode = nextMode;
  }

  function start() {
    if (running) return;
    running = true;
    lastTimestamp = 0;
    rafId = requestAnimationFrame(loop);
  }

  function stop() {
    running = false;
    cancelAnimationFrame(rafId);
  }

  function destroy() {
    stop();
    resizeObserver?.disconnect();
    motionQuery?.removeEventListener?.('change', onMotionChange);
  }

  function onMotionChange(event) {
    reduceMotion = event.matches;
  }

  const resizeObserver = typeof ResizeObserver !== 'undefined'
    ? new ResizeObserver(() => resize())
    : null;
  resizeObserver?.observe(canvas);
  motionQuery?.addEventListener?.('change', onMotionChange);

  resize();

  return {
    destroy,
    resize,
    setMode,
    setSignal,
    start,
    stop,
  };
}
