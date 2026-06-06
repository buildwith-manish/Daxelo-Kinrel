import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import { Toaster } from "@/components/ui/toaster";
import { ThemeProvider } from "next-themes";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "Daxelo Kinrel — Indian Family Relationship Intelligence",
  description:
    "Map family relationships in 7 Indian languages. Interactive family trees, AI-powered kinship discovery, and offline-first design.",
  keywords: [
    "Daxelo Kinrel",
    "Indian family tree",
    "kinship terms",
    "Hindi relationships",
    "Marathi relationships",
    "Tamil relationships",
    "family graph",
    "relationship mapping",
  ],
  authors: [{ name: "Daxelo Kinrel Team" }],
  icons: {
    icon: "/kinrel-icon-primary.svg",
  },
  openGraph: {
    title: "Daxelo Kinrel — Indian Family Relationship Intelligence",
    description:
      "Map family relationships in 7 Indian languages with AI-powered kinship discovery.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body
        className={`${geistSans.variable} ${geistMono.variable} antialiased bg-background text-foreground`}
      >
        <ThemeProvider
          attribute="class"
          defaultTheme="dark"
          enableSystem
          disableTransitionOnChange
        >
          {children}
          <Toaster />
        </ThemeProvider>
      </body>
    </html>
  );
}
