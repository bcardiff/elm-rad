// A scrappy dev-only mock API for Layer 2 examples.
// Every endpoint delays ~2s so latest-wins is visible by eye.

const JOKES = [
  "Why did the developer go broke? Because they used up all their cache.",
  "There are 10 kinds of people: those who get binary and those who don't.",
  "A SQL query walks into a bar, sees two tables, and asks: can I join you?",
];

function pickJoke() {
  return JOKES[Math.floor(Math.random() * JOKES.length)];
}

function sendJson(res, body, ms = 2000) {
  setTimeout(() => {
    res.setHeader("Content-Type", "application/json");
    res.statusCode = 200;
    res.end(JSON.stringify(body));
  }, ms);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let data = "";
    req.on("data", (chunk) => (data += chunk));
    req.on("end", () => resolve(data));
    req.on("error", reject);
  });
}

export function mockApi() {
  return {
    name: "mock-api",
    configureServer(server) {
      // GET /api/joke
      server.middlewares.use("/api/joke", (req, res, next) => {
        if (!req.url || !req.url.startsWith("/") || req.method !== "GET") {
          return next();
        }
        sendJson(res, { text: pickJoke() });
      });

      // GET /api/github/users/:login
      server.middlewares.use("/api/github/users/", (req, res, next) => {
        if (req.method !== "GET") return next();
        const login = (req.url || "/").split("/").filter(Boolean).pop() || "";
        sendJson(res, { login, bio: `mock bio for ${login}` });
      });

      // POST /api/note
      server.middlewares.use("/api/note", async (req, res, _next) => {
        if (req.method !== "POST") {
          res.statusCode = 405;
          res.end();
          return;
        }
        const raw = await readBody(req);
        let parsed;
        try {
          parsed = JSON.parse(raw);
        } catch (_e) {
          res.statusCode = 400;
          res.end(JSON.stringify({ error: "invalid json" }));
          return;
        }
        sendJson(res, { id: Math.floor(Math.random() * 10000), echoed: parsed });
      });

      // GET /api/search?q=...
      server.middlewares.use("/api/search", (req, res, next) => {
        if (req.method !== "GET") return next();
        const url = new URL(req.url || "/", "http://localhost");
        const q = url.searchParams.get("q") || "";
        sendJson(res, { query: q, matches: [q + "-alpha", q + "-beta", q + "-gamma"] });
      });

      // GET /api/username-check?q=<name>
      // "taken" → unavailable; anything else → available
      server.middlewares.use("/api/username-check", (req, res, next) => {
        if (req.method !== "GET") return next();
        const url = new URL(req.url || "/", "http://localhost");
        const q = url.searchParams.get("q") || "";
        sendJson(res, { available: q !== "taken" }, 1500);
      });

      // POST /api/signup
      // 200 on success; 400 if the username is "fail" (deterministic failure path).
      server.middlewares.use("/api/signup", async (req, res, _next) => {
        if (req.method !== "POST") {
          res.statusCode = 405;
          res.end();
          return;
        }
        const raw = await readBody(req);
        let parsed;
        try {
          parsed = JSON.parse(raw);
        } catch (_e) {
          res.statusCode = 400;
          res.end(JSON.stringify({ error: "invalid json" }));
          return;
        }
        if (parsed.username === "fail") {
          setTimeout(() => {
            res.statusCode = 400;
            res.setHeader("Content-Type", "application/json");
            res.end(JSON.stringify({ error: "username 'fail' is reserved" }));
          }, 1500);
          return;
        }
        sendJson(res, { ok: true }, 1500);
      });
    },
  };
}
