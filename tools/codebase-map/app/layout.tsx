import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Intentive — Codebase map",
  description: "Explore how Intentive captures, understands, remembers, retrieves, and acts.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en"><body>{children}</body></html>;
}
