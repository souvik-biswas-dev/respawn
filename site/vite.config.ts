import { defineConfig } from "vite";
// Relative base: the built site works from any path or from a plain file server.
export default defineConfig({ base: "./", build: { target: "es2022" } });
