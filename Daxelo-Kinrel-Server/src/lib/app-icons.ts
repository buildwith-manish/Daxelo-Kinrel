/**
 * DAXELO KINREL — Icon System
 *
 * Custom icon mapping for domain-specific concepts.
 * Maps KINREL concepts to Lucide icon names.
 *
 * Pack 01: Design System — Icons & Imagery
 */

import {
  TreePine, Heart, Link2, Tag, Users, UserPlus, Sparkles,
  Cake, HeartHandshake, Flower2, MessageCircle, Citrus,
  Settings, Search, ArrowLeft, X, MoreVertical, Pencil,
  Trash2, Share2, Copy, Check, AlertCircle, Info,
  AlertTriangle, CheckCircle2, Globe, Shield, Activity,
  Download, Smartphone, Bell, Eye, FileText, Phone,
  Lock, Zap, BookOpen, ChevronRight, Star
} from 'lucide-react'

// ── Domain-specific icon mapping ────────────────────────────────────
export const appIcons = {
  // Family & Relationships
  family: TreePine,
  person: Users,
  relationship: Link2,
  gotra: Tag,
  tree: TreePine,
  invite: UserPlus,

  // Events & Celebrations
  birthday: Cake,
  anniversary: HeartHandshake,
  memorial: Flower2,

  // Communication
  whatsapp: MessageCircle,

  // Features
  matrimonial: Heart,
  health: Activity,
  accessibility: Eye,

  // Standard actions
  settings: Settings,
  search: Search,
  back: ArrowLeft,
  close: X,
  more: MoreVertical,
  edit: Pencil,
  delete: Trash2,
  share: Share2,
  copy: Copy,
  check: Check,
  error: AlertCircle,
  info: Info,
  warning: AlertTriangle,
  success: CheckCircle2,

  // Navigation
  chevronRight: ChevronRight,
  star: Star,

  // Premium
  premium: Star,

  // Other
  globe: Globe,
  shield: Shield,
  download: Download,
  smartphone: Smartphone,
  notification: Bell,
  document: FileText,
  phone: Phone,
  lock: Lock,
  zap: Zap,
  bookOpen: BookOpen,
} as const

// ── Icon size tokens ────────────────────────────────────────────────
export const iconSizes = {
  xs: 14,
  sm: 16,
  md: 20,
  lg: 24,
  xl: 32,
} as const

export type AppIconName = keyof typeof appIcons
