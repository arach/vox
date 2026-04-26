#!/usr/bin/env bun

import { existsSync, mkdirSync, mkdtempSync, readdirSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join, resolve } from "path";
import { VoxClient, type AttributedWordTiming, type FileAnnotationResult, type FileTranscriptionResult, type SpeakerSegment, type WordTiming } from "../packages/client/src/index.ts";

type ScenarioTurn = {
  speakerId: string;
  voice: string;
  text: string;
  pauseAfterMs: number;
};

type TurnArtifact = {
  index: number;
  speakerId: string;
  voice: string;
  text: string;
  wavPath: string;
  silencePath?: string;
  durationSec: number;
  startSec: number;
  endSec: number;
  transcription: FileTranscriptionResult;
};

type ReferenceWord = WordTiming & {
  speakerId: string;
};

type EvaluationReport = {
  outputDir: string;
  combinedAudioPath: string;
  turns: Array<{
    index: number;
    speakerId: string;
    voice: string;
    text: string;
    startSec: number;
    endSec: number;
    durationSec: number;
    transcription: FileTranscriptionResult;
  }>;
  groundTruth: {
    transcript: string;
    speakers: SpeakerSegment[];
    words: ReferenceWord[];
  };
  combinedTranscription: FileTranscriptionResult;
  annotation?: {
    result: FileAnnotationResult;
    evaluation: {
      speakerMapping: Record<string, string>;
      referenceWordCount: number;
      coveredWordCount: number;
      speakerAccuracy: number;
      predictedSpeakerCount: number;
      referenceSpeakerCount: number;
    };
  };
  annotationError?: string;
};

type AnnotationEvaluation = NonNullable<EvaluationReport["annotation"]>["evaluation"];

const DEFAULT_PORT = 42137;
const DEFAULT_OUT_PREFIX = "vox-annotation-eval-";

const defaultScenario = (voiceA: string, voiceB: string): ScenarioTurn[] => [
  {
    speakerId: "speaker_a",
    voice: voiceA,
    text: "Let's start with the client metrics from yesterday afternoon.",
    pauseAfterMs: 360,
  },
  {
    speakerId: "speaker_b",
    voice: voiceB,
    text: "Sure. The warm path stayed under one hundred milliseconds the whole time.",
    pauseAfterMs: 420,
  },
  {
    speakerId: "speaker_a",
    voice: voiceA,
    text: "Great. Please mark the cold start spike on the first run.",
    pauseAfterMs: 330,
  },
  {
    speakerId: "speaker_b",
    voice: voiceB,
    text: "Done. I also tagged the model load so the dashboard stays readable.",
    pauseAfterMs: 0,
  },
];

async function main(argv: string[]): Promise<void> {
  const port = Number(readOption(argv, "--port") ?? DEFAULT_PORT);
  const voiceA = readOption(argv, "--voice-a") ?? "Samantha";
  const voiceB = readOption(argv, "--voice-b") ?? "Daniel";
  const outDir = readOption(argv, "--out-dir")
    ? resolve(readOption(argv, "--out-dir")!)
    : mkdtempSync(join(tmpdir(), DEFAULT_OUT_PREFIX));
  const keepIntermediates = argv.includes("--keep-intermediates");

  mkdirSync(outDir, { recursive: true });

  const client = new VoxClient({
    clientId: "annotation-eval",
    port,
  });

  try {
    await waitForDaemon(client);
    await client.preloadModel("parakeet:v3");

    const turns = defaultScenario(voiceA, voiceB);
    const artifacts = await buildArtifacts(outDir, turns, client);
    const combinedAudioPath = join(outDir, "combined-dialogue.wav");
    await concatArtifacts(artifacts, combinedAudioPath);

    const combinedTranscription = await client.transcribeFile(combinedAudioPath, "parakeet:v3");
    const groundTruth = buildGroundTruth(artifacts);

    const report: EvaluationReport = {
      outputDir: outDir,
      combinedAudioPath,
      turns: artifacts.map((artifact) => ({
        index: artifact.index,
        speakerId: artifact.speakerId,
        voice: artifact.voice,
        text: artifact.text,
        startSec: artifact.startSec,
        endSec: artifact.endSec,
        durationSec: artifact.durationSec,
        transcription: artifact.transcription,
      })),
      groundTruth,
      combinedTranscription,
    };

    try {
      const annotation = await client.annotateFile(combinedAudioPath, {
        modelId: "speaker-diarization:v1",
        text: combinedTranscription.text,
        words: combinedTranscription.words,
      });
      report.annotation = {
        result: annotation,
        evaluation: evaluateAnnotation(annotation, groundTruth),
      };
    } catch (error) {
      report.annotationError = error instanceof Error ? error.message : String(error);
    }

    const reportPath = join(outDir, "report.json");
    writeFileSync(reportPath, JSON.stringify(report, null, 2));

    printSummary(report, reportPath);

    if (!keepIntermediates) {
      cleanupIntermediates(outDir);
    }
  } finally {
    client.disconnect();
  }
}

async function buildArtifacts(
  outDir: string,
  turns: ScenarioTurn[],
  client: VoxClient,
): Promise<TurnArtifact[]> {
  const artifacts: TurnArtifact[] = [];
  let cursorSec = 0;

  for (const [index, turn] of turns.entries()) {
    const stem = join(outDir, `turn-${String(index + 1).padStart(2, "0")}-${turn.speakerId}`);
    const wavPath = await synthesizeSpeech(stem, turn.voice, turn.text);
    const durationSec = await probeDuration(wavPath);
    const silencePath =
      turn.pauseAfterMs > 0 ? await synthesizeSilence(`${stem}-silence.wav`, turn.pauseAfterMs / 1000) : undefined;
    const transcription = await client.transcribeFile(wavPath, "parakeet:v3");

    artifacts.push({
      index,
      speakerId: turn.speakerId,
      voice: turn.voice,
      text: turn.text,
      wavPath,
      silencePath,
      durationSec,
      startSec: cursorSec,
      endSec: cursorSec + durationSec,
      transcription,
    });

    cursorSec += durationSec + turn.pauseAfterMs / 1000;
  }

  return artifacts;
}

function buildGroundTruth(artifacts: TurnArtifact[]): EvaluationReport["groundTruth"] {
  const transcript = artifacts.map((artifact) => artifact.transcription.text).join(" ").trim();
  const speakers = artifacts.map((artifact) => ({
    speakerId: artifact.speakerId,
    start: roundTime(artifact.startSec),
    end: roundTime(artifact.endSec),
    confidence: 1,
  }));

  const words: ReferenceWord[] = artifacts.flatMap((artifact) =>
    artifact.transcription.words.map((word) => ({
      ...word,
      start: roundTime(word.start + artifact.startSec),
      end: roundTime(word.end + artifact.startSec),
      speakerId: artifact.speakerId,
    })),
  );

  return {
    transcript,
    speakers,
    words,
  };
}

async function synthesizeSpeech(stem: string, voice: string, text: string): Promise<string> {
  const aiffPath = `${stem}.aiff`;
  const wavPath = `${stem}.wav`;

  await run(["say", "-v", voice, "-o", aiffPath, text]);
  await run(["afconvert", "-f", "WAVE", "-d", "LEF32@16000", "-c", "1", aiffPath, wavPath]);
  rmSync(aiffPath, { force: true });

  return wavPath;
}

async function synthesizeSilence(path: string, durationSec: number): Promise<string> {
  await run([
    "ffmpeg",
    "-y",
    "-f",
    "lavfi",
    "-i",
    "anullsrc=r=16000:cl=mono",
    "-t",
    durationSec.toFixed(3),
    path,
  ]);
  return path;
}

async function concatArtifacts(artifacts: TurnArtifact[], outputPath: string): Promise<void> {
  const concatManifest = outputPath.replace(/\.wav$/, ".txt");
  const lines: string[] = [];

  for (const artifact of artifacts) {
    lines.push(`file '${escapeForConcat(artifact.wavPath)}'`);
    if (artifact.silencePath) {
      lines.push(`file '${escapeForConcat(artifact.silencePath)}'`);
    }
  }

  writeFileSync(concatManifest, `${lines.join("\n")}\n`);
  await run([
    "ffmpeg",
    "-y",
    "-f",
    "concat",
    "-safe",
    "0",
    "-i",
    concatManifest,
    "-c",
    "copy",
    outputPath,
  ]);
}

function evaluateAnnotation(
  annotation: FileAnnotationResult,
  groundTruth: EvaluationReport["groundTruth"],
): AnnotationEvaluation {
  const predictedSpeakers = uniqueSpeakerIds(annotation.speakers, annotation.words);
  const referenceSpeakers = Array.from(new Set(groundTruth.speakers.map((speaker) => speaker.speakerId)));
  const mapping = bestSpeakerMapping(annotation.speakers, groundTruth.speakers, predictedSpeakers, referenceSpeakers);

  let coveredWordCount = 0;
  let correctWordCount = 0;

  for (const word of groundTruth.words) {
    const predicted = lookupSpeakerAtTime(annotation, midpoint(word.start, word.end));
    if (!predicted) {
      continue;
    }
    coveredWordCount += 1;
    const mapped = mapping[predicted] ?? predicted;
    if (mapped == word.speakerId) {
      correctWordCount += 1;
    }
  }

  return {
    speakerMapping: mapping,
    referenceWordCount: groundTruth.words.length,
    coveredWordCount,
    speakerAccuracy: coveredWordCount > 0 ? correctWordCount / coveredWordCount : 0,
    predictedSpeakerCount: predictedSpeakers.length,
    referenceSpeakerCount: referenceSpeakers.length,
  };
}

function lookupSpeakerAtTime(annotation: FileAnnotationResult, timeSec: number): string | undefined {
  const segmentMatch = annotation.speakers.find((segment) => timeSec >= segment.start && timeSec <= segment.end);
  if (segmentMatch) {
    return segmentMatch.speakerId;
  }

  const wordMatch = annotation.words.find((word) => {
    if (!word.speakerId) {
      return false;
    }
    return timeSec >= word.start && timeSec <= word.end;
  });
  return wordMatch?.speakerId ?? undefined;
}

function bestSpeakerMapping(
  predictedSegments: SpeakerSegment[],
  referenceSegments: SpeakerSegment[],
  predictedIds: string[],
  referenceIds: string[],
): Record<string, string> {
  if (predictedIds.length === 0 || referenceIds.length === 0) {
    return {};
  }

  const limitedPredicted = predictedIds.slice(0, 4);
  const limitedReference = referenceIds.slice(0, 4);
  const permutations = permute(limitedReference);
  let bestScore = -1;
  let bestMapping: Record<string, string> = {};

  for (const permutation of permutations) {
    const mapping: Record<string, string> = {};
    for (const [index, predictedId] of limitedPredicted.entries()) {
      mapping[predictedId] = permutation[index % permutation.length];
    }

    const score = scoreSpeakerMapping(predictedSegments, referenceSegments, mapping);
    if (score > bestScore) {
      bestScore = score;
      bestMapping = mapping;
    }
  }

  return bestMapping;
}

function scoreSpeakerMapping(
  predictedSegments: SpeakerSegment[],
  referenceSegments: SpeakerSegment[],
  mapping: Record<string, string>,
): number {
  let score = 0;

  for (const predicted of predictedSegments) {
    const mappedSpeaker = mapping[predicted.speakerId];
    if (!mappedSpeaker) {
      continue;
    }

    for (const reference of referenceSegments) {
      if (reference.speakerId !== mappedSpeaker) {
        continue;
      }
      score += overlapDuration(predicted.start, predicted.end, reference.start, reference.end);
    }
  }

  return score;
}

function overlapDuration(aStart: number, aEnd: number, bStart: number, bEnd: number): number {
  return Math.max(0, Math.min(aEnd, bEnd) - Math.max(aStart, bStart));
}

function uniqueSpeakerIds(segments: SpeakerSegment[], words: AttributedWordTiming[]): string[] {
  const ids = new Set<string>();
  for (const segment of segments) {
    ids.add(segment.speakerId);
  }
  for (const word of words) {
    if (word.speakerId) {
      ids.add(word.speakerId);
    }
  }
  return Array.from(ids);
}

function permute(values: string[]): string[][] {
  if (values.length <= 1) {
    return [values];
  }

  const output: string[][] = [];
  for (const [index, value] of values.entries()) {
    const rest = values.slice(0, index).concat(values.slice(index + 1));
    for (const permutation of permute(rest)) {
      output.push([value, ...permutation]);
    }
  }
  return output;
}

function midpoint(start: number, end: number): number {
  return start + (end - start) / 2;
}

function roundTime(value: number): number {
  return Math.round(value * 1000) / 1000;
}

async function probeDuration(path: string): Promise<number> {
  const output = await runAndCapture(["afinfo", path]);
  const match = output.match(/estimated duration:\s+([0-9.]+)\s+sec/i);
  const duration = Number(match?.[1] ?? "");
  if (!Number.isFinite(duration) || duration <= 0) {
    throw new Error(`Could not read duration for ${path}`);
  }
  return duration;
}

async function waitForDaemon(client: VoxClient): Promise<void> {
  const deadline = Date.now() + 15_000;
  let lastError: Error | null = null;

  while (Date.now() < deadline) {
    try {
      await client.connect();
      await client.health();
      return;
    } catch (error) {
      lastError = error instanceof Error ? error : new Error(String(error));
      client.disconnect();
      await Bun.sleep(250);
    }
  }

  throw lastError ?? new Error("Timed out waiting for Vox daemon. Start voxd first or pass --port.");
}

function cleanupIntermediates(outDir: string): void {
  const entries = existsSync(outDir) ? readdirSync(outDir) : [];
  for (const entry of entries) {
    if (
      entry.endsWith(".txt") ||
      (entry.startsWith("turn-") && entry.endsWith(".wav")) ||
      (entry.startsWith("turn-") && entry.endsWith("-silence.wav"))
    ) {
      rmSync(join(outDir, entry), { force: true });
    }
  }
}

function printSummary(report: EvaluationReport, reportPath: string): void {
  console.log(`output: ${report.outputDir}`);
  console.log(`audio: ${report.combinedAudioPath}`);
  console.log(`report: ${reportPath}`);
  console.log(`turns: ${report.turns.length}`);
  console.log(`reference speakers: ${new Set(report.groundTruth.speakers.map((speaker) => speaker.speakerId)).size}`);
  console.log(`reference words: ${report.groundTruth.words.length}`);
  console.log(`combined transcript: ${report.combinedTranscription.text}`);

  if (report.annotation) {
    const evaluation = report.annotation.evaluation;
    console.log(`annotation speakers: ${evaluation.predictedSpeakerCount}`);
    console.log(`speaker accuracy: ${(evaluation.speakerAccuracy * 100).toFixed(1)}%`);
    console.log(`covered words: ${evaluation.coveredWordCount}/${evaluation.referenceWordCount}`);
  } else if (report.annotationError) {
    console.log(`annotation unavailable: ${report.annotationError}`);
  }
}

function readOption(args: string[], name: string): string | undefined {
  const index = args.indexOf(name);
  if (index === -1) {
    return undefined;
  }
  return args[index + 1];
}

async function run(cmd: string[]): Promise<void> {
  const proc = Bun.spawn(cmd, {
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);

  if (exitCode !== 0) {
    throw new Error(`${cmd[0]} failed with exit code ${exitCode}: ${stderr || stdout}`.trim());
  }
}

async function runAndCapture(cmd: string[]): Promise<string> {
  const proc = Bun.spawn(cmd, {
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);

  if (exitCode !== 0) {
    throw new Error(`${cmd[0]} failed with exit code ${exitCode}: ${stderr || stdout}`.trim());
  }

  return stdout;
}

function escapeForConcat(path: string): string {
  return path.replace(/'/g, "'\\''");
}

await main(process.argv.slice(2));
