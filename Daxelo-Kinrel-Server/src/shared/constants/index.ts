/**
 * KINREL Mirror — Shared Constants
 */

// ── API ───────────────────────────────────────────────────────────
export const API_V2_PREFIX = '/api/v2';
export const API_VERSION = '1.0.0';

// ── Auth ──────────────────────────────────────────────────────────
export const ACCESS_TOKEN_EXPIRY = '15m';
export const REFRESH_TOKEN_EXPIRY = '7d';
export const SESSION_MAX_AGE = 30 * 24 * 60 * 60; // 30 days in seconds

// ── Pagination ────────────────────────────────────────────────────
export const DEFAULT_PAGE_SIZE = 20;
export const MAX_PAGE_SIZE = 100;

// ── Supported Languages ───────────────────────────────────────────
export const SUPPORTED_LOCALES = [
  { code: 'en', name: 'English', native: 'English', script: 'Latin' },
  { code: 'hi', name: 'Hindi', native: 'हिन्दी', script: 'Devanagari' },
  { code: 'bn', name: 'Bengali', native: 'বাংলা', script: 'Bengali' },
  { code: 'te', name: 'Telugu', native: 'తెలుగు', script: 'Telugu' },
  { code: 'mr', name: 'Marathi', native: 'मराठी', script: 'Devanagari' },
  { code: 'ta', name: 'Tamil', native: 'தமிழ்', script: 'Tamil' },
  { code: 'ur', name: 'Urdu', native: 'اردو', script: 'Arabic', rtl: true },
  { code: 'gu', name: 'Gujarati', native: 'ગુજરાતી', script: 'Gujarati' },
  { code: 'kn', name: 'Kannada', native: 'ಕನ್ನಡ', script: 'Kannada' },
  { code: 'ml', name: 'Malayalam', native: 'മലയാളം', script: 'Malayalam' },
  { code: 'or', name: 'Odia', native: 'ଓଡ଼ିଆ', script: 'Oriya' },
  { code: 'pa', name: 'Punjabi', native: 'ਪੰਜਾਬੀ', script: 'Gurmukhi' },
  { code: 'as', name: 'Assamese', native: 'অসমীয়া', script: 'Bengali' },
  { code: 'sa', name: 'Sanskrit', native: 'संस्कृत', script: 'Devanagari' },
] as const;

// ── Family Roles ──────────────────────────────────────────────────
export const FAMILY_ROLES = [
  { value: 'admin', label: 'Admin', description: 'Full control over family settings and members' },
  { value: 'editor', label: 'Editor', description: 'Can add and edit persons and relationships' },
  { value: 'member', label: 'Member', description: 'Can view and add persons' },
  { value: 'viewer', label: 'Viewer', description: 'Read-only access to family data' },
] as const;

// ── Relationship Categories ───────────────────────────────────────
export const RELATIONSHIP_CATEGORIES = [
  { value: 'core_family', label: 'Core Family', labelHi: 'मूल परिवार' },
  { value: 'direct_descendant', label: 'Direct Descendant', labelHi: 'सीधे वंशज' },
  { value: 'grandparents', label: 'Grandparents', labelHi: 'दादा-दादी' },
  { value: 'direct_ancestor', label: 'Direct Ancestor', labelHi: 'सीधे पूर्वज' },
  { value: 'extended', label: 'Extended Family', labelHi: 'विस्तारित परिवार' },
  { value: 'cousins', label: 'Cousins', labelHi: 'चचेरे भाई-बहन' },
  { value: 'in_laws', label: 'In-Laws', labelHi: 'ससुराल पक्ष' },
  { value: 'step_family', label: 'Step Family', labelHi: 'सौतेला परिवार' },
  { value: 'adoptive_family', label: 'Adoptive Family', labelHi: 'दत्तक परिवार' },
] as const;

// ── Privacy Levels ────────────────────────────────────────────────
export const PRIVACY_LEVELS = [
  { value: 'family', label: 'Family Only', description: 'Visible only to family members' },
  { value: 'extended', label: 'Extended', description: 'Visible to connected families' },
  { value: 'public', label: 'Public', description: 'Visible to anyone with access' },
] as const;

// ── Moderation ────────────────────────────────────────────────────
export const REPORT_REASONS = [
  { value: 'spam', label: 'Spam' },
  { value: 'harassment', label: 'Harassment' },
  { value: 'hate_speech', label: 'Hate Speech' },
  { value: 'caste_reference', label: 'Caste Reference' },
  { value: 'misinformation', label: 'Misinformation' },
  { value: 'sexual_content', label: 'Sexual Content' },
  { value: 'violence', label: 'Violence' },
  { value: 'impersonation', label: 'Impersonation' },
  { value: 'pii_exposure', label: 'PII Exposure' },
  { value: 'other', label: 'Other' },
] as const;

// ── Indian Festival Calendar ──────────────────────────────────────
export const INDIAN_FESTIVALS = [
  { id: 'diwali', name: 'Diwali', nameHi: 'दिवाली', month: 'Oct-Nov', colorKey: 'diwali' },
  { id: 'holi', name: 'Holi', nameHi: 'होली', month: 'Mar', colorKey: 'holi' },
  { id: 'eid', name: 'Eid', nameHi: 'ईद', month: 'Variable', colorKey: 'eid' },
  { id: 'navratri', name: 'Navratri', nameHi: 'नवरात्रि', month: 'Oct', colorKey: 'navratri' },
  { id: 'onam', name: 'Onam', nameHi: 'ओणम', month: 'Aug-Sep', colorKey: 'onam' },
  { id: 'baisakhi', name: 'Baisakhi', nameHi: 'बैसाखी', month: 'Apr', colorKey: 'baisakhi' },
  { id: 'pongal', name: 'Pongal', nameHi: 'पोंगल', month: 'Jan', colorKey: 'pongal' },
  { id: 'durga', name: 'Durga Puja', nameHi: 'दुर्गा पूजा', month: 'Oct', colorKey: 'durga' },
] as const;

// ── App Info ──────────────────────────────────────────────────────
export const APP_NAME = 'KINREL Mirror';
export const APP_DESCRIPTION = 'Enterprise Architecture Sandbox — Deep Feature Mirror of DAXELO KINREL';
export const APP_VERSION = '1.0.0';
export const APP_ORG = 'Daxelo';
