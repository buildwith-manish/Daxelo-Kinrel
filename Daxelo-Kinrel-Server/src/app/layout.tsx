import type { Metadata, Viewport } from "next";
import { Outfit, DM_Sans, DM_Mono } from "next/font/google";
import "./globals.css";
import { Toaster } from "@/components/ui/toaster";
import { ThemeProvider } from "next-themes";
import { FestivalThemeProvider } from "@/components/kinrel/festival-theme-provider";
import { LocaleProvider } from "@/components/kinrel/locale-provider";

// ── Font setup (Kinrel brand: Outfit + DM Sans + DM Mono) ──────────────

const outfit = Outfit({
  subsets: ["latin"],
  weight:  ["400", "700", "800"],
  variable: "--font-outfit",
  display: "swap",
});

const dmSans = DM_Sans({
  subsets: ["latin"],
  weight:  ["300", "400", "500", "700"],
  variable: "--font-dm-sans",
  display: "swap",
});

const dmMono = DM_Mono({
  subsets: ["latin"],
  weight:  ["400", "500"],
  variable: "--font-dm-mono",
  display: "swap",
});

// ── Metadata ──────────────────────────────────────────────────────────

export const metadata: Metadata = {
  metadataBase: new URL("https://daxelokinrel.com"),

  title: {
    default:  "Kinrel — Family Relationship Intelligence by Daxelo",
    template: "%s · Kinrel",
  },
  description:
    "Map every family connection with AI-powered kinship names across 14 Indian languages. Built by Daxelo.",

  applicationName: "Kinrel",
  authors: [{ name: "Daxelo", url: "https://daxelokinrel.com" }],
  keywords: [
    "family tree", "kinship", "Indian family", "relationship names",
    "family graph", "daxelo", "kinrel",
  ],
  creator:   "Daxelo",
  publisher: "Daxelo",

  icons: {
    icon: [
      { url: "/brand/icons/kinrel-icon-mini.svg", type: "image/svg+xml" },
    ],
    apple: "/brand/icons/kinrel-icon-primary.svg",
  },

  openGraph: {
    type:        "website",
    url:         "https://daxelokinrel.com",
    siteName:    "Kinrel",
    title:       "Kinrel — Family Relationship Intelligence",
    description: "AI-powered Indian family graph — map every kinship connection.",
    images: [
      {
        url:    "/brand/og-image.svg",
        width:  1200,
        height: 630,
        alt:    "Kinrel — Family Relationship Intelligence by Daxelo",
      },
    ],
    locale: "en_IN",
  },

  twitter: {
    card:        "summary_large_image",
    title:       "Kinrel — Family Relationship Intelligence",
    description: "AI-powered Indian family graph — map every kinship connection.",
    creator:     "@daxeloapp",
  },

  robots: {
    index:  true,
    follow: true,
    googleBot: { index: true, follow: true },
  },

  alternates: {
    canonical: "https://daxelokinrel.com",
  },
};

// ── Viewport ──────────────────────────────────────────────────────────

export const viewport: Viewport = {
  themeColor:   "#E8612A",
  colorScheme:  "dark",
  width:        "device-width",
  initialScale: 1,
  maximumScale: 1,
};

// ── Root layout ───────────────────────────────────────────────────────

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${outfit.variable} ${dmSans.variable} ${dmMono.variable}`}
      suppressHydrationWarning
    >
      <head>
        <meta name="msapplication-TileColor"   content="#13141E" />
        <meta name="msapplication-TileImage"   content="/brand/icons/kinrel-icon-primary.svg" />
      </head>
      <body
        className={`${outfit.variable} ${dmSans.variable} ${dmMono.variable} antialiased`}
        style={{
          backgroundColor: "var(--kinrel-bg)",
          color:           "var(--kinrel-white)",
          fontFamily:      "var(--kinrel-font-body)",
        }}
      >
        <ThemeProvider
          attribute="class"
          defaultTheme="dark"
          enableSystem
          disableTransitionOnChange
        >
          <LocaleProvider>
            <FestivalThemeProvider>
              {children}
              <Toaster />
            </FestivalThemeProvider>
          </LocaleProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
