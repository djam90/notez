import { defineConfig, devices } from '@playwright/test'

// Runs against the Vite dev server (source, not the built bundle). WebKit is
// the closest engine to the app's WKWebView; Chromium catches engine-specific
// assumptions cheaply.
const PORT = 5199

export default defineConfig({
  testDir: 'test/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: `http://localhost:${PORT}`,
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
  ],
  webServer: {
    command: `npx vite --port ${PORT} --strictPort`,
    url: `http://localhost:${PORT}/editor.html`,
    reuseExistingServer: !process.env.CI,
    timeout: 30_000,
  },
})
