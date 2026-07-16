#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const BASE_URL = process.env.TAPINK_API_URL ?? "http://127.0.0.1:47663";
const TOKEN = process.env.TAPINK_API_TOKEN;

if (!TOKEN) {
  console.error(
    "tapink-mcp: TAPINK_API_TOKEN is not set. Copy the token from TapInk's Settings > External API " +
      "and set it as an env var for this MCP server."
  );
  process.exit(1);
}

/** Raw HTTP call against the TapInk local API. Throws on network failure; returns the Response otherwise. */
async function apiRequest(method, path, { query, body } = {}) {
  const url = new URL(path, BASE_URL);
  if (query) {
    for (const [key, value] of Object.entries(query)) {
      if (value !== undefined) url.searchParams.set(key, String(value));
    }
  }
  return fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${TOKEN}`,
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
}

/** For endpoints that return JSON. Throws with the API's error message on a non-2xx response. */
async function apiJson(method, path, opts) {
  const res = await apiRequest(method, path, opts);
  const text = await res.text();
  let data = {};
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { raw: text };
  }
  if (!res.ok) {
    throw new Error(data.error ?? `TapInk API returned HTTP ${res.status}`);
  }
  return data;
}

function textResult(value) {
  return { content: [{ type: "text", text: JSON.stringify(value) }] };
}

function errorResult(error) {
  return { content: [{ type: "text", text: `Error: ${error.message}` }], isError: true };
}

const server = new McpServer({ name: "tapink-mcp", version: "0.1.0" });

const point = z.object({ x: z.number(), y: z.number() });
const display = z.number().int().describe("Display ID from list_displays");
const color = z
  .string()
  .optional()
  .describe("Hex color, e.g. #FF0000 or #FF0000AA with alpha. Omit to use TapInk's currently selected color.");
const width = z
  .number()
  .positive()
  .optional()
  .describe("Stroke/outline width in points. Omit to use TapInk's currently selected line width.");

// --- Draw mode control ---

// server.registerTool(
//   "get_draw_mode",
//   { description: "Check whether TapInk's draw-mode overlay is currently active." },
//   async () => {
//     try {
//       return textResult(await apiJson("GET", "/draw-mode"));
//     } catch (error) {
//       return errorResult(error);
//     }
//   }
// );

for (const [name, path] of [
  ["enable_draw_mode", "/draw-mode/enable"],
  ["disable_draw_mode", "/draw-mode/disable"],
  // ["toggle_draw_mode", "/draw-mode/toggle"],
]) {
  server.registerTool(
    name,
    { description: `${name.replace(/_/g, " ")} — shows or hides TapInk's transparent drawing overlay.` },
    async () => {
      try {
        return textResult(await apiJson("POST", path));
      } catch (error) {
        return errorResult(error);
      }
    }
  );
}

// --- Displays & screenshots ---

server.registerTool(
  "list_displays",
  { description: "List every connected monitor with its display ID and pixel dimensions. Call this before drawing or taking a screenshot to learn valid display IDs." },
  async () => {
    try {
      return textResult(await apiJson("GET", "/displays"));
    } catch (error) {
      return errorResult(error);
    }
  }
);

server.registerTool(
  "take_screenshot",
  {
    description:
      "Capture a screenshot of one display (or a pixel region of it), including any TapInk annotations currently drawn. " +
      "Silent — no shutter sound, no clipboard/disk write. Returns a PNG image.",
    inputSchema: {
      display: display,
      rect: z
        .object({ x: z.number(), y: z.number(), width: z.number(), height: z.number() })
        .optional()
        .describe("Optional sub-region in top-left-origin pixel coordinates. Omit to capture the full display."),
    },
  },
  async ({ display: displayId, rect }) => {
    try {
      const query = { display: displayId };
      if (rect) query.rect = `${rect.x},${rect.y},${rect.width},${rect.height}`;
      const res = await apiRequest("GET", "/screenshot", { query });
      if (!res.ok) {
        const text = await res.text();
        let message = `TapInk API returned HTTP ${res.status}`;
        try {
          message = JSON.parse(text).error ?? message;
        } catch {
          // non-JSON error body, keep the generic message
        }
        throw new Error(message);
      }
      const buffer = Buffer.from(await res.arrayBuffer());
      return { content: [{ type: "image", data: buffer.toString("base64"), mimeType: "image/png" }] };
    } catch (error) {
      return errorResult(error);
    }
  }
);

// --- Drawing primitives ---
// Every draw tool takes pixel coordinates in the target display's own top-left-origin pixel
// space — exactly matching the pixel grid of the image take_screenshot returns for that display.
// Drawing auto-enables draw mode if it's currently off.

function registerStrokeTool(name, isHighlighter) {
  server.registerTool(
    name,
    {
      description: `Draw a freehand ${isHighlighter ? "highlighter" : "pen"} stroke through a sequence of points.`,
      inputSchema: {
        display,
        points: z.array(point).min(2).describe("Points the stroke passes through, in order."),
        color,
        width,
      },
    },
    async (args) => {
      try {
        return textResult(await apiJson("POST", `/tools/${name === "draw_pen" ? "pen" : "highlighter"}`, { body: args }));
      } catch (error) {
        return errorResult(error);
      }
    }
  );
}
registerStrokeTool("draw_pen", false);
registerStrokeTool("draw_highlighter", true);

function registerShapeTool(name, route) {
  server.registerTool(
    name,
    {
      description: `Draw a ${route} from one point to another.`,
      inputSchema: {
        display,
        start: point,
        end: point,
        color,
        width,
        fill: z
          .string()
          .optional()
          .describe("Fill color (rectangle/ellipse only; ignored for line/arrow). Omit for no fill."),
      },
    },
    async (args) => {
      try {
        return textResult(await apiJson("POST", `/tools/${route}`, { body: args }));
      } catch (error) {
        return errorResult(error);
      }
    }
  );
}
registerShapeTool("draw_rectangle", "rectangle");
registerShapeTool("draw_ellipse", "ellipse");
registerShapeTool("draw_line", "line");
registerShapeTool("draw_arrow", "arrow");

server.registerTool(
  "draw_text",
  {
    description: "Draw a text label at a point.",
    inputSchema: {
      display,
      origin: point,
      string: z.string().min(1),
      color,
      fontSize: z
        .number()
        .positive()
        .optional()
        .describe("Font size in points. Omit to derive it from TapInk's currently selected line width."),
    },
  },
  async (args) => {
    try {
      return textResult(await apiJson("POST", "/tools/text", { body: args }));
    } catch (error) {
      return errorResult(error);
    }
  }
);

// --- Undo / redo / clear ---

for (const name of ["undo", "redo"]) {
  server.registerTool(
    name,
    { description: `${name === "undo" ? "Undo" : "Redo"} the last drawn object.` },
    async () => {
      try {
        return textResult(await apiJson("POST", `/${name}`));
      } catch (error) {
        return errorResult(error);
      }
    }
  );
}

server.registerTool(
  "clear_canvas",
  { description: "Erase every object currently drawn on every display." },
  async () => {
    try {
      return textResult(await apiJson("POST", "/clear"));
    } catch (error) {
      return errorResult(error);
    }
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
