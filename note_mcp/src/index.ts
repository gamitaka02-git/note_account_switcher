#!/usr/bin/env node

import axios from "axios";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod/v4";

const NOTE_API_BASE_URL = "https://note.com/api/v2";

interface NoteApiEnvelope<T> {
  data: T;
}

interface NoteArticlesData {
  contents?: unknown;
  isLastPage?: unknown;
  totalCount?: unknown;
}

type JsonRecord = Record<string, unknown>;

const noteApi = axios.create({
  baseURL: NOTE_API_BASE_URL,
  timeout: 15_000,
  headers: {
    Accept: "application/json",
    "User-Agent": "note-mcp/1.0.0",
  },
});

const server = new McpServer({
  name: "note-mcp",
  version: "1.0.0",
});

const creatorIdSchema = z
  .string()
  .trim()
  .min(1, "creator_id is required")
  .max(100, "creator_id must be 100 characters or fewer")
  .regex(
    /^[A-Za-z0-9_-]+$/,
    "creator_id may contain only letters, numbers, underscores, and hyphens",
  )
  .describe('note creator ID (for example, "chitsuka")');

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function numberOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function booleanOrNull(value: unknown): boolean | null {
  return typeof value === "boolean" ? value : null;
}

function extractHashtags(value: unknown): string[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.flatMap((entry) => {
    if (!isRecord(entry) || !isRecord(entry.hashtag)) {
      return [];
    }

    const name = stringOrNull(entry.hashtag.name);
    return name === null ? [] : [name];
  });
}

function normalizeArticle(article: unknown, creatorId: string): JsonRecord {
  if (!isRecord(article)) {
    return { data: article };
  }

  const key = stringOrNull(article.key);
  const apiUrl = stringOrNull(article.noteUrl);
  const fallbackUrl = key === null
    ? null
    : `https://note.com/${encodeURIComponent(creatorId)}/n/${encodeURIComponent(key)}`;

  return {
    id: numberOrNull(article.id),
    key,
    title: stringOrNull(article.name),
    url: apiUrl ?? fallbackUrl,
    like_count: numberOrNull(article.likeCount),
    published_at: stringOrNull(article.publishAt),
    description: stringOrNull(article.description),
    body_excerpt: stringOrNull(article.body),
    table_of_contents:
      article.tableOfContents ?? article.table_of_contents ?? article.toc ?? null,
    hashtags: extractHashtags(article.hashtags),
    thumbnail_url:
      stringOrNull(article.eyecatch) ?? stringOrNull(article.thumbnailExternalUrl),
    price: numberOrNull(article.price),
    comment_count: numberOrNull(article.commentCount),
    can_read: booleanOrNull(article.canRead),
    is_pinned: booleanOrNull(article.isPinned),
  };
}

function successResult(payload: unknown) {
  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(payload, null, 2),
      },
    ],
  };
}

function errorResult(error: unknown, operation: string) {
  let message = `${operation} failed`;
  let status: number | null = null;

  if (axios.isAxiosError(error)) {
    status = error.response?.status ?? null;

    if (status === 404) {
      message = "The specified note creator was not found";
    } else if (status === 429) {
      message = "note.com rate-limited the request; please try again later";
    } else if (status !== null) {
      message = `note.com returned HTTP ${status}`;
    } else if (error.code === "ECONNABORTED") {
      message = "The request to note.com timed out";
    } else {
      message = error.message;
    }
  } else if (error instanceof Error) {
    message = error.message;
  }

  return {
    isError: true,
    content: [
      {
        type: "text" as const,
        text: JSON.stringify({ error: message, status }, null, 2),
      },
    ],
  };
}

server.registerTool(
  "get_note_profile",
  {
    title: "Get note creator profile",
    description: "Retrieve the public profile information for a note creator.",
    inputSchema: z.object({
      creator_id: creatorIdSchema,
    }),
  },
  async ({ creator_id }) => {
    try {
      const response = await noteApi.get<NoteApiEnvelope<unknown>>(
        `/creators/${encodeURIComponent(creator_id)}`,
      );

      return successResult({
        creator_id,
        profile: response.data.data,
      });
    } catch (error: unknown) {
      return errorResult(error, "Profile retrieval");
    }
  },
);

server.registerTool(
  "get_note_articles",
  {
    title: "Get note creator articles",
    description:
      "Retrieve a page of a note creator's public articles, including titles, URLs, like counts, publication dates, excerpts, and related metadata.",
    inputSchema: z.object({
      creator_id: creatorIdSchema,
      page: z
        .number()
        .int()
        .min(1)
        .default(1)
        .describe("Page number (default: 1)"),
    }),
  },
  async ({ creator_id, page }) => {
    try {
      const response = await noteApi.get<NoteApiEnvelope<NoteArticlesData>>(
        `/creators/${encodeURIComponent(creator_id)}/contents`,
        {
          params: {
            kind: "note",
            page,
          },
        },
      );

      const data = response.data.data;
      const contents = Array.isArray(data.contents) ? data.contents : [];

      return successResult({
        creator_id,
        page,
        total_count: numberOrNull(data.totalCount),
        is_last_page: booleanOrNull(data.isLastPage),
        articles: contents.map((article) => normalizeArticle(article, creator_id)),
      });
    } catch (error: unknown) {
      return errorResult(error, "Article retrieval");
    }
  },
);

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Failed to start note MCP server: ${message}`);
  process.exitCode = 1;
});
