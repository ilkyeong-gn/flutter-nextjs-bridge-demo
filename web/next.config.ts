import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  // Android 에뮬레이터는 10.0.2.2로 접속하므로 dev 리소스 cross-origin 차단 허용 필요
  allowedDevOrigins: ['10.0.2.2'],
  cacheComponents: true,
  partialPrefetching: true,
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
