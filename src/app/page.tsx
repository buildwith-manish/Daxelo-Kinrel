'use client'

import { useState, useEffect } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import {
  TreePine,
  Globe,
  Languages,
  Bot,
  WifiOff,
  Shield,
  Search,
  Bell,
  Users,
  GitBranch,
  Sparkles,
  ChevronRight,
  Github,
  ExternalLink,
  Star,
  ArrowRight,
  Moon,
  Sun,
  Zap,
  Heart,
  BookOpen,
  Smartphone,
  Server,
  Database,
  Lock,
  Menu,
  X,
} from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { useTheme } from 'next-themes'

/* ─── Feature Data ──────────────────────────────────── */
const features = [
  {
    icon: TreePine,
    title: 'Interactive Family Tree',
    description: 'Build and explore family trees with 500+ members. Zoom, pan, and collapse branches with intuitive gestures.',
    color: '#E8612A',
  },
  {
    icon: GitBranch,
    title: 'Family Graph Engine',
    description: '8 core relationship types generate 50+ derived kinship terms automatically using our graph engine.',
    color: '#F59240',
  },
  {
    icon: Bot,
    title: 'AI Relationship Discovery',
    description: 'AI-powered kinship explanations and relationship discovery across cultures and languages.',
    color: '#D4AF37',
  },
  {
    icon: Languages,
    title: '7 Indian Languages',
    description: 'Full support for Hindi, Marathi, Tamil, Telugu, Kannada, Bengali, and Gujarati kinship terms.',
    color: '#4CAF7A',
  },
  {
    icon: WifiOff,
    title: 'Offline-First Design',
    description: 'Drift + SQLite offline database with background sync. Works without internet, syncs when connected.',
    color: '#60A5FA',
  },
  {
    icon: Search,
    title: 'Smart Search',
    description: 'Fuzzy search across users, families, and relationships. Works offline with local database.',
    color: '#E8612A',
  },
  {
    icon: Bell,
    title: 'Smart Notifications',
    description: 'Intelligent alerts for invites, birthdays, anniversaries, and family events.',
    color: '#F59240',
  },
  {
    icon: Shield,
    title: 'Enterprise Security',
    description: 'JWT auth, RLS policies, role guards, rate limiting, and 2FA encryption with AES-256.',
    color: '#D4AF37',
  },
  {
    icon: Users,
    title: 'Family ID & QR Codes',
    description: 'Instagram-style @username system, KIN-AB12CD34 family IDs with QR codes and deep links.',
    color: '#4CAF7A',
  },
]

const languages = [
  { name: 'Hindi', native: 'हिन्दी', code: 'hi' },
  { name: 'Marathi', native: 'मराठी', code: 'mr' },
  { name: 'Tamil', native: 'தமிழ்', code: 'ta' },
  { name: 'Telugu', native: 'తెలుగు', code: 'te' },
  { name: 'Kannada', native: 'ಕನ್ನಡ', code: 'kn' },
  { name: 'Bengali', native: 'বাংলা', code: 'bn' },
  { name: 'Gujarati', native: 'ગુજરાતી', code: 'gu' },
]

const techStack = [
  {
    category: 'Mobile/Desktop',
    icon: Smartphone,
    tech: 'Flutter',
    description: 'Android, iOS, Web, Windows, macOS, Linux',
    color: '#60A5FA',
  },
  {
    category: 'Backend',
    icon: Server,
    tech: 'NestJS',
    description: '28 modules, 102+ unit tests',
    color: '#E8612A',
  },
  {
    category: 'Database',
    icon: Database,
    tech: 'PostgreSQL + Drift',
    description: 'Supabase online, SQLite offline',
    color: '#4CAF7A',
  },
  {
    category: 'Auth & Security',
    icon: Lock,
    tech: 'Supabase Auth',
    description: 'JWT, RLS, 2FA, AES-256',
    color: '#F59240',
  },
  {
    category: 'Realtime',
    icon: Zap,
    tech: 'Socket.IO + Supabase',
    description: 'Live updates, notifications',
    color: '#D4AF37',
  },
  {
    category: 'ORM',
    icon: BookOpen,
    tech: 'Prisma + Drift',
    description: 'Backend ORM + Flutter offline DB',
    color: '#60A5FA',
  },
]

const stats = [
  { label: 'Languages', value: '7+', icon: Languages },
  { label: 'Kinship Terms', value: '50+', icon: GitBranch },
  { label: 'NestJS Modules', value: '28', icon: Server },
  { label: 'Unit Tests', value: '102+', icon: Shield },
]

/* ─── Components ────────────────────────────────────── */

function ThemeToggle() {
  const { theme, setTheme } = useTheme()
  const [mounted, setMounted] = useState(false)

  useEffect(() => { setMounted(true) }, [])

  if (!mounted) return <div className="w-9 h-9" />

  return (
    <Button
      variant="ghost"
      size="icon"
      onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
      className="rounded-full hover:bg-primary/10"
    >
      {theme === 'dark' ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
    </Button>
  )
}

function Navbar() {
  const [scrolled, setScrolled] = useState(false)
  const [mobileOpen, setMobileOpen] = useState(false)

  useEffect(() => {
    const handler = () => setScrolled(window.scrollY > 20)
    window.addEventListener('scroll', handler)
    return () => window.removeEventListener('scroll', handler)
  }, [])

  return (
    <motion.nav
      initial={{ y: -100 }}
      animate={{ y: 0 }}
      transition={{ duration: 0.6, ease: 'easeOut' }}
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled
          ? 'glass-card shadow-lg shadow-black/20'
          : 'bg-transparent'
      }`}
    >
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex items-center justify-between h-16">
          {/* Logo */}
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[#E8612A] to-[#F59240] flex items-center justify-center">
              <TreePine className="h-5 w-5 text-white" />
            </div>
            <span className="text-lg font-bold text-gradient-kinrel">Daxelo Kinrel</span>
          </div>

          {/* Desktop Nav */}
          <div className="hidden md:flex items-center gap-6">
            <a href="#features" className="text-sm text-muted-foreground hover:text-primary transition-colors">Features</a>
            <a href="#languages" className="text-sm text-muted-foreground hover:text-primary transition-colors">Languages</a>
            <a href="#tech" className="text-sm text-muted-foreground hover:text-primary transition-colors">Tech Stack</a>
            <a href="https://github.com/buildwith-manish/Daxelo-Kinrel" target="_blank" rel="noopener noreferrer" className="text-sm text-muted-foreground hover:text-primary transition-colors flex items-center gap-1">
              <Github className="h-4 w-4" /> GitHub
            </a>
            <ThemeToggle />
            <Button className="bg-gradient-to-r from-[#E8612A] to-[#F59240] hover:opacity-90 text-white border-0">
              Get Started <ArrowRight className="ml-2 h-4 w-4" />
            </Button>
          </div>

          {/* Mobile Menu */}
          <div className="flex md:hidden items-center gap-2">
            <ThemeToggle />
            <Button variant="ghost" size="icon" onClick={() => setMobileOpen(!mobileOpen)}>
              {mobileOpen ? <X className="h-5 w-5" /> : <Menu className="h-5 w-5" />}
            </Button>
          </div>
        </div>
      </div>

      {/* Mobile Nav Dropdown */}
      <AnimatePresence>
        {mobileOpen && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            className="md:hidden glass-card border-t border-border"
          >
            <div className="px-4 py-4 flex flex-col gap-3">
              <a href="#features" onClick={() => setMobileOpen(false)} className="text-sm text-muted-foreground hover:text-primary transition-colors py-2">Features</a>
              <a href="#languages" onClick={() => setMobileOpen(false)} className="text-sm text-muted-foreground hover:text-primary transition-colors py-2">Languages</a>
              <a href="#tech" onClick={() => setMobileOpen(false)} className="text-sm text-muted-foreground hover:text-primary transition-colors py-2">Tech Stack</a>
              <a href="https://github.com/buildwith-manish/Daxelo-Kinrel" target="_blank" rel="noopener noreferrer" className="text-sm text-muted-foreground hover:text-primary transition-colors py-2 flex items-center gap-1">
                <Github className="h-4 w-4" /> GitHub
              </a>
              <Button className="bg-gradient-to-r from-[#E8612A] to-[#F59240] hover:opacity-90 text-white border-0 w-full">
                Get Started <ArrowRight className="ml-2 h-4 w-4" />
              </Button>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.nav>
  )
}

function HeroSection() {
  return (
    <section className="relative min-h-screen flex items-center justify-center overflow-hidden pt-16">
      {/* Background effects */}
      <div className="absolute inset-0 overflow-hidden">
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-[#E8612A]/10 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 right-1/4 w-96 h-96 bg-[#F59240]/10 rounded-full blur-3xl" />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-[#E8612A]/5 rounded-full blur-3xl" />
      </div>

      <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
        <div className="grid lg:grid-cols-2 gap-12 items-center">
          {/* Left: Text content */}
          <motion.div
            initial={{ opacity: 0, x: -50 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.8, ease: 'easeOut' }}
            className="space-y-8"
          >
            <div className="space-y-4">
              <Badge variant="secondary" className="bg-primary/10 text-primary border-primary/20 hover:bg-primary/20">
                <Sparkles className="h-3 w-3 mr-1" /> Indian Family Relationship Intelligence
              </Badge>
              <h1 className="text-4xl sm:text-5xl lg:text-6xl font-extrabold leading-tight">
                Map Your Family{' '}
                <span className="text-gradient-kinrel">Relationships</span>{' '}
                in 7 Languages
              </h1>
              <p className="text-lg text-muted-foreground max-w-xl">
                Daxelo Kinrel is the #1 family relationship intelligence app for Indian families.
                Discover kinship terms, build interactive family trees, and connect with your heritage — all offline.
              </p>
            </div>

            <div className="flex flex-wrap gap-4">
              <Button size="lg" className="bg-gradient-to-r from-[#E8612A] to-[#F59240] hover:opacity-90 text-white border-0 kinrel-glow">
                <TreePine className="mr-2 h-5 w-5" /> Start Building
              </Button>
              <Button size="lg" variant="outline" className="border-primary/30 hover:bg-primary/10" asChild>
                <a href="https://github.com/buildwith-manish/Daxelo-Kinrel" target="_blank" rel="noopener noreferrer">
                  <Github className="mr-2 h-5 w-5" /> View on GitHub
                </a>
              </Button>
            </div>

            {/* Stats row */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 pt-4">
              {stats.map((stat, i) => (
                <motion.div
                  key={stat.label}
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.4 + i * 0.1, duration: 0.5 }}
                  className="text-center"
                >
                  <div className="text-2xl font-bold text-gradient-kinrel">{stat.value}</div>
                  <div className="text-xs text-muted-foreground">{stat.label}</div>
                </motion.div>
              ))}
            </div>
          </motion.div>

          {/* Right: Hero image */}
          <motion.div
            initial={{ opacity: 0, x: 50 }}
            animate={{ opacity: 1, x: 0 }}
            transition={{ duration: 0.8, ease: 'easeOut', delay: 0.2 }}
            className="relative"
          >
            <div className="relative rounded-2xl overflow-hidden shadow-2xl shadow-[#E8612A]/20 border border-border/50 kinrel-float">
              <img
                src="/hero-image.png"
                alt="Daxelo Kinrel - Indian Family Tree Visualization"
                className="w-full h-auto rounded-2xl"
              />
              <div className="absolute inset-0 bg-gradient-to-t from-background/80 via-transparent to-transparent" />
            </div>

            {/* Floating badges */}
            <motion.div
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 1, duration: 0.5 }}
              className="absolute -top-4 -right-4 glass-card rounded-xl p-3 flex items-center gap-2"
            >
              <div className="w-8 h-8 rounded-full bg-[#4CAF7A]/20 flex items-center justify-center">
                <WifiOff className="h-4 w-4 text-[#4CAF7A]" />
              </div>
              <span className="text-sm font-medium">Works Offline</span>
            </motion.div>

            <motion.div
              initial={{ opacity: 0, scale: 0.8 }}
              animate={{ opacity: 1, scale: 1 }}
              transition={{ delay: 1.2, duration: 0.5 }}
              className="absolute -bottom-4 -left-4 glass-card rounded-xl p-3 flex items-center gap-2"
            >
              <div className="w-8 h-8 rounded-full bg-[#E8612A]/20 flex items-center justify-center">
                <Languages className="h-4 w-4 text-[#E8612A]" />
              </div>
              <span className="text-sm font-medium">7 Languages</span>
            </motion.div>
          </motion.div>
        </div>
      </div>
    </section>
  )
}

function FeaturesSection() {
  return (
    <section id="features" className="py-24 relative">
      <div className="absolute inset-0 overflow-hidden">
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[800px] h-[400px] bg-[#E8612A]/5 rounded-full blur-3xl" />
      </div>

      <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="text-center space-y-4 mb-16"
        >
          <Badge variant="secondary" className="bg-primary/10 text-primary border-primary/20">
            <Sparkles className="h-3 w-3 mr-1" /> Features
          </Badge>
          <h2 className="text-3xl sm:text-4xl font-bold">
            Everything You Need for{' '}
            <span className="text-gradient-kinrel">Family Intelligence</span>
          </h2>
          <p className="text-muted-foreground max-w-2xl mx-auto">
            From interactive family trees to AI-powered kinship discovery, Daxelo Kinrel has every tool to map and understand your family relationships.
          </p>
        </motion.div>

        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {features.map((feature, i) => (
            <motion.div
              key={feature.title}
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.08, duration: 0.5 }}
            >
              <Card className="group h-full bg-card/50 border-border/50 hover:border-primary/30 transition-all duration-300 hover:shadow-lg hover:shadow-primary/5">
                <CardContent className="p-6 space-y-4">
                  <div
                    className="w-12 h-12 rounded-xl flex items-center justify-center transition-transform duration-300 group-hover:scale-110"
                    style={{ backgroundColor: `${feature.color}15` }}
                  >
                    <feature.icon className="h-6 w-6" style={{ color: feature.color }} />
                  </div>
                  <h3 className="text-lg font-semibold">{feature.title}</h3>
                  <p className="text-sm text-muted-foreground leading-relaxed">{feature.description}</p>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  )
}

function LanguagesSection() {
  return (
    <section id="languages" className="py-24 relative bg-card/30">
      <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="text-center space-y-4 mb-16"
        >
          <Badge variant="secondary" className="bg-primary/10 text-primary border-primary/20">
            <Globe className="h-3 w-3 mr-1" /> Multilingual
          </Badge>
          <h2 className="text-3xl sm:text-4xl font-bold">
            Speak Your Family&apos;s{' '}
            <span className="text-gradient-kinrel">Language</span>
          </h2>
          <p className="text-muted-foreground max-w-2xl mx-auto">
            Full kinship term support across 7 major Indian languages. Every relationship term is culturally accurate and contextually appropriate.
          </p>
        </motion.div>

        <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-7 gap-4">
          {languages.map((lang, i) => (
            <motion.div
              key={lang.code}
              initial={{ opacity: 0, scale: 0.8 }}
              whileInView={{ opacity: 1, scale: 1 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.08, duration: 0.4 }}
            >
              <Card className="group text-center hover:border-primary/30 transition-all duration-300 hover:shadow-lg hover:shadow-primary/5 cursor-pointer">
                <CardContent className="p-4 space-y-2">
                  <div className="text-3xl font-bold text-gradient-kinrel">{lang.native}</div>
                  <div className="text-sm font-medium">{lang.name}</div>
                  <Badge variant="outline" className="text-xs">{lang.code.toUpperCase()}</Badge>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>

        {/* Language example cards */}
        <div className="mt-16 grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {[
            { lang: 'Hindi', examples: ['पिता (Father)', 'माता (Mother)', 'भाई (Brother)', 'बहन (Sister)', 'चाचा (Uncle - Paternal)'] },
            { lang: 'Tamil', examples: ['அப்பா (Father)', 'அம்மா (Mother)', 'அண்ணன் (Elder Brother)', 'தங்கை (Younger Sister)', 'சித்தப்பா (Uncle)'] },
            { lang: 'Bengali', examples: ['বাবা (Father)', 'মা (Mother)', 'দাদা (Elder Brother)', 'দিদি (Elder Sister)', 'কাকা (Uncle)'] },
          ].map((item, i) => (
            <motion.div
              key={item.lang}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.1, duration: 0.5 }}
            >
              <Card className="h-full bg-card/50 border-border/50">
                <CardContent className="p-6 space-y-4">
                  <div className="flex items-center gap-2">
                    <Languages className="h-5 w-5 text-primary" />
                    <h3 className="font-semibold">{item.lang} Kinship Terms</h3>
                  </div>
                  <ul className="space-y-2">
                    {item.examples.map((ex) => (
                      <li key={ex} className="text-sm text-muted-foreground flex items-center gap-2">
                        <ChevronRight className="h-3 w-3 text-primary flex-shrink-0" />
                        {ex}
                      </li>
                    ))}
                  </ul>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  )
}

function TechStackSection() {
  return (
    <section id="tech" className="py-24 relative">
      <div className="absolute inset-0 overflow-hidden">
        <div className="absolute bottom-0 right-1/4 w-[600px] h-[300px] bg-[#F59240]/5 rounded-full blur-3xl" />
      </div>

      <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="text-center space-y-4 mb-16"
        >
          <Badge variant="secondary" className="bg-primary/10 text-primary border-primary/20">
            <Zap className="h-3 w-3 mr-1" /> Architecture
          </Badge>
          <h2 className="text-3xl sm:text-4xl font-bold">
            Built with{' '}
            <span className="text-gradient-kinrel">Modern Stack</span>
          </h2>
          <p className="text-muted-foreground max-w-2xl mx-auto">
            A robust, scalable architecture combining Flutter for cross-platform mobile, NestJS for the backend, and Supabase for real-time capabilities.
          </p>
        </motion.div>

        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-6">
          {techStack.map((item, i) => (
            <motion.div
              key={item.tech}
              initial={{ opacity: 0, y: 20 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ delay: i * 0.1, duration: 0.5 }}
            >
              <Card className="group h-full bg-card/50 border-border/50 hover:border-primary/30 transition-all duration-300">
                <CardContent className="p-6 space-y-4">
                  <div className="flex items-center gap-4">
                    <div
                      className="w-12 h-12 rounded-xl flex items-center justify-center transition-transform group-hover:scale-110"
                      style={{ backgroundColor: `${item.color}15` }}
                    >
                      <item.icon className="h-6 w-6" style={{ color: item.color }} />
                    </div>
                    <div>
                      <div className="text-sm text-muted-foreground">{item.category}</div>
                      <div className="text-lg font-semibold">{item.tech}</div>
                    </div>
                  </div>
                  <p className="text-sm text-muted-foreground">{item.description}</p>
                </CardContent>
              </Card>
            </motion.div>
          ))}
        </div>

        {/* Architecture diagram */}
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="mt-16"
        >
          <Card className="bg-card/50 border-border/50">
            <CardContent className="p-6 sm:p-8">
              <h3 className="text-lg font-semibold mb-6 text-center">System Architecture</h3>
              <div className="flex flex-col sm:flex-row items-center justify-center gap-4 sm:gap-2">
                {/* Flutter App */}
                <div className="glass-card rounded-xl p-4 text-center min-w-[140px]">
                  <Smartphone className="h-6 w-6 mx-auto mb-2 text-[#60A5FA]" />
                  <div className="text-sm font-semibold">Flutter App</div>
                  <div className="text-xs text-muted-foreground">7 Platforms</div>
                </div>

                <ArrowRight className="h-5 w-5 text-primary hidden sm:block flex-shrink-0" />
                <div className="h-px w-8 bg-primary/50 sm:hidden" />

                {/* NestJS Backend */}
                <div className="glass-card rounded-xl p-4 text-center min-w-[140px]">
                  <Server className="h-6 w-6 mx-auto mb-2 text-[#E8612A]" />
                  <div className="text-sm font-semibold">NestJS</div>
                  <div className="text-xs text-muted-foreground">28 Modules</div>
                </div>

                <ArrowRight className="h-5 w-5 text-primary hidden sm:block flex-shrink-0" />
                <div className="h-px w-8 bg-primary/50 sm:hidden" />

                {/* Database */}
                <div className="glass-card rounded-xl p-4 text-center min-w-[140px]">
                  <Database className="h-6 w-6 mx-auto mb-2 text-[#4CAF7A]" />
                  <div className="text-sm font-semibold">PostgreSQL</div>
                  <div className="text-xs text-muted-foreground">Supabase + Drift</div>
                </div>

                <ArrowRight className="h-5 w-5 text-primary hidden sm:block flex-shrink-0" />
                <div className="h-px w-8 bg-primary/50 sm:hidden" />

                {/* Auth */}
                <div className="glass-card rounded-xl p-4 text-center min-w-[140px]">
                  <Lock className="h-6 w-6 mx-auto mb-2 text-[#F59240]" />
                  <div className="text-sm font-semibold">Supabase Auth</div>
                  <div className="text-xs text-muted-foreground">JWT + RLS</div>
                </div>
              </div>
            </CardContent>
          </Card>
        </motion.div>
      </div>
    </section>
  )
}

function CTASection() {
  return (
    <section className="py-24 relative">
      <div className="absolute inset-0 overflow-hidden">
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-[#E8612A]/8 rounded-full blur-3xl" />
      </div>

      <div className="relative max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6 }}
          className="space-y-8"
        >
          <div className="space-y-4">
            <h2 className="text-3xl sm:text-4xl font-bold">
              Ready to Map Your{' '}
              <span className="text-gradient-kinrel">Family Heritage</span>?
            </h2>
            <p className="text-muted-foreground max-w-2xl mx-auto text-lg">
              Join thousands of Indian families who are preserving their kinship knowledge with Daxelo Kinrel.
            </p>
          </div>

          <div className="flex flex-wrap justify-center gap-4">
            <Button size="lg" className="bg-gradient-to-r from-[#E8612A] to-[#F59240] hover:opacity-90 text-white border-0 kinrel-glow">
              <TreePine className="mr-2 h-5 w-5" /> Get Started Free
            </Button>
            <Button size="lg" variant="outline" className="border-primary/30 hover:bg-primary/10" asChild>
              <a href="https://github.com/buildwith-manish/Daxelo-Kinrel" target="_blank" rel="noopener noreferrer">
                <Star className="mr-2 h-5 w-4" /> Star on GitHub
              </a>
            </Button>
          </div>
        </motion.div>
      </div>
    </section>
  )
}

function Footer() {
  return (
    <footer className="border-t border-border bg-card/30">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div className="grid sm:grid-cols-2 lg:grid-cols-4 gap-8">
          {/* Brand */}
          <div className="space-y-4">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[#E8612A] to-[#F59240] flex items-center justify-center">
                <TreePine className="h-5 w-5 text-white" />
              </div>
              <span className="text-lg font-bold text-gradient-kinrel">Daxelo Kinrel</span>
            </div>
            <p className="text-sm text-muted-foreground">
              Indian Family Relationship Intelligence — Map relationships in 7 Indian languages.
            </p>
          </div>

          {/* Product */}
          <div className="space-y-3">
            <h4 className="font-semibold text-sm">Product</h4>
            <ul className="space-y-2">
              {['Family Tree', 'Kinship Terms', 'AI Discovery', 'Offline Mode', 'Smart Notifications'].map((item) => (
                <li key={item}>
                  <span className="text-sm text-muted-foreground hover:text-primary transition-colors cursor-pointer">{item}</span>
                </li>
              ))}
            </ul>
          </div>

          {/* Languages */}
          <div className="space-y-3">
            <h4 className="font-semibold text-sm">Languages</h4>
            <ul className="space-y-2">
              {languages.slice(0, 5).map((lang) => (
                <li key={lang.code}>
                  <span className="text-sm text-muted-foreground hover:text-primary transition-colors cursor-pointer">
                    {lang.name} ({lang.native})
                  </span>
                </li>
              ))}
            </ul>
          </div>

          {/* Resources */}
          <div className="space-y-3">
            <h4 className="font-semibold text-sm">Resources</h4>
            <ul className="space-y-2">
              <li>
                <a href="https://github.com/buildwith-manish/Daxelo-Kinrel" target="_blank" rel="noopener noreferrer" className="text-sm text-muted-foreground hover:text-primary transition-colors flex items-center gap-1">
                  <Github className="h-3 w-3" /> GitHub Repository
                </a>
              </li>
              <li>
                <a href="https://github.com/buildwith-manish/Daxelo-Kinrel/blob/main/README.md" target="_blank" rel="noopener noreferrer" className="text-sm text-muted-foreground hover:text-primary transition-colors flex items-center gap-1">
                  <ExternalLink className="h-3 w-3" /> Documentation
                </a>
              </li>
              <li>
                <a href="https://github.com/buildwith-manish/Daxelo-Kinrel/issues" target="_blank" rel="noopener noreferrer" className="text-sm text-muted-foreground hover:text-primary transition-colors flex items-center gap-1">
                  <ExternalLink className="h-3 w-3" /> Issue Tracker
                </a>
              </li>
            </ul>
          </div>
        </div>

        <div className="mt-12 pt-8 border-t border-border flex flex-col sm:flex-row items-center justify-between gap-4">
          <p className="text-xs text-muted-foreground">
            © {new Date().getFullYear()} Daxelo Kinrel. All rights reserved.
          </p>
          <div className="flex items-center gap-4">
            <a href="https://github.com/buildwith-manish/Daxelo-Kinrel" target="_blank" rel="noopener noreferrer" className="text-muted-foreground hover:text-primary transition-colors">
              <Github className="h-5 w-5" />
            </a>
            <span className="text-xs text-muted-foreground flex items-center gap-1">
              Made with <Heart className="h-3 w-3 text-[#E8612A]" /> in India
            </span>
          </div>
        </div>
      </div>
    </footer>
  )
}

/* ─── Main Page ─────────────────────────────────────── */
export default function Home() {
  return (
    <div className="min-h-screen flex flex-col">
      <Navbar />
      <main className="flex-1">
        <HeroSection />
        <FeaturesSection />
        <LanguagesSection />
        <TechStackSection />
        <CTASection />
      </main>
      <Footer />
    </div>
  )
}
