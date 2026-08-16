import assert from "node:assert/strict";
import test from "node:test";
import { Effect } from "effect";
import {
  crawlEffect,
  isFirecrawlQuotaError,
  searchBrave,
  type CrawlClient,
} from "./index.ts";

test("recognizes only Firecrawl quota and rate-limit failures", () => {
  assert.equal(isFirecrawlQuotaError({ status: 402 }), true);
  assert.equal(isFirecrawlQuotaError({ statusCode: 429 }), true);
  assert.equal(
    isFirecrawlQuotaError(
      new Error("Firecrawl search failed", {
        cause: { status: 402, message: "Insufficient credits" },
      }),
    ),
    true,
  );
  assert.equal(
    isFirecrawlQuotaError(new Error("Credit quota exhausted")),
    true,
  );

  assert.equal(isFirecrawlQuotaError({ status: 401 }), false);
  assert.equal(isFirecrawlQuotaError({ status: 500 }), false);
  assert.equal(isFirecrawlQuotaError(new Error("Network unavailable")), false);
});

test("uses Mario-style Brave headers and returns web results", async () => {
  let requestedUrl = "";
  let requestedHeaders: Headers | undefined;
  const fakeFetch = (async (input, init) => {
    requestedUrl = String(input);
    requestedHeaders = new Headers(init?.headers);
    return new Response(
      JSON.stringify({
        web: {
          results: [
            {
              title: "Pi coding agent",
              url: "https://pi.dev/",
              description: "A coding agent.",
            },
          ],
        },
      }),
      { status: 200 },
    );
  }) as typeof fetch;

  const result = await searchBrave(
    {
      query: "pi coding agent",
      limit: 7,
      scrapeResults: true,
    },
    "test-brave-key",
    undefined,
    fakeFetch,
  );

  const url = new URL(requestedUrl);
  assert.equal(
    url.origin + url.pathname,
    "https://api.search.brave.com/res/v1/web/search",
  );
  assert.equal(url.searchParams.get("q"), "pi coding agent");
  assert.equal(url.searchParams.get("count"), "7");
  assert.equal(url.searchParams.get("country"), "US");
  assert.equal(requestedHeaders?.get("X-Subscription-Token"), "test-brave-key");
  assert.equal(result.provider, "brave");
  assert.equal(result.fallbackFrom, "firecrawl");
  assert.equal(result.results.length, 1);
  assert.match(result.warning ?? "", /snippets only/i);
});

test("uses Brave's source-specific endpoint and top-level results", async () => {
  let requestedUrl = "";
  const fakeFetch = (async (input) => {
    requestedUrl = String(input);
    return new Response(
      JSON.stringify({
        results: [
          {
            title: "Current story",
            url: "https://example.com/story",
          },
        ],
      }),
      { status: 200 },
    );
  }) as typeof fetch;

  const result = await searchBrave(
    { query: "current story", source: "news" },
    "test-brave-key",
    undefined,
    fakeFetch,
  );

  assert.equal(new URL(requestedUrl).pathname, "/res/v1/news/search");
  assert.equal(result.source, "news");
  assert.equal(result.results.length, 1);
  assert.equal(result.warning, undefined);
});

test("cancels the remote crawl when polling is interrupted", async () => {
  let pollingStarted!: () => void;
  const startedPolling = new Promise<void>((resolve) => {
    pollingStarted = resolve;
  });
  const cancelledJobs: string[] = [];

  const client: CrawlClient = {
    startCrawl: async (url) => ({ id: "crawl-123", url }),
    getCrawlStatus: async () => {
      pollingStarted();
      return new Promise(() => undefined);
    },
    cancelCrawl: async (jobId) => {
      cancelledJobs.push(jobId);
      return true;
    },
  };

  const controller = new AbortController();
  const running = Effect.runPromise(
    crawlEffect(client, "https://example.com", { limit: 1 }),
    { signal: controller.signal },
  );
  const interrupted = assert.rejects(running);

  await startedPolling;
  controller.abort();
  await interrupted;

  assert.deepEqual(cancelledJobs, ["crawl-123"]);
});
