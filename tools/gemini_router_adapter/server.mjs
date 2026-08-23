#!/usr/bin/env node

import http from "node:http";
import fs from "node:fs";

const listenHost = process.env.ADAPTER_HOST || "127.0.0.1";
const listenPort = Number(process.env.ADAPTER_PORT || 8787);
const routerBaseUrl = (process.env.ROUTER_BASE_URL || "http://127.0.0.1:20128/v1").replace(/\/+$/, "");
const routerApiKey = process.env.ROUTER_API_KEY || "";
const primaryModel = process.env.ROUTER_PRIMARY_MODEL || "gemipro/gemini-3.1-pro-openai";
const fallbackModel = process.env.ROUTER_FALLBACK_MODEL || "gemi/gemini-3-7-flash-openai";
const routingMode = (process.env.ROUTER_MODEL || "auto").toLowerCase();

// Opt-in diagnostics: set ADAPTER_DIAG to a file path to record how requests
// arrive from the caller. Never throws, and stays inert when unset.
const diagFile = process.env.ADAPTER_DIAG || "";
function diag(build) {
  if (!diagFile) return;
  try {
    const line = JSON.stringify({ ts: new Date().toISOString(), ...build() });
    fs.appendFileSync(diagFile, line + "\n");
  } catch {}
}

function json(res, status, value) {
  const body = JSON.stringify(value);
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": Buffer.byteLength(body),
  });
  res.end(body);
}

function isRetryableRouterError(status, errorText = "") {
  if ([408, 409, 425, 429, 500, 502, 503, 504].includes(status)) return true;
  return /rate limit|timeout|temporarily|overloaded|busy|unavailable|server error|context length/i.test(errorText);
}

function promptIsComplex(body) {
  const messages = Array.isArray(body?.messages) ? body.messages : [];
  const text = JSON.stringify(messages);
  const toolCount = Array.isArray(body?.tools) ? body.tools.length : 0;
  const hasImages = text.includes('"image_url"');
  const hasSearch = text.includes("googleSearch");
  const longPrompt = text.length > 3500;
  return toolCount > 0 || hasImages || hasSearch || longPrompt;
}

function modelCandidates(body) {
  if (routingMode && routingMode !== "auto") return [routingMode];
  return promptIsComplex(body)
    ? [primaryModel, fallbackModel]
    : [fallbackModel, primaryModel];
}

async function fetchWithFallback(openaiBody, authorization) {
  const candidates = modelCandidates(openaiBody);
  let lastStatus = 0;
  let lastErrorText = "";
  for (const model of candidates) {
    const upstream = await fetch(`${routerBaseUrl}/chat/completions`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(authorization ? { authorization } : {}),
      },
      body: JSON.stringify({ ...openaiBody, model }),
    });
    if (upstream.ok) return { upstream, model };
    lastStatus = upstream.status;
    lastErrorText = await upstream.text();
    if (!isRetryableRouterError(lastStatus, lastErrorText) || model === candidates.at(-1)) {
      return { upstream, model, errorText: lastErrorText, status: lastStatus };
    }
  }
  return { upstream: null, model: candidates[0], errorText: lastErrorText, status: lastStatus };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}"));
      } catch (error) {
        reject(new Error(`Invalid JSON request: ${error.message}`));
      }
    });
    req.on("error", reject);
  });
}

function textFromParts(parts = []) {
  return parts
    .filter((part) => typeof part?.text === "string")
    .map((part) => part.text)
    .join("");
}

function openAIContentFromParts(parts = []) {
  const content = [];
  for (const part of parts) {
    if (typeof part?.text === "string") {
      content.push({ type: "text", text: part.text });
      continue;
    }
    const inline = part?.inlineData || part?.inline_data;
    if (inline?.data && inline?.mimeType) {
      content.push({
        type: "image_url",
        image_url: {
          url: `data:${inline.mimeType};base64,${inline.data}`,
        },
      });
      continue;
    }
    const file = part?.fileData || part?.file_data;
    if (file?.fileUri) {
      content.push({
        type: "image_url",
        image_url: { url: file.fileUri },
      });
    }
  }
  return content;
}

export function geminiContentsToOpenAI(contents = []) {
  // Gemini identifies a function response only by tool name, while OpenAI pairs
  // each tool message to a specific tool_call id. Keying that map by name loses
  // parallel calls to the SAME tool: every response collapses onto the last id
  // and the earlier calls are left unanswered. Upstream then sees malformed
  // tool history and degrades to describing calls as plain text
  // ("Function call requested: ..."). Track calls in order instead and consume
  // them FIFO, preferring the earliest unanswered call of a matching name.
  const pending = [];
  let toolCounter = 0;
  return contents.map((item) => {
    const role = item.role === "model" ? "assistant" : item.role === "function" ? "tool" : item.role || "user";
    const parts = item.parts || [];
    const functionResponses = parts.filter((part) => part.functionResponse);
    if (functionResponses.length) {
      return functionResponses.map((part) => {
        const response = part.functionResponse;
        const entry =
          pending.find((c) => !c.used && c.name === response.name) ||
          pending.find((c) => !c.used);
        let toolCallId;
        if (entry) {
          entry.used = true;
          toolCallId = entry.id;
        } else {
          toolCallId = `call_gemini_${++toolCounter}`;
        }
        return {
          role: "tool",
          tool_call_id: toolCallId,
          name: response.name,
          content: JSON.stringify(response.response ?? {}),
        };
      });
    }
    const functionCalls = parts.filter((part) => part.functionCall);
    if (functionCalls.length) {
      const toolCalls = functionCalls.map((part) => {
        const call = part.functionCall;
        const id = `call_gemini_${++toolCounter}`;
        pending.push({ id, name: call.name, used: false });
        return {
          id,
          type: "function",
          function: {
            name: call.name,
            arguments: JSON.stringify(call.args || {}),
          },
        };
      });
      const text = textFromParts(parts);
      return {
        role: "assistant",
        // 9Router rejects an assistant message whose content is null,
        // even when it contains valid tool_calls. Use an empty string for
        // tool-only assistant turns.
        content: text || "",
        tool_calls: toolCalls,
      };
    }
    const content = openAIContentFromParts(parts);
    return {
      role,
      content: content.length === 1 && content[0].type === "text"
        ? content[0].text
        : content,
    };
  }).flat();
}

// Gemini CLI declares tool arguments under `parametersJsonSchema`; only older
///hand-written declarations use `parameters`. Reading just `parameters` sent
// every tool upstream with an EMPTY schema, so the model could not know the
// argument names: it guessed (`path` instead of `file_path`/`dir_path`) and,
// once those were rejected, degraded to narrating calls as plain text
// ("Function call requested: ..."). Accept both spellings.
function toolParameters(fn) {
  return fn?.parametersJsonSchema || fn?.parameters || null;
}

function toolsToOpenAI(tools = []) {
  return tools
    .flatMap((tool) => tool.functionDeclarations || [])
    .map((fn) => ({
      type: "function",
      function: {
        name: fn.name,
        description: fn.description,
        parameters: toolParameters(fn) || { type: "object", properties: {} },
      },
    }));
}

function sanitizeOpenAIMessages(messages = []) {
  return messages.map((message) => {
    const sanitized = { ...message };
    // 9Router rejects null assistant content, including valid tool-only turns.
    if (sanitized.role === "assistant" && sanitized.content == null) {
      sanitized.content = "";
    }
    // Prevent malformed tool history from breaking the whole request.
    if (sanitized.role === "tool" && sanitized.content == null) {
      sanitized.content = "{}";
    }
    if (Array.isArray(sanitized.tool_calls)) {
      sanitized.tool_calls = sanitized.tool_calls
        .filter((call) => call?.function?.name)
        .map((call) => ({
          ...call,
          function: {
            ...call.function,
            arguments: typeof call.function.arguments === "string"
              ? call.function.arguments
              : JSON.stringify(call.function.arguments || {}),
          },
        }));
    }
    return sanitized;
  });
}

function toOpenAIRequest(gemini, stream) {
  const messages = [];
  if (gemini.systemInstruction) {
    messages.push({
      role: "system",
      content: textFromParts(gemini.systemInstruction.parts || []),
    });
  }
  messages.push(...geminiContentsToOpenAI(gemini.contents || []));

  const generation = gemini.generationConfig || {};
  const request = {
    model: routingMode && routingMode !== "auto" ? routingMode : primaryModel,
    messages: sanitizeOpenAIMessages(messages),
    // Gemini CLI signals streaming by method (`:streamGenerateContent` vs
    // `:generateContent`), never with a `stream` field in the body. Keying off
    // the body made every request stream, so non-streaming callers (session
    // summary, topic generation) received an SSE body and failed on
    // JSON.parse with: Unexpected token 'd', "data: {...".
    stream,
  };
  if (typeof generation.temperature === "number") request.temperature = generation.temperature;
  if (typeof generation.topP === "number") request.top_p = generation.topP;
  if (typeof generation.topK === "number") request.top_k = generation.topK;
  if (typeof generation.maxOutputTokens === "number") request.max_tokens = generation.maxOutputTokens;

  const tools = toolsToOpenAI(gemini.tools || []);
  if (tools.length) request.tools = tools;
  return request;
}

// Gemini CLI parses `streamGenerateContent?alt=sse` with
//   /^\s*data: (.*)(?:\n\n|\r\r|\r\n\r\n)/
// so every event must be a single-line `data: <json>` frame terminated by a
// blank line. Bare newline-delimited JSON never matches that regex, leaves the
// payload sitting in the CLI's buffer, and surfaces at stream end as
// "Incomplete JSON segment at the end".
function sseEvent(value) {
  return `data: ${JSON.stringify(value)}\n\n`;
}

function geminiTextEvent(text, model) {
  return sseEvent({
    candidates: [{
      content: { role: "model", parts: [{ text }] },
    }],
    modelVersion: model,
  });
}

// name -> JSON schema, taken from the declarations the caller already sent.
export function buildToolSchemas(tools = []) {
  const schemas = new Map();
  for (const tool of tools) {
    for (const fn of tool.functionDeclarations || []) {
      if (fn?.name) schemas.set(fn.name, toolParameters(fn) || {});
    }
  }
  return schemas;
}

// The model reached through 9Router/Kie frequently invents shorter parameter
// names (`path` instead of `file_path` / `dir_path`), which the Gemini CLI
// rejects with "params must have required property 'file_path'" and wastes a
// turn retrying. Repair the call against the schema the CLI actually declared
// rather than hard-coding tool names, so every tool is covered.
export function normalizeToolArgs(name, args, schemas) {
  const schema = schemas?.get(name);
  if (!schema || !args || typeof args !== "object") return args;

  const required = Array.isArray(schema.required) ? schema.required : [];
  const declared = Object.keys(schema.properties || {});
  const missing = required.filter((key) => args[key] == null);
  if (!missing.length) return args;

  const extras = Object.keys(args).filter((key) => !declared.includes(key));
  const repaired = { ...args };

  // Unambiguous case: exactly one required field missing and one stray key.
  if (missing.length === 1 && extras.length === 1) {
    repaired[missing[0]] = repaired[extras[0]];
    delete repaired[extras[0]];
    return repaired;
  }

  // Otherwise fall back to matching a generic alias onto a `*_path` field.
  for (const key of missing) {
    const alias = extras.find(
      (candidate) =>
        candidate === "path" ||
        key.endsWith(`_${candidate}`) ||
        candidate.endsWith(`_${key}`),
    );
    if (alias) {
      repaired[key] = repaired[alias];
      delete repaired[alias];
    }
  }
  return repaired;
}

// `gemi/gemini-3-7-flash-openai` intermittently NARRATES its tool calls as
// plain text instead of emitting them, e.g.
//   Function call requested: list_directory
//   Arguments: {"dir_path":"..."}
// (reproduced against the router directly, with this adapter out of the path).
// The CLI then shows an unexecutable message and the text pollutes the history,
// which makes the model repeat the pattern. Recover real calls from that text.
const NARRATION_MARKER = "Function call requested:";

// Scan out one balanced JSON object starting at/after `from`, quote-aware.
function extractJsonObject(text, from) {
  let i = from;
  while (i < text.length && text[i] !== "{") i++;
  if (text[i] !== "{") return null;
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let j = i; j < text.length; j++) {
    const ch = text[j];
    if (inString) {
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) return { json: text.slice(i, j + 1), end: j + 1 };
    }
  }
  return null;
}

export function parseNarratedToolCalls(text) {
  const calls = [];
  const re = /Function call requested:\s*([A-Za-z0-9_.-]+)\s*[\r\n]*\s*Arguments:\s*/g;
  let match;
  while ((match = re.exec(text))) {
    const found = extractJsonObject(text, re.lastIndex);
    if (!found) continue;
    try {
      calls.push({ name: match[1], args: JSON.parse(found.json) });
    } catch {
      // Not parseable as arguments; leave this one alone.
    }
    re.lastIndex = found.end;
  }
  return calls;
}

function narratedCallEvent(call, model, schemas) {
  return sseEvent({
    candidates: [{
      content: {
        role: "model",
        parts: [{
          functionCall: {
            name: call.name,
            args: normalizeToolArgs(call.name, call.args, schemas),
          },
        }],
      },
    }],
    modelVersion: model,
  });
}

function geminiToolEvent(toolCall, model, schemas) {
  const fn = toolCall.function || {};
  let args = {};
  try {
    args = JSON.parse(fn.arguments || "{}");
  } catch {
    args = {};
  }
  const before = args;
  args = normalizeToolArgs(fn.name, args, schemas);
  diag(() => ({
    event: "toolCall",
    name: fn.name,
    knownSchema: !!schemas?.get(fn.name),
    argsBefore: Object.keys(before || {}),
    argsAfter: Object.keys(args || {}),
  }));
  return sseEvent({
    candidates: [{
      content: {
        role: "model",
        parts: [{
          functionCall: {
            name: fn.name || "unknown",
            args,
          },
        }],
      },
    }],
    modelVersion: model,
  });
}

// OpenAI usage -> Gemini usageMetadata. The harness reads these camel-case
// counters for its context/cost gauges, so the raw OpenAI keys must not leak.
function geminiUsage(usage) {
  if (!usage) return undefined;
  return {
    promptTokenCount: usage.prompt_tokens,
    candidatesTokenCount: usage.completion_tokens,
    totalTokenCount: usage.total_tokens,
  };
}

function geminiUsageEvent(usage, model) {
  if (!usage) return "";
  return sseEvent({
    usageMetadata: geminiUsage(usage),
    modelVersion: model,
  });
}

async function proxy(req, res) {
  const body = await readBody(req);
  // Gemini CLI validates `-m` against Google's own model catalog before it
  // sends a request. The caller must therefore use a valid Gemini alias such
  // as `flash`; the adapter deliberately replaces that alias with the
  // configured 9Router model.
  const wantsStream = req.url.includes(":streamGenerateContent");
  const schemas = buildToolSchemas(body.tools || []);
  diag(() => ({
    url: req.url,
    topLevelKeys: Object.keys(body),
    toolsType: Array.isArray(body.tools) ? `array[${body.tools.length}]` : typeof body.tools,
    toolWrapperKeys: (body.tools || []).map((t) => Object.keys(t || {})),
    schemaCount: schemas.size,
    schemaNames: [...schemas.keys()].slice(0, 12),
    sampleSchema: [...schemas.entries()].slice(0, 2).map(([k, v]) => ({
      name: k,
      required: v?.required,
      props: Object.keys(v?.properties || {}),
    })),
  }));
  const openaiBody = toOpenAIRequest(body, wantsStream);

  diag(() => {
    // Dump the exact tools payload once so it can be replayed against upstream.
    if (diagFile && openaiBody.tools) {
      try {
        fs.writeFileSync(
          diagFile.replace(/\.jsonl$/, "") + "-tools.json",
          JSON.stringify(openaiBody.tools, null, 1),
        );
      } catch {}
    }
    return {
      event: "upstreamRequest",
      model: openaiBody.model,
      stream: openaiBody.stream,
      toolCount: openaiBody.tools?.length ?? 0,
      toolBytes: openaiBody.tools ? JSON.stringify(openaiBody.tools).length : 0,
      messageRoles: openaiBody.messages.map((m) => m.role),
      totalBytes: JSON.stringify(openaiBody).length,
    };
  });

  const incomingAuth = req.headers.authorization;
  const authorization = routerApiKey
    ? `Bearer ${routerApiKey}`
    : incomingAuth || "";

  const routed = await fetchWithFallback(openaiBody, authorization);
  if (!routed.upstream || !routed.upstream.ok) {
    res.writeHead(routed.status || 502, { "content-type": "application/json; charset=utf-8" });
    res.end(routed.errorText || JSON.stringify({ error: { message: "Router request failed" } }));
    return;
  }
  const upstream = routed.upstream;
  const usedModel = routed.model;

  if (!openaiBody.stream) {
    const result = await upstream.json();
    const choice = result.choices?.[0];
    const message = choice?.message || {};
    const parts = [];
    if (message.content) {
      // Same narration recovery as the streaming path.
      const recovered = parseNarratedToolCalls(message.content);
      if (recovered.length) {
        for (const call of recovered) {
          parts.push({
            functionCall: {
              name: call.name,
              args: normalizeToolArgs(call.name, call.args, schemas),
            },
          });
        }
      } else {
        parts.push({ text: message.content });
      }
    }
    for (const call of message.tool_calls || []) {
      let args = {};
      try { args = JSON.parse(call.function?.arguments || "{}"); } catch {}
      parts.push({
        functionCall: {
          name: call.function?.name,
          args: normalizeToolArgs(call.function?.name, args, schemas),
        },
      });
    }
    return json(res, 200, {
      candidates: [{
        content: { role: "model", parts },
        // Gemini uses upper-case finish reasons; OpenAI sends "stop"/"length".
        finishReason: String(choice?.finish_reason || "stop").toUpperCase(),
      }],
      usageMetadata: geminiUsage(result.usage),
      modelVersion: result.model || usedModel,
    });
  }

  res.writeHead(200, {
    // Gemini CLI requests `?alt=sse` and parses this endpoint as SSE.
    "content-type": "text/event-stream; charset=utf-8",
    "cache-control": "no-cache",
    connection: "keep-alive",
  });

  const reader = upstream.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let lastModel = usedModel;
  let usage;
  let emittedContent = false;
  let emittedToolCall = false;

  // Text is released with a short hold-back so the narration marker can be
  // detected even when it straddles two chunks. Once narration starts, the rest
  // is captured instead of forwarded, and converted to real calls at stream end.
  let held = "";
  let narration = "";
  let inNarration = false;

  const pushText = (text) => {
    if (inNarration) {
      narration += text;
      return;
    }
    held += text;
    const idx = held.indexOf(NARRATION_MARKER);
    if (idx !== -1) {
      const prefix = held.slice(0, idx);
      if (prefix) {
        emittedContent = true;
        res.write(geminiTextEvent(prefix, lastModel));
      }
      inNarration = true;
      narration = held.slice(idx);
      held = "";
      return;
    }
    const keep = Math.min(held.length, NARRATION_MARKER.length - 1);
    const flush = held.slice(0, held.length - keep);
    held = held.slice(held.length - keep);
    if (flush) {
      emittedContent = true;
      res.write(geminiTextEvent(flush, lastModel));
    }
  };

  const emit = (chunk) => {
    const delta = chunk.choices?.[0]?.delta || {};
    if (chunk.model) lastModel = chunk.model;
    if (chunk.usage) usage = chunk.usage;
    if (delta.content) {
      pushText(delta.content);
    }
    for (const call of delta.tool_calls || []) {
      emittedToolCall = true;
      res.write(geminiToolEvent(call, lastModel, schemas));
    }
  };

  const consumeLine = (line) => {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) return;
    const payload = trimmed.slice(5).trim();
    if (!payload || payload === "[DONE]") return;
    try { emit(JSON.parse(payload)); } catch {}
  };

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() || "";
    for (const line of lines) consumeLine(line);
  }
  if (buffer) consumeLine(buffer);

  if (inNarration) {
    const recovered = parseNarratedToolCalls(narration);
    diag(() => ({
      event: "narration",
      recovered: recovered.length,
      names: recovered.map((c) => c.name),
      textLength: narration.length,
    }));
    if (recovered.length) {
      // Replace the narration with the calls it was describing; the text itself
      // is dropped so it never re-enters the history and re-teaches the habit.
      for (const call of recovered) {
        emittedToolCall = true;
        res.write(narratedCallEvent(call, lastModel, schemas));
      }
    } else {
      // Nothing parseable: forward it as ordinary text rather than lose it.
      emittedContent = true;
      res.write(geminiTextEvent(narration, lastModel));
    }
  } else if (held) {
    emittedContent = true;
    res.write(geminiTextEvent(held, lastModel));
  }

  res.write(geminiUsageEvent(usage, lastModel));
  // Gemini CLI requires a terminal candidate with a finish reason. OpenAI
  // streams commonly end with only the transport closing (or [DONE]), which
  // otherwise leaves the CLI reporting "Model stream ended without a finish
  // reason".
  res.write(sseEvent({
    candidates: [{
      content: { role: "model", parts: [] },
      finishReason: "STOP",
    }],
    modelVersion: lastModel,
  }));
  // Gemini's native stream expects JSON `data:` events only. Unlike the
  // OpenAI stream, it does not use `data: [DONE]`; emitting that sentinel
  // makes Gemini CLI try to parse "[DONE]" as JSON.
  res.end();
}

const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    return json(res, 200, {
      ok: true,
      routerBaseUrl,
      model: routingMode === "auto" ? `${primaryModel} -> ${fallbackModel}` : routingMode,
    });
  }
  if (req.method !== "POST" || !req.url.includes("/models/")) {
    return json(res, 404, { error: { message: "Expected Gemini generateContent request" } });
  }
  try {
    await proxy(req, res);
  } catch (error) {
    json(res, 502, { error: { message: error.message } });
  }
});

server.listen(listenPort, listenHost, () => {
  console.log(`Gemini router adapter listening at http://${listenHost}:${listenPort}`);
  console.log(`Forwarding to ${routerBaseUrl} using models ${primaryModel} -> ${fallbackModel}`);
});
