#!/usr/bin/env node
/**
 * Minimal static server for the Kittenbaticorn web build.
 *
 * Sets COOP/COEP headers so the Godot threaded web template can
 * initialize SharedArrayBuffer (required for std::thread in the C++
 * GDExtension). Also sets correct MIME types for .wasm and .pck.
 *
 * Run: node web/server.js [port=8080]
 */

const express = require("express");
const path = require("path");

const PORT = parseInt(process.argv[2] ?? process.env.PORT ?? "8080", 10);
const DIST = path.resolve(__dirname, "..", "build", "web");

const app = express();

app.use((_req, res, next) => {
	res.set("Cross-Origin-Opener-Policy", "same-origin");
	res.set("Cross-Origin-Embedder-Policy", "require-corp");
	next();
});

app.use(
	"/",
	express.static(DIST, {
		setHeaders: (res, filePath) => {
			if (filePath.endsWith(".wasm")) {
				res.type("application/wasm");
			} else if (filePath.endsWith(".pck")) {
				res.type("application/octet-stream");
			} else if (filePath.endsWith(".js")) {
				res.type("text/javascript");
			}
		},
	}),
);

app.listen(PORT, () => {
	console.log(`Kittenbaticorn web build: http://localhost:${PORT}`);
	console.log(`Serving from: ${DIST}`);
});
