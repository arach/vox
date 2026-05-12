// Vox voice FX engine — dispatcher / walkie-talkie / radio voice processing.
//
// Decodes WAV/PCM audio into an AudioBuffer and routes it through a Web Audio
// graph that mimics a radio transmission: a band-pass shapes the "speaker"
// tone, a compressor tightens dynamics, and short synthesized "kerchunk" PTT
// clicks bookend the transmission.
//
// This module is headless and framework-agnostic. It depends only on
// `window.AudioContext` and `fetch` — no asset files, no transitive imports.
// Consumers (Ranger, Talkie, etc.) wire their own UI on top of the preset
// library and the playback API below.

export type VoiceFxParams = {
  // Band-pass shape.
  lowCutHz: number;       // high-pass corner; rolls off bass below this
  highCutHz: number;      // low-pass corner; rolls off treble above this
  bandQ: number;          // shared Q for both filters (0.3 = gentle, 1.5 = peaky)
  // Saturation (tanh wave-shaping) — adds grit, makes the comp sound "pushed".
  saturationAmount: number;   // 0..1
  // Bit-crush (amplitude quantization) — adds AM/lo-fi crunch.
  bitcrushAmount: number;     // 0..1
  // Carrier hiss — the constant "open mic" noise around the transmission.
  hissGain: number;           // 0..0.5
  hissCutoffHz: number;       // high-pass corner for hiss; tunes brightness
  // Presence peak — peaking EQ inside the band that adds "comm intelligibility"
  // bite. The signature "small speaker / pushed mic" sound that lets a voice
  // cut through. Set `presencePeakDb` to 0 to bypass.
  presencePeakDb: number;     // 0..12 dB
  presenceCenterHz: number;   // 800..2500 Hz; sweet spot for nasal/comm bite
  presenceQ: number;          // 0.5..2 (lower = wider boost)
  // Compressor settings (DynamicsCompressorNode).
  compressorThresholdDb: number;
  compressorRatio: number;
  // PTT click envelope.
  clickEnabled: boolean;
  clickGain: number;      // 0..1 peak amplitude of the click burst
  clickDurationMs: number;
  // Squelch tail — a short noise burst right after the voice ends, before the
  // closing kerchunk. The "channel dropping" cinematic signature.
  squelchTailEnabled: boolean;
  squelchTailGain: number;        // 0..0.3
  squelchTailDurationMs: number;  // 50..400
  // Delivery pacing. <1 = chiller drawl; >1 = more urgent. Note: a naive
  // playbackRate also shifts pitch — for true time-stretch you'd want to
  // re-synthesize via Vox with this same value sent as `speed`.
  playbackRate: number;   // 0.7..1.4
  // Overall output trim.
  outputGain: number;     // 0..2
  // Dry/wet mix between processed (1) and bypassed (0) signal.
  wetMix: number;         // 0..1
};

export const DEFAULT_VOICE_FX: VoiceFxParams = {
  lowCutHz: 350,
  highCutHz: 2800,
  bandQ: 0.85,
  saturationAmount: 0.25,
  bitcrushAmount: 0.12,
  hissGain: 0.045,
  hissCutoffHz: 1200,
  presencePeakDb: 4,
  presenceCenterHz: 1500,
  presenceQ: 1.0,
  compressorThresholdDb: -22,
  compressorRatio: 5,
  clickEnabled: true,
  clickGain: 0.35,
  clickDurationMs: 70,
  squelchTailEnabled: true,
  squelchTailGain: 0.07,
  squelchTailDurationMs: 180,
  playbackRate: 1.0,
  outputGain: 1.1,
  wetMix: 1,
};

// Curated voice presets. Each is a complete VoiceFxParams so switching is a
// clean reset, not a partial merge. Grouped loosely by "family" — dispatch is
// big-room comm-style; walkie is close-range pocket radio. Names are meant to
// feel like personalities rather than gear specs.
export type VoiceFxPreset = {
  id: string;
  label: string;
  family: "dispatch" | "walkie" | "other";
  description: string;
  params: VoiceFxParams;
};

export const VOICE_FX_PRESETS: VoiceFxPreset[] = [
  // ── Dispatch family — big-room, mission-control energy ────────────────
  {
    id: "chill-dispatcher",
    label: "Chill Dispatcher",
    family: "dispatch",
    description: "Warm, friendly, takes its time. Like the calmest voice on the channel.",
    params: {
      lowCutHz: 280,
      highCutHz: 3200,
      bandQ: 0.7,
      saturationAmount: 0.2,
      bitcrushAmount: 0.08,
      hissGain: 0.035,
      hissCutoffHz: 1400,
      presencePeakDb: 3.5,
      presenceCenterHz: 1500,
      presenceQ: 1.0,
      compressorThresholdDb: -20,
      compressorRatio: 4,
      clickEnabled: true,
      clickGain: 0.3,
      clickDurationMs: 60,
      squelchTailEnabled: true,
      squelchTailGain: 0.06,
      squelchTailDurationMs: 160,
      playbackRate: 0.97,
      outputGain: 1.1,
      wetMix: 1,
    },
  },
  {
    id: "tower-control",
    label: "Tower Control",
    family: "dispatch",
    description: "Crisp, clipped, all-business. Pushes you out the door a little faster.",
    params: {
      lowCutHz: 500,
      highCutHz: 2400,
      bandQ: 1.0,
      saturationAmount: 0.42,
      bitcrushAmount: 0.22,
      hissGain: 0.06,
      hissCutoffHz: 1800,
      presencePeakDb: 6,
      presenceCenterHz: 1700,
      presenceQ: 1.3,
      compressorThresholdDb: -28,
      compressorRatio: 8,
      clickEnabled: true,
      clickGain: 0.5,
      clickDurationMs: 80,
      squelchTailEnabled: true,
      squelchTailGain: 0.1,
      squelchTailDurationMs: 200,
      playbackRate: 1.08,
      outputGain: 1.15,
      wetMix: 1,
    },
  },
  {
    id: "carrier-wave",
    label: "Carrier Wave",
    family: "dispatch",
    description: "Always-on hiss like someone's holding the mic just to keep you company.",
    params: {
      lowCutHz: 320,
      highCutHz: 3000,
      bandQ: 0.55,
      saturationAmount: 0.15,
      bitcrushAmount: 0.06,
      hissGain: 0.11,
      hissCutoffHz: 900,
      presencePeakDb: 2,
      presenceCenterHz: 1300,
      presenceQ: 0.8,
      compressorThresholdDb: -18,
      compressorRatio: 3,
      clickEnabled: true,
      clickGain: 0.18,
      clickDurationMs: 50,
      squelchTailEnabled: true,
      squelchTailGain: 0.12,
      squelchTailDurationMs: 300,
      playbackRate: 0.95,
      outputGain: 1.05,
      wetMix: 1,
    },
  },
  // ── Walkie family — pocket-size, close-range, snappy ──────────────────
  {
    id: "pocket-walkie",
    label: "Pocket Walkie",
    family: "walkie",
    description: "That nostalgic kid-radio crunch. Narrow, snappy, just-this-side-of-toy.",
    params: {
      lowCutHz: 600,
      highCutHz: 2300,
      bandQ: 1.2,
      saturationAmount: 0.5,
      bitcrushAmount: 0.35,
      hissGain: 0.08,
      hissCutoffHz: 1700,
      presencePeakDb: 7,
      presenceCenterHz: 1800,
      presenceQ: 1.5,
      compressorThresholdDb: -26,
      compressorRatio: 7,
      clickEnabled: true,
      clickGain: 0.6,
      clickDurationMs: 50,
      squelchTailEnabled: true,
      squelchTailGain: 0.09,
      squelchTailDurationMs: 120,
      playbackRate: 1.05,
      outputGain: 1.15,
      wetMix: 1,
    },
  },
  {
    id: "trail-buddy",
    label: "Trail Buddy",
    family: "walkie",
    description: "Breezy handheld vibe — wider, hissier, like your hiking partner two ridges over.",
    params: {
      lowCutHz: 380,
      highCutHz: 2900,
      bandQ: 0.75,
      saturationAmount: 0.32,
      bitcrushAmount: 0.18,
      hissGain: 0.14,
      hissCutoffHz: 1100,
      presencePeakDb: 4,
      presenceCenterHz: 1500,
      presenceQ: 1.0,
      compressorThresholdDb: -22,
      compressorRatio: 5,
      clickEnabled: true,
      clickGain: 0.35,
      clickDurationMs: 65,
      squelchTailEnabled: true,
      squelchTailGain: 0.1,
      squelchTailDurationMs: 180,
      playbackRate: 0.98,
      outputGain: 1.1,
      wetMix: 1,
    },
  },
  // ── Other — character / reference ────────────────────────────────────
  {
    id: "am-broadcast",
    label: "AM Broadcast",
    family: "other",
    description: "Vintage lo-fi, no PTT click. The voice on a radio left on in the next room.",
    params: {
      lowCutHz: 250,
      highCutHz: 2200,
      bandQ: 0.9,
      saturationAmount: 0.55,
      bitcrushAmount: 0.4,
      hissGain: 0.05,
      hissCutoffHz: 700,
      presencePeakDb: 3,
      presenceCenterHz: 1200,
      presenceQ: 1.2,
      compressorThresholdDb: -24,
      compressorRatio: 6,
      clickEnabled: false,
      clickGain: 0,
      clickDurationMs: 60,
      squelchTailEnabled: false,
      squelchTailGain: 0,
      squelchTailDurationMs: 120,
      playbackRate: 0.96,
      outputGain: 1.05,
      wetMix: 1,
    },
  },
  {
    id: "clean-mic",
    label: "Clean Mic",
    family: "other",
    description: "Almost no FX — just a tiny click. A/B reference for everything else.",
    params: {
      lowCutHz: 150,
      highCutHz: 5000,
      bandQ: 0.4,
      saturationAmount: 0.03,
      bitcrushAmount: 0,
      hissGain: 0,
      hissCutoffHz: 1200,
      presencePeakDb: 1,
      presenceCenterHz: 1500,
      presenceQ: 0.6,
      compressorThresholdDb: -16,
      compressorRatio: 2,
      clickEnabled: true,
      clickGain: 0.22,
      clickDurationMs: 45,
      squelchTailEnabled: false,
      squelchTailGain: 0,
      squelchTailDurationMs: 80,
      playbackRate: 1.0,
      outputGain: 1.0,
      wetMix: 1,
    },
  },
];

export type VoiceFxPlayOptions = {
  params?: Partial<VoiceFxParams>;
  signal?: AbortSignal;
  onEnded?: () => void;
};

let sharedContext: AudioContext | null = null;

function getAudioContext(): AudioContext {
  if (sharedContext && sharedContext.state !== "closed") return sharedContext;
  const Ctx = (window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext);
  if (!Ctx) throw new Error("Web Audio API is not available in this browser.");
  sharedContext = new Ctx();
  return sharedContext;
}

export async function decodeAudioFromBase64(
  base64: string,
  contentType = "audio/wav",
): Promise<AudioBuffer> {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return await decodeAudioFromArrayBuffer(bytes.buffer, contentType);
}

export async function decodeAudioFromArrayBuffer(
  buffer: ArrayBuffer,
  _contentType = "audio/wav",
): Promise<AudioBuffer> {
  const ctx = getAudioContext();
  if (ctx.state === "suspended") await ctx.resume();
  return await ctx.decodeAudioData(buffer.slice(0));
}

export async function decodeAudioFromUrl(url: string): Promise<AudioBuffer> {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Failed to load audio (${response.status}): ${url}`);
  const arrayBuffer = await response.arrayBuffer();
  const contentType = response.headers.get("content-type") ?? "audio/wav";
  return await decodeAudioFromArrayBuffer(arrayBuffer, contentType);
}

function resolveParams(input: Partial<VoiceFxParams> | undefined): VoiceFxParams {
  return { ...DEFAULT_VOICE_FX, ...(input ?? {}) };
}

// Saturation curve: smooth tanh shaping. drive grows with amount; output is
// normalized so unity in == unity-ish out, then we let the comp catch peaks.
function makeSaturationCurve(amount: number): Float32Array<ArrayBuffer> {
  const drive = 1 + Math.max(0, Math.min(1, amount)) * 14;
  const samples = 2048;
  const curve = new Float32Array(new ArrayBuffer(samples * 4));
  const norm = Math.tanh(drive);
  for (let i = 0; i < samples; i += 1) {
    const x = (i / (samples - 1)) * 2 - 1;
    curve[i] = Math.tanh(drive * x) / norm;
  }
  return curve;
}

// Bit-crush curve: amplitude quantization via a stepped wave-shaper.
// amount 0 → ~256 levels (transparent); amount 1 → 4 levels (very crunchy).
function makeBitcrushCurve(amount: number): Float32Array<ArrayBuffer> {
  const clamped = Math.max(0, Math.min(1, amount));
  const levels = Math.max(4, Math.round(256 * Math.pow(1 - clamped, 2.5)));
  const samples = 4096;
  const curve = new Float32Array(new ArrayBuffer(samples * 4));
  for (let i = 0; i < samples; i += 1) {
    const x = (i / (samples - 1)) * 2 - 1;
    curve[i] = Math.round(x * levels) / levels;
  }
  return curve;
}

// Pink-ish noise loop for carrier hiss. ~2s is plenty when looped.
function createHissBuffer(ctx: BaseAudioContext): AudioBuffer {
  const sampleRate = ctx.sampleRate;
  const length = Math.floor(2 * sampleRate);
  const buffer = ctx.createBuffer(1, length, sampleRate);
  const data = buffer.getChannelData(0);
  let last = 0;
  for (let i = 0; i < length; i += 1) {
    const white = Math.random() * 2 - 1;
    // simple one-pole lowpass colors the noise toward pink, then we let the
    // hiss high-pass in the graph shape its brightness.
    last = last * 0.78 + white * 0.22;
    data[i] = last;
  }
  return buffer;
}

// Synthesizes a short "kerchunk" — a filtered noise burst with a fast envelope.
// Cheap, deterministic, and avoids shipping a real audio asset.
function synthesizeKerchunk(ctx: BaseAudioContext, durationMs: number): AudioBuffer {
  const sampleRate = ctx.sampleRate;
  const length = Math.max(16, Math.floor((durationMs / 1000) * sampleRate));
  const buffer = ctx.createBuffer(1, length, sampleRate);
  const data = buffer.getChannelData(0);
  // Pink-ish filtered noise with an exponential decay envelope and a small
  // initial transient to suggest a relay snap.
  let lastSample = 0;
  for (let i = 0; i < length; i += 1) {
    const t = i / length;
    const env = Math.pow(1 - t, 2.4) + (i < 32 ? Math.pow(1 - i / 32, 3) * 0.6 : 0);
    const white = Math.random() * 2 - 1;
    lastSample = lastSample * 0.6 + white * 0.4;
    data[i] = lastSample * env;
  }
  return buffer;
}

type ScheduledClick = {
  source: AudioBufferSourceNode;
  startsAt: number;
};

function scheduleClick(
  ctx: AudioContext,
  destination: AudioNode,
  buffer: AudioBuffer,
  startTime: number,
  gain: number,
): ScheduledClick {
  const source = ctx.createBufferSource();
  source.buffer = buffer;
  const gainNode = ctx.createGain();
  gainNode.gain.value = gain;
  source.connect(gainNode).connect(destination);
  source.start(startTime);
  return { source, startsAt: startTime };
}

export type VoiceFxHandle = {
  promise: Promise<void>;
  stop: () => void;
};

export function playWithVoiceFx(
  audioBuffer: AudioBuffer,
  options: VoiceFxPlayOptions = {},
): VoiceFxHandle {
  const params = resolveParams(options.params);
  const ctx = getAudioContext();
  if (ctx.state === "suspended") void ctx.resume();

  // Wet (processed) chain: HP → LP → saturation → bit-crush → compressor.
  const highPass = ctx.createBiquadFilter();
  highPass.type = "highpass";
  highPass.frequency.value = params.lowCutHz;
  highPass.Q.value = params.bandQ;

  const lowPass = ctx.createBiquadFilter();
  lowPass.type = "lowpass";
  lowPass.frequency.value = params.highCutHz;
  lowPass.Q.value = params.bandQ;

  const saturation = ctx.createWaveShaper();
  saturation.curve = makeSaturationCurve(params.saturationAmount);
  saturation.oversample = "2x";

  const bitcrush = ctx.createWaveShaper();
  bitcrush.curve = makeBitcrushCurve(params.bitcrushAmount);
  // No oversample on bit-crush: we *want* the artifacts.

  // Presence peak — a peaking EQ inside the band-pass for that "comm
  // intelligibility" bite. Sits after the saturation/crunch so it boosts the
  // shaped signal, not the raw input.
  const presence = ctx.createBiquadFilter();
  presence.type = "peaking";
  presence.frequency.value = params.presenceCenterHz;
  presence.Q.value = params.presenceQ;
  presence.gain.value = params.presencePeakDb;

  const compressor = ctx.createDynamicsCompressor();
  compressor.threshold.value = params.compressorThresholdDb;
  compressor.ratio.value = params.compressorRatio;
  compressor.attack.value = 0.003;
  compressor.release.value = 0.08;
  compressor.knee.value = 6;

  const wetGain = ctx.createGain();
  wetGain.gain.value = params.wetMix;

  const dryGain = ctx.createGain();
  dryGain.gain.value = 1 - params.wetMix;

  const outputGain = ctx.createGain();
  outputGain.gain.value = params.outputGain;

  // Voice source feeds both dry and wet paths so we can crossfade.
  const source = ctx.createBufferSource();
  source.buffer = audioBuffer;
  const playbackRate = Math.max(0.5, Math.min(2, params.playbackRate));
  source.playbackRate.value = playbackRate;
  // Effective duration once playbackRate is applied. All voice-end scheduling
  // uses this so the hiss tail and end click stay aligned with the audible end.
  const effectiveDuration = audioBuffer.duration / playbackRate;
  source.connect(highPass);
  highPass.connect(lowPass);
  lowPass.connect(saturation);
  saturation.connect(bitcrush);
  bitcrush.connect(presence);
  presence.connect(compressor);
  compressor.connect(wetGain);
  wetGain.connect(outputGain);

  source.connect(dryGain);
  dryGain.connect(outputGain);

  outputGain.connect(ctx.destination);

  const now = ctx.currentTime;
  const clickLeadMs = 40;
  const clickLead = clickLeadMs / 1000;
  const clickBuffer = params.clickEnabled
    ? synthesizeKerchunk(ctx, params.clickDurationMs)
    : null;
  const voiceStart = now + (params.clickEnabled ? clickLead + params.clickDurationMs / 1000 : 0);
  source.start(voiceStart);

  // Carrier hiss: loops alongside the transmission. Joins the wet bus so the
  // dry/wet mix controls it uniformly. Tail trails just past the end click
  // for that "carrier dropping" feel.
  let hissSource: AudioBufferSourceNode | null = null;
  if (params.hissGain > 0 && params.wetMix > 0) {
    const hissBuffer = createHissBuffer(ctx);
    hissSource = ctx.createBufferSource();
    hissSource.buffer = hissBuffer;
    hissSource.loop = true;
    const hissHighPass = ctx.createBiquadFilter();
    hissHighPass.type = "highpass";
    hissHighPass.frequency.value = params.hissCutoffHz;
    hissHighPass.Q.value = 0.7;
    const hissLevel = ctx.createGain();
    hissLevel.gain.value = params.hissGain;
    hissSource.connect(hissHighPass).connect(hissLevel).connect(wetGain);
    const hissStart = now;
    const hissEnd = voiceStart + effectiveDuration + 0.18;
    // Tiny fade in/out so the hiss doesn't pop.
    hissLevel.gain.setValueAtTime(0, hissStart);
    hissLevel.gain.linearRampToValueAtTime(params.hissGain, hissStart + 0.03);
    hissLevel.gain.setValueAtTime(params.hissGain, hissEnd - 0.08);
    hissLevel.gain.linearRampToValueAtTime(0, hissEnd);
    hissSource.start(hissStart);
    hissSource.stop(hissEnd + 0.02);
  }

  // Squelch tail — short noise burst after voice ends, before the end click.
  // The cinematic "channel dropping" sound. Routes through wetGain so the
  // dry/wet mix controls it like everything else in the FX bus.
  const voiceEnd = voiceStart + effectiveDuration;
  const squelchEnabled = params.squelchTailEnabled
    && params.squelchTailGain > 0
    && params.wetMix > 0;
  const squelchDur = params.squelchTailDurationMs / 1000;
  const squelchStart = voiceEnd + 0.005;
  const squelchEnd = squelchEnabled ? squelchStart + squelchDur : voiceEnd;
  let squelchSource: AudioBufferSourceNode | null = null;
  if (squelchEnabled) {
    const squelchBuffer = createHissBuffer(ctx);
    squelchSource = ctx.createBufferSource();
    squelchSource.buffer = squelchBuffer;
    squelchSource.loop = true;
    const squelchHP = ctx.createBiquadFilter();
    squelchHP.type = "highpass";
    squelchHP.frequency.value = 1000; // a touch brighter than carrier hiss
    squelchHP.Q.value = 0.7;
    const squelchGainNode = ctx.createGain();
    squelchGainNode.gain.value = 0;
    squelchSource.connect(squelchHP).connect(squelchGainNode).connect(wetGain);
    // Fast attack (~8ms), exponential decay over the tail — that "carrier
    // releases and noise dies out" feel.
    squelchGainNode.gain.setValueAtTime(0, squelchStart);
    squelchGainNode.gain.linearRampToValueAtTime(params.squelchTailGain, squelchStart + 0.008);
    squelchGainNode.gain.exponentialRampToValueAtTime(0.001, squelchEnd);
    squelchSource.start(squelchStart);
    squelchSource.stop(squelchEnd + 0.02);
  }

  const scheduledClicks: ScheduledClick[] = [];
  if (clickBuffer && params.clickEnabled) {
    scheduledClicks.push(scheduleClick(ctx, outputGain, clickBuffer, now, params.clickGain));
    // End click slides to after the squelch tail (if any) so the sequence
    // reads: voice → squelch breath → carrier-drop click.
    const endClickAt = (squelchEnabled ? squelchEnd : voiceEnd) + 0.02;
    scheduledClicks.push(scheduleClick(ctx, outputGain, clickBuffer, endClickAt, params.clickGain * 0.85));
  }

  let stopped = false;
  let onEndedFired = false;
  const fireOnEnded = () => {
    if (onEndedFired) return;
    onEndedFired = true;
    options.onEnded?.();
  };

  const promise = new Promise<void>((resolvePromise) => {
    const squelchAddedDur = squelchEnabled ? squelchDur + 0.02 : 0;
    const totalDuration = (params.clickEnabled
      ? clickLead + params.clickDurationMs / 1000
      : 0)
      + effectiveDuration
      + squelchAddedDur
      + (params.clickEnabled ? params.clickDurationMs / 1000 + 0.04 : 0)
      + 0.02;
    const timer = setTimeout(() => {
      fireOnEnded();
      resolvePromise();
    }, Math.ceil(totalDuration * 1000));

    const abort = () => {
      if (stopped) return;
      stopped = true;
      clearTimeout(timer);
      try { source.stop(); } catch { /* already stopped */ }
      if (hissSource) {
        try { hissSource.stop(); } catch { /* already stopped */ }
      }
      if (squelchSource) {
        try { squelchSource.stop(); } catch { /* already stopped */ }
      }
      for (const click of scheduledClicks) {
        try { click.source.stop(); } catch { /* already stopped */ }
      }
      try { source.disconnect(); } catch { /* noop */ }
      try { outputGain.disconnect(); } catch { /* noop */ }
      fireOnEnded();
      resolvePromise();
    };

    if (options.signal) {
      if (options.signal.aborted) abort();
      else options.signal.addEventListener("abort", abort, { once: true });
    }
  });

  return {
    promise,
    stop: () => {
      try { source.stop(); } catch { /* noop */ }
      if (hissSource) {
        try { hissSource.stop(); } catch { /* noop */ }
      }
      if (squelchSource) {
        try { squelchSource.stop(); } catch { /* noop */ }
      }
      for (const click of scheduledClicks) {
        try { click.source.stop(); } catch { /* noop */ }
      }
    },
  };
}

export function playDry(audioBuffer: AudioBuffer, options: { signal?: AbortSignal; onEnded?: () => void } = {}): VoiceFxHandle {
  const ctx = getAudioContext();
  if (ctx.state === "suspended") void ctx.resume();
  const source = ctx.createBufferSource();
  source.buffer = audioBuffer;
  source.connect(ctx.destination);
  source.start(ctx.currentTime);

  let onEndedFired = false;
  const fireOnEnded = () => {
    if (onEndedFired) return;
    onEndedFired = true;
    options.onEnded?.();
  };

  const promise = new Promise<void>((resolvePromise) => {
    const timer = setTimeout(() => {
      fireOnEnded();
      resolvePromise();
    }, Math.ceil(audioBuffer.duration * 1000) + 20);

    const abort = () => {
      clearTimeout(timer);
      try { source.stop(); } catch { /* noop */ }
      try { source.disconnect(); } catch { /* noop */ }
      fireOnEnded();
      resolvePromise();
    };

    if (options.signal) {
      if (options.signal.aborted) abort();
      else options.signal.addEventListener("abort", abort, { once: true });
    }
  });

  return {
    promise,
    stop: () => {
      try { source.stop(); } catch { /* noop */ }
    },
  };
}
