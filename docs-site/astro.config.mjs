import { defineConfig } from 'astro/config'
import tailwind from '@tailwindcss/vite'

export default defineConfig({
  markdown: {
    shikiConfig: {
      theme: 'vitesse-dark',
    },
  },
  vite: {
    plugins: [tailwind()],
  },
})
