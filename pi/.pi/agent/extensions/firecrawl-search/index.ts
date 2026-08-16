import { readFileSync } from "node:fs";
import { mkdtemp, writeFile } from "node:fs/promises";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { StringEnum } from "@earendil-works/pi-ai";
import {
  DEFAULT_MAX_BYTES,
  DEFAULT_MAX_LINES,
  formatSize,
  truncateHead,
  type AgentToolResult,
  type AgentToolUpdateCallback,
  type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { Cause, Data, Effect, Exit } from "effect";
import { Firecrawl, type CrawlJob, type CrawlOptions } from "firecrawl";
import { Type } from "typebox";
import {
  CRAWL_PARAMETER_DESCRIPTIONS,
  CRAWL_PROMPT_GUIDELINES,
  CRAWL_PROMPT_SNIPPET,
  CRAWL_TOOL_DESCRIPTION,
  SCRAPE_PARAMETER_DESCRIPTIONS,
  SCRAPE_PROMPT_GUIDELINES,
  SCRAPE_PROMPT_SNIPPET,
  SCRAPE_TOOL_DESCRIPTION,
  SEARCH_PARAMETER_DESCRIPTIONS,
  SEARCH_PROMPT_GUIDELINES,
  SEARCH_PROMPT_SNIPPET,
  SEARCH_TOOL_DESCRIPTION,
} from "./prompt.ts";

function readEnvValue(name: string) {
  if (process.env[name]) return process.env[name];

  const envPath = join(homedir(), ".pi", "agent", ".env");
  let envText = "";

  try {
    envText = readFileSync(envPath, "utf8");
  } catch {
    return undefined;
  }

  for (const line of envText.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const match = trimmed.match(
      /^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/,
    );
    if (!match || match[1] !== name) continue;

    const value = match[2].trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      return value.slice(1, -1);
    }

    return value.replace(/\s+#.*$/, "");
  }

  return undefined;
}

class MissingApiKeyError extends Data.TaggedError("MissingApiKeyError")<{
  readonly message: string;
}> {}

function createClient() {
  const apiKey = readEnvValue("FIRECRAWL_API_KEY");
  if (!apiKey) {
    return Effect.fail(
      new MissingApiKeyError({
        message:
          "Missing FIRECRAWL_API_KEY in the environment or ~/.pi/agent/.env",
      }),
    );
  }

  return Effect.try({
    try: () => new Firecrawl({ apiKey }),
    catch: (cause) =>
      new FirecrawlError({ message: errorMessage(cause), cause }),
  });
}

function stringify(value: unknown) {
  return JSON.stringify(value, null, 2);
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

function errorRecord(error: unknown): Record<string, unknown> | undefined {
  return typeof error === "object" && error !== null
    ? (error as Record<string, unknown>)
    : undefined;
}

/** Firecrawl uses 402 for exhausted credits and 429 for rate limits. */
export function isFirecrawlQuotaError(error: unknown): boolean {
  const visited = new Set<unknown>();
  let current: unknown = error;

  while (current && !visited.has(current)) {
    visited.add(current);
    const record = errorRecord(current);
    const status = record?.status ?? record?.statusCode;
    if (status === 402 || status === 429) return true;

    const message = errorMessage(current);
    if (
      /\b(?:quota|credits?|payment required|rate[ -]?limit(?:ed|ing)?)\b/i.test(
        message,
      )
    ) {
      return true;
    }

    current = record?.cause;
  }

  return false;
}

class FirecrawlError extends Data.TaggedError("FirecrawlError")<{
  readonly message: string;
  readonly cause: unknown;
}> {}

function firecrawlRequest<T>(request: () => Promise<T>) {
  return Effect.tryPromise({
    try: request,
    catch: (cause) =>
      new FirecrawlError({ message: errorMessage(cause), cause }),
  });
}

class OutputError extends Data.TaggedError("OutputError")<{
  readonly message: string;
  readonly cause: unknown;
}> {}

function formatOutput(value: unknown, operation: string) {
  return Effect.tryPromise({
    try: async () => {
      const output = typeof value === "string" ? value : stringify(value);
      const truncation = truncateHead(output, {
        maxBytes: DEFAULT_MAX_BYTES,
        maxLines: DEFAULT_MAX_LINES,
      });
      if (!truncation.truncated) return output;

      const outputDirectory = await mkdtemp(join(tmpdir(), "pi-firecrawl-"));
      const outputPath = join(outputDirectory, `${operation}.json`);
      await writeFile(outputPath, output, "utf8");

      return `${truncation.content}\n\n[Output truncated: ${truncation.outputLines} of ${truncation.totalLines} lines (${formatSize(truncation.outputBytes)} of ${formatSize(truncation.totalBytes)}). Full output saved to: ${outputPath}]`;
    },
    catch: (cause) => new OutputError({ message: errorMessage(cause), cause }),
  });
}

export type CrawlClient = Pick<
  Firecrawl,
  "startCrawl" | "getCrawlStatus" | "cancelCrawl"
>;

function pollCrawl(
  client: CrawlClient,
  jobId: string,
): Effect.Effect<CrawlJob, FirecrawlError> {
  return firecrawlRequest(() => client.getCrawlStatus(jobId)).pipe(
    Effect.flatMap((job) =>
      job.status === "scraping"
        ? Effect.sleep("2 seconds").pipe(
            Effect.flatMap(() =>
              Effect.suspend(() => pollCrawl(client, jobId)),
            ),
          )
        : Effect.succeed(job),
    ),
  );
}

/** Brackets the remote job so every non-successful exit attempts cancellation. */
export function crawlEffect(
  client: CrawlClient,
  url: string,
  options: CrawlOptions,
) {
  return Effect.acquireUseRelease(
    firecrawlRequest(() => client.startCrawl(url, options)),
    (job) => pollCrawl(client, job.id),
    (job, exit) =>
      Exit.isSuccess(exit)
        ? Effect.void
        : firecrawlRequest(() => client.cancelCrawl(job.id)).pipe(
            Effect.timeout("10 seconds"),
            Effect.ignore,
          ),
  );
}

function operationError(operation: string, error: unknown) {
  if (error instanceof MissingApiKeyError) return new Error(error.message);

  const cause =
    error instanceof FirecrawlError || error instanceof OutputError
      ? error.cause
      : error;
  return new Error(`Firecrawl ${operation} failed: ${errorMessage(error)}`, {
    cause,
  });
}

/** Shared Effect pipeline with a single Promise boundary for the tool API. */
async function runFirecrawl<T>(
  operation: string,
  status: string,
  timeout: number,
  signal: AbortSignal | undefined,
  onUpdate: AgentToolUpdateCallback<T | undefined> | undefined,
  request: (
    client: Firecrawl,
  ) => Effect.Effect<
    { details: T; output: unknown },
    FirecrawlError | OutputError
  >,
) {
  const program = Effect.gen(function* () {
    const client = yield* createClient();
    yield* Effect.sync(() =>
      onUpdate?.({
        content: [{ type: "text", text: status }],
        details: undefined,
      }),
    );

    const { details, output } = yield* request(client).pipe(
      Effect.timeout(timeout),
    );
    const formatted = yield* formatOutput(output, operation);

    return {
      content: [{ type: "text" as const, text: formatted }],
      details,
    } satisfies AgentToolResult<T | undefined>;
  });

  const exit = await Effect.runPromiseExit(
    program,
    signal ? { signal } : undefined,
  );
  if (Exit.isSuccess(exit)) return exit.value;
  if (Cause.hasInterruptsOnly(exit.cause)) {
    throw new Error("Firecrawl request cancelled");
  }
  throw operationError(operation, Cause.squash(exit.cause));
}

type SearchSource = "web" | "news" | "images";

export interface SearchParams {
  readonly query: string;
  readonly limit?: number;
  readonly source?: SearchSource;
  readonly scrapeResults?: boolean;
}

export interface BraveSearchDetails {
  readonly provider: "brave";
  readonly fallbackFrom: "firecrawl";
  readonly query: string;
  readonly source: SearchSource;
  readonly results: readonly unknown[];
  readonly warning?: string;
}

type Fetch = typeof fetch;

function braveEndpoint(source: SearchSource) {
  return `https://api.search.brave.com/res/v1/${source}/search`;
}

function braveResults(
  response: Record<string, unknown>,
  source: SearchSource,
): readonly unknown[] {
  const section = errorRecord(response[source]);
  const nestedResults = section?.results;
  if (Array.isArray(nestedResults)) return nestedResults;
  return Array.isArray(response.results) ? response.results : [];
}

/** Mario Zechner-style Brave Search request, kept dependency-free with fetch. */
export async function searchBrave(
  params: SearchParams,
  apiKey: string,
  signal?: AbortSignal,
  fetchImpl: Fetch = fetch,
): Promise<BraveSearchDetails> {
  const source = params.source ?? "web";
  const url = new URL(braveEndpoint(source));
  url.searchParams.set("q", params.query);
  url.searchParams.set("count", String(params.limit ?? 5));
  url.searchParams.set("country", "US");

  const timeoutSignal = AbortSignal.timeout(30_000);
  const requestSignal = signal
    ? AbortSignal.any([signal, timeoutSignal])
    : timeoutSignal;
  const response = await fetchImpl(url, {
    headers: {
      Accept: "application/json",
      "Accept-Encoding": "gzip",
      "X-Subscription-Token": apiKey,
    },
    signal: requestSignal,
  });
  const bodyText = await response.text();

  if (!response.ok) {
    const detail = bodyText.trim().slice(0, 500);
    throw new Error(
      `Brave Search request failed (${response.status} ${response.statusText})${detail ? `: ${detail}` : ""}`,
    );
  }

  let body: unknown;
  try {
    body = JSON.parse(bodyText);
  } catch (cause) {
    throw new Error("Brave Search returned invalid JSON", { cause });
  }

  const responseRecord = errorRecord(body);
  if (!responseRecord)
    throw new Error("Brave Search returned an empty response");

  return {
    provider: "brave",
    fallbackFrom: "firecrawl",
    query: params.query,
    source,
    results: braveResults(responseRecord, source),
    warning: params.scrapeResults
      ? "Firecrawl result scraping was unavailable; Brave returned search metadata and snippets only."
      : undefined,
  };
}

async function runBraveFallback(
  params: SearchParams,
  signal: AbortSignal | undefined,
  onUpdate: AgentToolUpdateCallback<BraveSearchDetails | undefined> | undefined,
) {
  const apiKey = readEnvValue("BRAVE_API_KEY");
  if (!apiKey) {
    throw new Error(
      "Missing BRAVE_API_KEY in the environment or ~/.pi/agent/.env",
    );
  }

  onUpdate?.({
    content: [
      {
        type: "text",
        text: `Firecrawl quota exhausted; searching Brave for: ${params.query}`,
      },
    ],
    details: undefined,
  });

  const details = await searchBrave(params, apiKey, signal);
  const formatted = await Effect.runPromise(formatOutput(details, "search"));
  return {
    content: [{ type: "text" as const, text: formatted }],
    details,
  } satisfies AgentToolResult<BraveSearchDetails | undefined>;
}

async function runSearch(
  params: SearchParams,
  signal: AbortSignal | undefined,
  onUpdate: AgentToolUpdateCallback<unknown> | undefined,
) {
  try {
    return await runFirecrawl(
      "search",
      `Searching Firecrawl for: ${params.query}`,
      35_000,
      signal,
      onUpdate,
      (client) =>
        firecrawlRequest(() =>
          client.search(params.query, {
            limit: params.limit ?? 5,
            sources: [params.source ?? "web"],
            scrapeOptions: params.scrapeResults
              ? { formats: ["markdown"], timeout: 30_000 }
              : undefined,
            timeout: 30_000,
          }),
        ).pipe(Effect.map((result) => ({ details: result, output: result }))),
    );
  } catch (firecrawlError) {
    if (signal?.aborted || !isFirecrawlQuotaError(firecrawlError)) {
      throw firecrawlError;
    }

    try {
      return await runBraveFallback(params, signal, onUpdate);
    } catch (braveError) {
      throw new AggregateError(
        [firecrawlError, braveError],
        `Firecrawl quota was exhausted and the Brave fallback failed: ${errorMessage(braveError)}`,
      );
    }
  }
}

export default function firecrawlTools(pi: ExtensionAPI) {
  pi.registerTool({
    name: "search",
    label: "Search Web",
    description: SEARCH_TOOL_DESCRIPTION,
    promptSnippet: SEARCH_PROMPT_SNIPPET,
    promptGuidelines: SEARCH_PROMPT_GUIDELINES,
    parameters: Type.Object({
      query: Type.String({
        description: SEARCH_PARAMETER_DESCRIPTIONS.query,
      }),
      limit: Type.Optional(
        Type.Number({
          description: SEARCH_PARAMETER_DESCRIPTIONS.limit,
          minimum: 1,
          maximum: 20,
        }),
      ),
      source: Type.Optional(StringEnum(["web", "news", "images"] as const)),
      scrapeResults: Type.Optional(
        Type.Boolean({
          description: SEARCH_PARAMETER_DESCRIPTIONS.scrapeResults,
        }),
      ),
    }),
    execute: (_toolCallId, params, signal, onUpdate) =>
      runSearch(params, signal, onUpdate),
  });

  pi.registerTool({
    name: "crawl",
    label: "Crawl Website",
    description: CRAWL_TOOL_DESCRIPTION,
    promptSnippet: CRAWL_PROMPT_SNIPPET,
    promptGuidelines: CRAWL_PROMPT_GUIDELINES,
    parameters: Type.Object({
      url: Type.String({ description: CRAWL_PARAMETER_DESCRIPTIONS.url }),
      limit: Type.Optional(
        Type.Number({
          description: CRAWL_PARAMETER_DESCRIPTIONS.limit,
          minimum: 1,
          maximum: 100,
        }),
      ),
      maxDiscoveryDepth: Type.Optional(
        Type.Number({
          description: CRAWL_PARAMETER_DESCRIPTIONS.maxDiscoveryDepth,
          minimum: 0,
        }),
      ),
      includePaths: Type.Optional(
        Type.Array(Type.String(), {
          description: CRAWL_PARAMETER_DESCRIPTIONS.includePaths,
        }),
      ),
      excludePaths: Type.Optional(
        Type.Array(Type.String(), {
          description: CRAWL_PARAMETER_DESCRIPTIONS.excludePaths,
        }),
      ),
      crawlEntireDomain: Type.Optional(
        Type.Boolean({
          description: CRAWL_PARAMETER_DESCRIPTIONS.crawlEntireDomain,
        }),
      ),
      allowSubdomains: Type.Optional(
        Type.Boolean({
          description: CRAWL_PARAMETER_DESCRIPTIONS.allowSubdomains,
        }),
      ),
      sitemap: Type.Optional(StringEnum(["include", "skip", "only"] as const)),
      onlyMainContent: Type.Optional(
        Type.Boolean({
          description: CRAWL_PARAMETER_DESCRIPTIONS.onlyMainContent,
        }),
      ),
      timeout: Type.Optional(
        Type.Number({
          description: CRAWL_PARAMETER_DESCRIPTIONS.timeout,
          minimum: 1,
          maximum: 600,
        }),
      ),
    }),
    execute: (_toolCallId, params, signal, onUpdate) =>
      runFirecrawl(
        "crawl",
        `Crawling up to ${params.limit ?? 20} pages from: ${params.url}`,
        ((params.timeout ?? 120) + 5) * 1_000,
        signal,
        onUpdate,
        (client) =>
          crawlEffect(client, params.url, {
            limit: params.limit ?? 20,
            maxDiscoveryDepth: params.maxDiscoveryDepth,
            includePaths: params.includePaths,
            excludePaths: params.excludePaths,
            crawlEntireDomain: params.crawlEntireDomain,
            allowSubdomains: params.allowSubdomains,
            sitemap: params.sitemap,
            scrapeOptions: {
              formats: ["markdown"],
              onlyMainContent: params.onlyMainContent ?? true,
            },
          }).pipe(
            Effect.map((result) => ({ details: result, output: result })),
          ),
      ),
  });

  pi.registerTool({
    name: "scrape",
    label: "Scrape Page",
    description: SCRAPE_TOOL_DESCRIPTION,
    promptSnippet: SCRAPE_PROMPT_SNIPPET,
    promptGuidelines: SCRAPE_PROMPT_GUIDELINES,
    parameters: Type.Object({
      url: Type.String({ description: SCRAPE_PARAMETER_DESCRIPTIONS.url }),
      onlyMainContent: Type.Optional(
        Type.Boolean({
          description: SCRAPE_PARAMETER_DESCRIPTIONS.onlyMainContent,
        }),
      ),
      waitFor: Type.Optional(
        Type.Number({
          description: SCRAPE_PARAMETER_DESCRIPTIONS.waitFor,
          minimum: 0,
          maximum: 60_000,
        }),
      ),
      timeout: Type.Optional(
        Type.Number({
          description: SCRAPE_PARAMETER_DESCRIPTIONS.timeout,
          minimum: 1,
          maximum: 120_000,
        }),
      ),
      includeMetadata: Type.Optional(
        Type.Boolean({
          description: SCRAPE_PARAMETER_DESCRIPTIONS.includeMetadata,
        }),
      ),
    }),
    execute: (_toolCallId, params, signal, onUpdate) =>
      runFirecrawl(
        "scrape",
        `Scraping page with Firecrawl: ${params.url}`,
        (params.timeout ?? 30_000) + 5_000,
        signal,
        onUpdate,
        (client) =>
          firecrawlRequest(() =>
            client.scrape(params.url, {
              formats: ["markdown"],
              onlyMainContent: params.onlyMainContent ?? true,
              waitFor: params.waitFor,
              timeout: params.timeout ?? 30_000,
            }),
          ).pipe(
            Effect.flatMap((document) =>
              Effect.try({
                try: () => {
                  const metadata =
                    params.includeMetadata && document.metadata
                      ? `\n\nMetadata:\n${stringify(document.metadata)}`
                      : "";
                  const markdown =
                    document.markdown?.trim() ||
                    "No markdown content returned.";

                  return {
                    details: document,
                    output: `${markdown}${metadata}`,
                  };
                },
                catch: (cause) =>
                  new OutputError({ message: errorMessage(cause), cause }),
              }),
            ),
          ),
      ),
  });
}
