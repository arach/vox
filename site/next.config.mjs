import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const nextConfig = {
  transpilePackages: ["@arach/dewey"],
  turbopack: {
    root: path.join(__dirname, ".."),
  },
};

export default nextConfig;
