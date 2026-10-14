import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Dua halaman: panel (index.html) dan halaman publik titik genangan (titik.html) untuk tautan bagikan.
export default defineConfig({
  plugins: [react()],
  build: { rollupOptions: { input: { main: 'index.html', titik: 'titik.html' } } },
})
