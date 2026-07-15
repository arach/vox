import type { Metadata } from "next";
import Script from "next/script";
import {
  IBM_Plex_Mono,
  Space_Grotesk,
  Instrument_Serif,
} from "next/font/google";
import "./globals.css";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://voxd.cc";

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
  icons: {
    icon: "/logo.svg",
  },
  title: "Vox",
  description: "Vox powers transcription and text-to-speech for macOS, iOS, and web apps.",
  metadataBase: new URL(siteUrl),
  openGraph: {
    title: "Vox — macOS transcription and text-to-speech",
    description: "For macOS, iOS, and web apps. Embed Vox directly or integrate through Vox Companion.",
    url: siteUrl,
    siteName: "Vox",
    type: "website",
    images: [{ url: "/og.png" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "Vox — macOS transcription and text-to-speech",
    description: "For macOS, iOS, and web apps. Embed Vox directly or integrate through Vox Companion.",
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
        <Script
          src="https://www.googletagmanager.com/gtag/js?id=G-SCL11LG51S"
          strategy="afterInteractive"
        />
        <Script id="google-analytics" strategy="afterInteractive">
          {`
            window.dataLayer = window.dataLayer || [];
            function gtag(){dataLayer.push(arguments);}
            gtag('js', new Date());
            gtag('config', 'G-SCL11LG51S');

            document.addEventListener('click', function (event) {
              if (!(event.target instanceof Element)) return;

              const link = event.target.closest('a[href]');
              if (!link) return;

              const url = new URL(link.href, window.location.href);
              if (!url.pathname.toLowerCase().endsWith('.dmg')) return;

              const fileName = decodeURIComponent(url.pathname.split('/').pop() || '');
              gtag('event', 'installer_download', {
                file_name: fileName,
                installer_name: fileName.replace(/\.dmg$/i, ''),
                link_url: url.href,
                link_text: (link.textContent || '').trim(),
                transport_type: 'beacon'
              });
            });
          `}
        </Script>
      </body>
    </html>
  );
}
