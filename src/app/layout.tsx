import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "LeadFinder — Home Services Lead Extraction",
  description: "Pull ranked home-service business leads. Website-first scoring, contact enrichment, CSV export.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
