import { defineConfig } from "vite";
import { resolve } from "path";
import elm from "vite-plugin-elm";
import { mockApi } from "./mock-api-plugin.js";

export default defineConfig({
  plugins: [elm(), mockApi()],
  appType: "mpa",
  build: {
    rollupOptions: {
      input: {
        index: resolve(__dirname, "index.html"),
        "greeting-html": resolve(__dirname, "greeting-html.html"),
        greeting: resolve(__dirname, "greeting.html"),
        counter: resolve(__dirname, "counter.html"),
        swap: resolve(__dirname, "swap.html"),
        "full-name": resolve(__dirname, "full-name.html"),
        temperature: resolve(__dirname, "temperature.html"),
        "fetch-joke": resolve(__dirname, "fetch-joke.html"),
        "github-user": resolve(__dirname, "github-user.html"),
        "post-note": resolve(__dirname, "post-note.html"),
        "derived-search": resolve(__dirname, "derived-search.html"),
        "debounce-echo": resolve(__dirname, "debounce-echo.html"),
        "search-debounced": resolve(__dirname, "search-debounced.html"),
        "custom-triggers": resolve(__dirname, "custom-triggers.html"),
        "required-name": resolve(__dirname, "required-name.html"),
        "email-format": resolve(__dirname, "email-format.html"),
        "username-available": resolve(__dirname, "username-available.html"),
        "counter-component": resolve(__dirname, "counter-component.html"),
        "tagpicker-component": resolve(__dirname, "tagpicker-component.html"),
      },
    },
  },
});
