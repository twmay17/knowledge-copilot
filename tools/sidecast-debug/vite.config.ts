import { defineConfig } from "vite";

export default defineConfig({
  root: ".",
  server: {
    host: "127.0.0.1",
    port: 3000,
    proxy: {
      "/api": "http://127.0.0.1:3001",
    },
  },
});
