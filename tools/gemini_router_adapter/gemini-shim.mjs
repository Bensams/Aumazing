#!/usr/bin/env node

// Munder Difflin currently tries to resume Gemini sessions after a restart.
// Gemini CLI's resume index is not stable when the API is behind our adapter,
// so start Michael with a fresh session instead.
const args = process.argv.slice(2);
const filtered = [];
for (let i = 0; i < args.length; i += 1) {
  if (args[i] === "--resume" || args[i] === "-r") {
    i += 1;
    continue;
  }
  if (args[i] === "--continue" || args[i] === "-c") continue;
  filtered.push(args[i]);
}

const realGemini = "C:\\Users\\bened\\AppData\\Roaming\\npm\\gemini.cmd";
const { spawn } = await import("node:child_process");
const child = spawn(realGemini, filtered, {
  stdio: "inherit",
  // Windows cannot spawn a .cmd file directly without a shell.
  shell: true,
  env: process.env,
});
child.on("exit", (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  process.exit(code ?? 1);
});
