#!/usr/bin/env node
// Report one Codex `exec --json` run to the ii-os agent-usage API.
//
// Usage: report-codex-exec-usage.mjs LOG [EXIT_STATUS]
//
// agent_execution runs this standalone file (no dependencies) on the trusted
// controller after every work-ticket run, including failed ones, with a clean
// environment:
//   II_OS_AGENT_USAGE_URL            ii-os API base (https; http only for 127.0.0.1/localhost)
//   II_OS_AGENT_USAGE_WORKSPACE_ID   workspace the reporting key belongs to
//   AGENT_USAGE_KEY_FILE             file holding the workspace reporting key
//   II_OS_AGENT_EXECUTION_ID         the run's execution id (binds the event id)
//   EVALS_EXECUTION_ORIGIN           local | cloud | unknown
//   II_AGENT_USAGE_SOURCE            codex (the only supported source)
//   II_AGENT_BILLING_MODE            subscription_included | metered_api | metered_credits | cloud_provider | unknown
//   II_AGENT_BILLING_PROVIDER        e.g. openai
//   II_AGENT_MODEL                   the configured model (optional)
//   II_AGENT_BILLING_PLAN, II_AGENT_SUBSCRIPTION_COST_USD_MONTHLY (optional)
// It POSTs {"events":[<ii.agent-usage.event.v1>]} to
// ${II_OS_AGENT_USAGE_URL}/v1/workspaces/<workspace>/agent-usage/events with the
// key as a bearer token, and prints exactly one receipt line:
//   {"reported":true,"eventId":"<64 hex>","source":"codex","model":<string|null>,"totalTokens":<int>}
// The transcript itself is never sent; only token counts and a session hash.

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

// API-equivalent USD per million tokens. The operator keeps this table current
// with the provider's published prices; a model missing here is still reported,
// with its tokens and a zero estimated cost.
const OPENAI_TOKEN_PRICES = {
  "gpt-5.6": {
    inputUsdPerMillion: 4,
    cachedInputUsdPerMillion: 0.4,
    outputUsdPerMillion: 20,
    longContext: { thresholdInputTokens: 272_000, inputUsdPerMillion: 8, cachedInputUsdPerMillion: 0.8, outputUsdPerMillion: 30 }
  },
  "gpt-5.6-sol": {
    inputUsdPerMillion: 4,
    cachedInputUsdPerMillion: 0.4,
    outputUsdPerMillion: 20,
    longContext: { thresholdInputTokens: 272_000, inputUsdPerMillion: 8, cachedInputUsdPerMillion: 0.8, outputUsdPerMillion: 30 }
  },
  "gpt-5.6-terra": {
    inputUsdPerMillion: 2,
    cachedInputUsdPerMillion: 0.2,
    outputUsdPerMillion: 12,
    longContext: { thresholdInputTokens: 272_000, inputUsdPerMillion: 4, cachedInputUsdPerMillion: 0.4, outputUsdPerMillion: 18 }
  },
  "gpt-5.6-luna": {
    inputUsdPerMillion: 0.2,
    cachedInputUsdPerMillion: 0.02,
    outputUsdPerMillion: 1.2,
    longContext: { thresholdInputTokens: 272_000, inputUsdPerMillion: 0.4, cachedInputUsdPerMillion: 0.04, outputUsdPerMillion: 1.8 }
  },
  "gpt-5.5": {
    inputUsdPerMillion: 5,
    cachedInputUsdPerMillion: 0.5,
    outputUsdPerMillion: 30,
    longContext: { thresholdInputTokens: 272_000, inputUsdPerMillion: 10, cachedInputUsdPerMillion: 1, outputUsdPerMillion: 45 }
  },
  "gpt-5.5-2026-04-23": {
    inputUsdPerMillion: 5,
    cachedInputUsdPerMillion: 0.5,
    outputUsdPerMillion: 30,
    longContext: { thresholdInputTokens: 272_000, inputUsdPerMillion: 10, cachedInputUsdPerMillion: 1, outputUsdPerMillion: 45 }
  },
  "gpt-5.4": {
    inputUsdPerMillion: 2.5,
    cachedInputUsdPerMillion: 0.25,
    outputUsdPerMillion: 15,
    longContext: { thresholdInputTokens: 272_000, inputUsdPerMillion: 5, cachedInputUsdPerMillion: 0.5, outputUsdPerMillion: 22.5 }
  },
  "gpt-5.4-mini": { inputUsdPerMillion: 0.75, cachedInputUsdPerMillion: 0.075, outputUsdPerMillion: 4.5 },
  "gpt-5.3-codex": { inputUsdPerMillion: 1.75, cachedInputUsdPerMillion: 0.175, outputUsdPerMillion: 14 }
};

const [logPath, exitStatusValue = "0"] = process.argv.slice(2);
if (!logPath) throw new Error("Usage: report-codex-exec-usage.mjs LOG [EXIT_STATUS]");

const endpointBase = validateEndpoint(required("II_OS_AGENT_USAGE_URL")).replace(/\/$/, "");
const workspaceId = safeIdentifier(required("II_OS_AGENT_USAGE_WORKSPACE_ID"), 128, "II_OS_AGENT_USAGE_WORKSPACE_ID");
// The execution id makes the event id unique per run: two runs with identical
// transcripts (for example two failures before any output) stay two events.
const executionId = safeIdentifier(required("II_OS_AGENT_EXECUTION_ID"), 256, "II_OS_AGENT_EXECUTION_ID");
const token = readToken(required("AGENT_USAGE_KEY_FILE"));
const source = process.env.II_AGENT_USAGE_SOURCE?.trim() || "codex";
if (source !== "codex") throw new Error("invalid agent usage source");
const origin = required("EVALS_EXECUTION_ORIGIN");
if (!["local", "cloud", "unknown"].includes(origin)) throw new Error("invalid execution origin");
const billingMode = process.env.II_AGENT_BILLING_MODE?.trim() || "unknown";
if (!["subscription_included", "metered_api", "metered_credits", "cloud_provider", "unknown"].includes(billingMode)) {
  throw new Error("invalid billing mode");
}
const billingProvider = process.env.II_AGENT_BILLING_PROVIDER?.trim() || "openai";
if (billingProvider.length > 64 || !/^[A-Za-z0-9][A-Za-z0-9._:/-]*$/.test(billingProvider)) throw new Error("invalid billing provider");
const billingPlan = safeOptionalIdentifier(process.env.II_AGENT_BILLING_PLAN, 128);
const subscriptionCostUsdMonthly = optionalMoney(process.env.II_AGENT_SUBSCRIPTION_COST_USD_MONTHLY);
if (subscriptionCostUsdMonthly !== null && billingMode !== "subscription_included") {
  throw new Error("a subscription cost requires subscription_included billing");
}

const log = fs.readFileSync(logPath, "utf8");
const events = log.split(/\r?\n/).flatMap((line) => {
  try {
    const value = JSON.parse(line);
    return value && typeof value === "object" && !Array.isArray(value) ? [value] : [];
  } catch {
    return [];
  }
});
const completed = events.filter((event) => event.type === "turn.completed");
const usage = completed.reduce((sum, event) => addCodexUsage(sum, object(event.usage)), emptyUsage());
const sessionId = events.find((event) => event.type === "thread.started")?.thread_id;
const model =
  safeOptionalIdentifier(process.env.II_AGENT_MODEL, 160) ??
  modelFromEvents(events) ??
  modelFromRollout(sessionId) ??
  modelFromConfig();
if (!model) {
  // An unlabelled report still carries its tokens, but the reader has no rate
  // to price them with. Say so on the run rather than reading as free.
  process.stderr.write(
    "agent-usage: could not determine the model for this run; tokens will be reported without a rate. " +
      "Set II_AGENT_MODEL on the reporting step to fix it.\n"
  );
}
const estimatedCostUsd = model ? estimateOpenAiTokenCostUsd(model, usage) : null;
if (model && estimatedCostUsd === null) {
  process.stderr.write(`agent-usage: no token price is configured for ${model}; tokens will be reported without a rate.\n`);
}
const exitStatus = Number.parseInt(exitStatusValue, 10);
const eventId = crypto.createHash("sha256")
  .update(`${executionId}\n${crypto.createHash("sha256").update(log).digest("hex")}\n${exitStatusValue}`)
  .digest("hex");
const totalTokens = usage.totalTokens || usage.inputTokens + usage.outputTokens;
const actualCostUsd = actualCostFor(billingMode, estimatedCostUsd);
// Every key here is accepted by the backend's AgentUsageEvent.parse; unknown
// keys are rejected, so nothing else may be added.
const event = {
  schemaVersion: "ii.agent-usage.event.v1",
  eventId,
  occurredAt: new Date().toISOString(),
  source,
  eventType: Number.isInteger(exitStatus) && exitStatus === 0 ? "codex.exec.completed" : "codex.exec.failed",
  executionOrigin: origin,
  ...(model ? { model } : {}),
  billing: {
    mode: billingMode,
    provider: billingProvider,
    ...(billingPlan ? { plan: billingPlan } : {}),
    ...(subscriptionCostUsdMonthly !== null ? { subscriptionCostUsdMonthly } : {})
  },
  ...(typeof sessionId === "string" && sessionId
    ? { sessionFingerprint: crypto.createHash("sha256").update(`${source}\n${sessionId}`).digest("hex") }
    : {}),
  metrics: {
    prompts: 1,
    sessions: typeof sessionId === "string" && sessionId ? 1 : 0,
    requests: completed.length,
    inputTokens: usage.inputTokens,
    cachedInputTokens: usage.cachedInputTokens,
    cacheReadInputTokens: 0,
    cacheCreationInputTokens: 0,
    outputTokens: usage.outputTokens,
    reasoningOutputTokens: usage.reasoningOutputTokens,
    totalTokens,
    costUsd: roundCostUsd(estimatedCostUsd ?? 0),
    apiEquivalentCostUsd: roundCostUsd(estimatedCostUsd ?? 0),
    ...(actualCostUsd !== null ? { actualCostUsd: roundCostUsd(actualCostUsd) } : {}),
    usageEvents: 1,
    claudeOtelRequests: 0,
    claudeStatuslineSamples: 0,
    codexTokenEvents: completed.length
  }
};

const endpoint = `${endpointBase}/v1/workspaces/${encodeURIComponent(workspaceId)}/agent-usage/events`;
const response = await fetch(endpoint, {
  method: "POST",
  redirect: "error",
  signal: AbortSignal.timeout(20_000),
  headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
  body: JSON.stringify({ events: [event] })
});
if (!response.ok) throw new Error(`agent usage ingest failed with HTTP ${response.status}`);
process.stdout.write(`${JSON.stringify({ reported: true, eventId, source, model: model ?? null, totalTokens })}\n`);

function emptyUsage() {
  return { inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 0 };
}

function addCodexUsage(target, value) {
  target.inputTokens += integer(value.input_tokens);
  target.cachedInputTokens += integer(value.cached_input_tokens);
  target.outputTokens += integer(value.output_tokens);
  target.reasoningOutputTokens += integer(value.reasoning_output_tokens);
  target.totalTokens += integer(value.total_tokens);
  return target;
}

function integer(value) {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? Math.trunc(number) : 0;
}

function object(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function estimateOpenAiTokenCostUsd(name, value) {
  const pricing = OPENAI_TOKEN_PRICES[name.trim().toLowerCase()];
  if (!pricing) return null;
  const effective = pricing.longContext && value.inputTokens > pricing.longContext.thresholdInputTokens ? pricing.longContext : pricing;
  const cachedInputTokens = Math.max(0, Math.min(value.cachedInputTokens, value.inputTokens));
  const freshInputTokens = Math.max(0, value.inputTokens - cachedInputTokens);
  return (
    (freshInputTokens * effective.inputUsdPerMillion) +
    (cachedInputTokens * effective.cachedInputUsdPerMillion) +
    (Math.max(0, value.outputTokens) * effective.outputUsdPerMillion)
  ) / 1_000_000;
}

function roundCostUsd(value) {
  if (!Number.isFinite(value) || value <= 0) return 0;
  return Number(value.toFixed(9));
}

function actualCostFor(mode, apiEquivalentCostUsd) {
  if (mode === "subscription_included") return 0;
  if (mode === "metered_api" && apiEquivalentCostUsd !== null) return apiEquivalentCostUsd;
  return null;
}

function optionalMoney(value) {
  if (value === undefined || value.trim() === "") return null;
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 1_000_000) throw new Error("invalid monthly subscription cost");
  return roundCostUsd(parsed);
}

/// The effective model of a non-ephemeral run, from its Codex rollout.
function modelFromRollout(threadId) {
  const sessions = path.join(codexHome(), "sessions");
  let newestMatching = null;
  let newest = null;
  const walk = (directory, depth) => {
    if (depth > 5) return;
    let entries;
    try {
      entries = fs.readdirSync(directory, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        walk(full, depth + 1);
      } else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
        try {
          const modified = fs.statSync(full).mtimeMs;
          if (!newest || modified > newest.modified) newest = { full, modified };
          if (typeof threadId === "string" && threadId && entry.name.includes(threadId) &&
              (!newestMatching || modified > newestMatching.modified)) {
            newestMatching = { full, modified };
          }
        } catch {
          // A transcript that vanished mid-walk is not an error worth failing on.
        }
      }
    }
  };
  walk(sessions, 0);
  const selected = newestMatching ?? newest;
  if (!selected) return null;
  let contents;
  try {
    contents = fs.readFileSync(selected.full, "utf8");
  } catch {
    return null;
  }
  for (const line of contents.split("\n")) {
    if (!line.includes('"model"')) continue;
    let parsed;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    for (const candidate of [
      object(parsed).model,
      object(object(parsed).payload).model,
      object(object(parsed).turn_context).model,
      object(object(parsed).item).model
    ]) {
      const found = safeOptionalIdentifier(candidate, 160);
      if (found) return found;
    }
  }
  return null;
}

// `codex exec --ephemeral` writes no rollout; the top-level configured model is
// then the only durable model source left after the process exits.
function modelFromConfig() {
  let contents;
  try {
    contents = fs.readFileSync(path.join(codexHome(), "config.toml"), "utf8");
  } catch {
    return null;
  }
  const topLevel = contents.split(/^\s*\[/m, 1)[0] ?? "";
  const match = topLevel.match(/^\s*model\s*=\s*["']([^"']+)["']\s*(?:#.*)?$/m);
  return safeOptionalIdentifier(match?.[1], 160);
}

function codexHome() {
  return process.env.CODEX_HOME?.trim() || path.join(os.homedir(), ".codex");
}

function modelFromEvents(values) {
  for (const value of values) {
    const event = object(value);
    for (const candidate of [event.model, object(event.payload).model, object(event.item).model, object(event.usage).model]) {
      const found = safeOptionalIdentifier(candidate, 160);
      if (found) return found;
    }
  }
  return null;
}

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function readToken(filePath) {
  const stat = fs.statSync(filePath);
  if (!stat.isFile() || stat.size < 20 || stat.size > 4096) throw new Error("agent usage key file is invalid");
  const value = fs.readFileSync(filePath, "utf8").trim();
  if (value.length < 20 || /[\r\n]/.test(value)) throw new Error("agent usage key file is invalid");
  return value;
}

function safeIdentifier(value, maximum, label) {
  const normalized = safeOptionalIdentifier(value, maximum);
  if (!normalized) throw new Error(`${label} is invalid`);
  return normalized;
}

function safeOptionalIdentifier(value, maximum) {
  if (typeof value !== "string") return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= maximum && /^[A-Za-z0-9][A-Za-z0-9._:/@+#-]*$/.test(normalized)
    ? normalized
    : null;
}

function validateEndpoint(value) {
  let endpoint;
  try {
    endpoint = new URL(value);
  } catch {
    throw new Error("II_OS_AGENT_USAGE_URL is invalid");
  }
  const local = endpoint.protocol === "http:" && ["127.0.0.1", "localhost"].includes(endpoint.hostname);
  if (endpoint.protocol !== "https:" && !local) throw new Error("II_OS_AGENT_USAGE_URL must use HTTPS");
  if (endpoint.username || endpoint.password || endpoint.search || endpoint.hash) {
    throw new Error("II_OS_AGENT_USAGE_URL must not carry credentials, a query or a fragment");
  }
  return value;
}
