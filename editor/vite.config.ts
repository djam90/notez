import { defineConfig } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'

// Builds the whole editor into one self-contained HTML file that the native
// app bundles and serves from the `notez://` scheme. No network, no disk
// lookups beyond this single file = instant startup.
export default defineConfig({
  plugins: [viteSingleFile()],
  build: {
    outDir: '../Notez/Resources',
    emptyOutDir: false,
    rollupOptions: { input: 'editor.html' },
  },
})
