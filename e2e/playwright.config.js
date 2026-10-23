// Browser tests for the whole shop. They expect the stack to be running (docker compose up --wait in ApiGateway/) with
// DEV_LOG_CODES=true in .env, so sign-up codes can be read from the bank's log instead of an inbox.
const { defineConfig, devices } = require("@playwright/test");

module.exports = defineConfig({
  testDir: "./tests",
  timeout: 90_000,
  expect: { timeout: 15_000 },
  retries: process.env.CI ? 1 : 0,
  workers: 1,                       // the tests share one database
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
