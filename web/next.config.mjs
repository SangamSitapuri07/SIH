/** @type {import('next').NextConfig} */
const nextConfig = {
  // Allow the Arena preview proxy to embed the dev server
  allowedDevOrigins: [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "https://*.e2b.app",
  ],

  // Proxy /api/* requests to the FastAPI backend on port 8000
  // This is dev-only; in production the backend would be at a real URL.
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: "http://localhost:8000/api/:path*",
      },
    ];
  },
};

export default nextConfig;
