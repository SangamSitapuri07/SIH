import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "ORCA — Marine Intelligence",
  description: "Marine EcOsystem Reasoning with Collaborative Agents — SIH 2026 PS 176",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  );
}
