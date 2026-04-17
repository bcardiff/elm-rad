import { defineConfig } from "vite";
import { resolve } from "path";
import elm from "vite-plugin-elm";

export default defineConfig({
  plugins: [elm()],
  appType: "mpa",
  build: {
    rollupOptions: {
      input: {
        index: resolve(__dirname, "index.html"),
        "greeting-html": resolve(__dirname, "greeting-html.html"),
        greeting: resolve(__dirname, "greeting.html"),
      },
    },
  },
});
