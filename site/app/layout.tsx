import type { Metadata } from "next";
import { IBM_Plex_Mono, Space_Grotesk, Instrument_Serif } from "next/font/google";
import "./globals.css";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://vox.arach.dev";

const plexMono = IBM_Plex_Mono({
  variable: "--font-mono",
  subsets: ["latin"],
  weight: ["400", "500"],
});

const spaceGrotesk = Space_Grotesk({
  variable: "--font-sans",
  subsets: ["latin"],
  weight: ["300", "400", "500"],
});

const instrumentSerif = Instrument_Serif({
  variable: "--font-display",
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
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
      <body className={`${spaceGrotesk.variable} ${plexMono.variable} ${instrumentSerif.variable} font-light`}>
        {children}
      </body>
    </html>
  );
}
