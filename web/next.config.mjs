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
        // 127.0.0.1, not "localhost": on Windows, "localhost" may resolve
        // to ::1 (IPv6) where uvicorn isn't listening — one of the causes
        // behind the ECONNRESET flood in dev. (The UI calls the backend
        // directly anyway; this proxy is only the fallback route.)
        destination: "http://127.0.0.1:8000/api/:path*",
      },
    ];
  },
};

export default nextConfig;
