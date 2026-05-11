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
        "L01E01-greeting-html": resolve(__dirname, "L01E01-greeting-html.html"),
        "L01E02-greeting": resolve(__dirname, "L01E02-greeting.html"),
        "L01E03-counter": resolve(__dirname, "L01E03-counter.html"),
        "L01E04-swap": resolve(__dirname, "L01E04-swap.html"),
        "L01E05-full-name": resolve(__dirname, "L01E05-full-name.html"),
        "L01E06-temperature": resolve(__dirname, "L01E06-temperature.html"),
        "L02E01-fetch-joke": resolve(__dirname, "L02E01-fetch-joke.html"),
        "L02E02-github-user": resolve(__dirname, "L02E02-github-user.html"),
        "L02E03-post-note": resolve(__dirname, "L02E03-post-note.html"),
        "L02E04-derived-search": resolve(__dirname, "L02E04-derived-search.html"),
        "L03E01-debounce-echo": resolve(__dirname, "L03E01-debounce-echo.html"),
        "L03E02-search-debounced": resolve(__dirname, "L03E02-search-debounced.html"),
        "L03E03-custom-triggers": resolve(__dirname, "L03E03-custom-triggers.html"),
        "L04E01-required-name": resolve(__dirname, "L04E01-required-name.html"),
        "L04E02-email-format": resolve(__dirname, "L04E02-email-format.html"),
        "L04E03-username-available": resolve(__dirname, "L04E03-username-available.html"),
        "L05E01-profile-form": resolve(__dirname, "L05E01-profile-form.html"),
        "L05E02-wizard-step": resolve(__dirname, "L05E02-wizard-step.html"),
        "L05E03-signup": resolve(__dirname, "L05E03-signup.html"),
        "L05E04-checkout": resolve(__dirname, "L05E04-checkout.html"),
        "L06E01-counter-component": resolve(__dirname, "L06E01-counter-component.html"),
        "L06E02-tagpicker-component": resolve(__dirname, "L06E02-tagpicker-component.html"),
        "L07E01-persist-counter": resolve(__dirname, "L07E01-persist-counter.html"),
      },
    },
  },
});
