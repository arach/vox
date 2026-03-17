import { afterAll, beforeAll, describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { createServer } from "net";
import { VoxClient } from "../src/client.ts";

const E2E_ENABLED = process.env.VOX_E2E === "1";
const maybeDescribe = E2E_ENABLED ? describe : describe.skip;
const REPO_ROOT = join(import.meta.dir, "../../..");
const DAEMON_BINARY = join(REPO_ROOT, "swift/.build/debug/voxd");

const corpus = [
  {
    label: "quick-reply",
    text: "Sounds good. Let me take a look at the pull request and I'll get back to you by end of day.",
    expectedWords: ["sounds", "good", "pull", "request", "end", "day"],
  },
  {
    label: "code-comment",
    text: "This function handles the retry logic for failed API calls. It uses exponential backoff with a maximum of three retries.",
    expectedWords: ["function", "retry", "api", "exponential", "backoff", "three"],
  },
  {
    label: "single-word",
    text: "Yes.",
    expectedWords: ["yes"],
  },
] as const;

maybeDescribe("Vox file transcription e2e", () => {
  let client: VoxClient;
  let daemon: Bun.Subprocess | null = null;
  let tempHome = "";
  let port = 0;

  beforeAll(async () => {
    if (!existsSync(DAEMON_BINARY)) {
      throw new Error(`Missing daemon binary at ${DAEMON_BINARY}. Run bun run build first.`);
    }

    tempHome = mkdtempSync(join(tmpdir(), "vox-e2e-home-"));
    port = await reservePort();
    daemon = Bun.spawn([DAEMON_BINARY, "--port", String(port)], {
      cwd: REPO_ROOT,
      env: {
        ...process.env,
        VOX_HOME: tempHome,
      },
      stdout: "ignore",
      stderr: "ignore",
    });

    client = new VoxClient({
      clientId: "vox-e2e",
      port,
    });

    await waitForDaemon(client);
    await client.preloadModel();
  }, 300_000);

  afterAll(async () => {
    client?.disconnect();
    if (daemon && daemon.exitCode === null) {
      daemon.kill();
      await daemon.exited;
    }
    if (tempHome) {
      rmSync(tempHome, { recursive: true, force: true });
    }
  });

  for (const testCase of corpus) {
    test(
      testCase.label,
      async () => {
        const audioPath = await synthesizeSpeech(testCase.label, testCase.text);
        try {
          const result = await client.transcribeFile(audioPath);
          const normalized = normalize(result.text);

          expect(result.text.length).toBeGreaterThan(0);
          for (const word of testCase.expectedWords) {
            expect(normalized).toContain(normalize(word));
          }
        } finally {
          rmSync(audioPath.replace(/\.wav$/, ".aiff"), { force: true });
          rmSync(audioPath, { force: true });
        }
      },
      300_000,
    );
  }
});

async function reservePort(): Promise<number> {
  return await new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        server.close();
        reject(new Error("Failed to reserve an ephemeral port."));
        return;
      }

      const { port } = address;
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(port);
      });
    });
  });
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
      await Bun.sleep(200);
    }
  }

  throw lastError ?? new Error("Timed out waiting for Vox daemon.");
}

async function synthesizeSpeech(label: string, text: string): Promise<string> {
  const stem = join(tmpdir(), `vox-e2e-${label}-${Date.now()}`);
  const aiffPath = `${stem}.aiff`;
  const wavPath = `${stem}.wav`;

  await run(["say", "-v", "Samantha", "-o", aiffPath, text]);
  await run(["afconvert", "-f", "WAVE", "-d", "LEF32@16000", "-c", "1", aiffPath, wavPath]);

  return wavPath;
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

function normalize(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
