import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://vox.arach.dev";

const geist = Geist({
  variable: "--font-sans",
  subsets: ["latin"],
  weight: ["400", "500", "700"],
});

const geistMono = Geist_Mono({
  variable: "--font-mono",
  subsets: ["latin"],
  weight: ["400", "500", "700"],
});

export const metadata: Metadata = {
  title: "Vox",
  description: "Local-first transcription runtime for macOS apps, CLIs, and developer tools.",
  metadataBase: new URL(siteUrl),
  openGraph: {
    title: "Vox",
    description: "A local-first transcription runtime for macOS apps, CLIs, and developer tools.",
    url: siteUrl,
    siteName: "Vox",
    type: "website",
    images: [{ url: "/og.png" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Vox",
    description: "Local-first transcription runtime for macOS apps, CLIs, and developer tools.",
    images: ["/og.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className={`${geist.variable} ${geistMono.variable}`}>
        {children}
      </body>
    </html>
  );
}
