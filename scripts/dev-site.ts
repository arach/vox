const cwd = decodeURIComponent(new URL("../", import.meta.url).pathname);

const docs = Bun.spawn(["bun", "run", "--cwd", "docs-site", "dev", "--host", "127.0.0.1"], {
  cwd,
  stdout: "inherit",
  stderr: "inherit",
});

const site = Bun.spawn(["bun", "run", "--cwd", "site", "dev"], {
  cwd,
  stdout: "inherit",
  stderr: "inherit",
});

let stopping = false;
function stop() {
  if (stopping) return;
  stopping = true;
  site.kill();
  docs.kill();
}

process.on("SIGINT", stop);
process.on("SIGTERM", stop);

const result = await Promise.race([
  site.exited.then((exitCode) => ({ exitCode, process: "site" })),
  docs.exited.then((exitCode) => ({ exitCode, process: "docs" })),
]);

stop();
await Promise.all([site.exited, docs.exited]);

if (result.exitCode !== 0) {
  console.error(`${result.process} dev server exited with code ${result.exitCode}`);
}
process.exit(result.exitCode);
