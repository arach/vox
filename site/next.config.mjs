import path from "path";
import { fileURLToPath } from "url";
import { PHASE_DEVELOPMENT_SERVER } from "next/constants.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export default function nextConfig(phase) {
  const developmentDocsProxy = phase === PHASE_DEVELOPMENT_SERVER
    ? {
        async rewrites() {
          return [
            { source: "/docs/:path*", destination: "http://127.0.0.1:4321/docs/:path*" },
            { source: "/_astro/:path*", destination: "http://127.0.0.1:4321/_astro/:path*" },
            { source: "/@vite/:path*", destination: "http://127.0.0.1:4321/@vite/:path*" },
            { source: "/@fs/:path*", destination: "http://127.0.0.1:4321/@fs/:path*" },
            { source: "/@id/:path*", destination: "http://127.0.0.1:4321/@id/:path*" },
            { source: "/node_modules/:path*", destination: "http://127.0.0.1:4321/node_modules/:path*" },
            { source: "/src/:path*", destination: "http://127.0.0.1:4321/src/:path*" },
            { source: "/pagefind/:path*", destination: "http://127.0.0.1:4321/pagefind/:path*" },
            { source: "/llms.txt", destination: "http://127.0.0.1:4321/llms.txt" },
            { source: "/llms-full.txt", destination: "http://127.0.0.1:4321/llms-full.txt" },
          ];
        },
      }
    : {};

  return {
    ...(phase === PHASE_DEVELOPMENT_SERVER ? {} : { output: "export" }),
    trailingSlash: true,
    images: {
      unoptimized: true,
    },
    turbopack: {
      root: path.join(__dirname, ".."),
    },
    ...(phase === PHASE_DEVELOPMENT_SERVER ? { allowedDevOrigins: ["127.0.0.1"] } : {}),
    ...developmentDocsProxy,
  };
}
