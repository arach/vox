import { defineConfig } from 'astro/config'
import tailwind from '@tailwindcss/vite'
import rehypeDocLinks from './src/lib/rehype-doc-links.mjs'

export default defineConfig({
  devToolbar: { enabled: false },
  markdown: {
    rehypePlugins: [rehypeDocLinks],
    shikiConfig: {
      theme: 'vitesse-dark',
    },
  },
  vite: {
    plugins: [tailwind()],
  },
})
