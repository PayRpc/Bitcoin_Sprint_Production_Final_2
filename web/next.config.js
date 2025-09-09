/** @type {import('next').NextConfig} */
const nextConfig = {
  // Minimal working configuration - no complex features
  env: {
    NEXT_PUBLIC_APP_ENV: process.env.NEXT_PUBLIC_APP_ENV || 'development',
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL || 'http://localhost:9001/api',
  },
  images: {
    unoptimized: true,
    domains: ['localhost'],
  },
  // Disable all experimental features that can cause crashes
  experimental: {
    // Disable all experimental features
  },
  // No rewrites, headers, or webpack config
}

export default nextConfig
