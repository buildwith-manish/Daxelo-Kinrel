/**
 * DAXELO KINREL — Brand Voice & Tone System
 *
 * Defines the brand voice, tone spectrum for different contexts,
 * writing principles, copy inventory, localization notes,
 * and Indian-specific formatting utilities.
 *
 * Pack 12: Brand & Motion — Brand Voice
 */

// ── Voice Definition ───────────────────────────────────────────────
export const VOICE_DEFINITION = 'knowledgeable, warm family elder' as const;

// ── Tone Spectrum ──────────────────────────────────────────────────
export interface ToneSpec {
  context: string;
  tone: string;
  example: string;
}

export const TONE_SPECTRUM: ToneSpec[] = [
  {
    context: 'Onboarding',
    tone: 'Enthusiastic, welcoming, patient — like a host greeting guests',
    example: 'Welcome to your family\'s living archive! Let\'s start with just one name — yours.',
  },
  {
    context: 'Success',
    tone: 'Celebratory, warm, affirming — like a proud parent',
    example: 'Wonderful! Your family tree just grew a new branch. 🌿',
  },
  {
    context: 'Error',
    tone: 'Calm, reassuring, never-blaming — like a patient teacher',
    example: 'We couldn\'t save that right now. No worries — let\'s try again together.',
  },
  {
    context: 'Warning',
    tone: 'Gentle, protective, respectful — like a caring elder',
    example: 'Just a heads-up: this action will affect the whole family tree. Shall we proceed?',
  },
  {
    context: 'Feature',
    tone: 'Excited, discoverable, culturally-rooted',
    example: 'Did you know? Your family speaks 3 languages — KINREL keeps everyone in their own tongue!',
  },
  {
    context: 'EmptyState',
    tone: 'Inviting, patient, hopeful — never guilt-tripping',
    example: 'Every great tree starts with a single seed. Add your first family member!',
  },
  {
    context: 'UpgradePrompt',
    tone: 'Graceful, value-focused, never desperate',
    example: 'Unlock deeper family insights — see relationships across generations with KINREL Premium.',
  },
  {
    context: 'DeceasedMemorial',
    tone: 'Reverent, sacred, gentle — above all commercial concerns',
    example: 'In loving memory. Their story lives on in every branch of this family tree.',
  },
  {
    context: 'Matrimonial',
    tone: 'Respectful, culturally sensitive, community-minded',
    example: 'Find your perfect match within trusted family networks — with blessings from elders.',
  },
];

// ── Writing Principles ─────────────────────────────────────────────
export const WRITING_PRINCIPLES = [
  {
    rule: 'Indian English First',
    description:
      'Use Indian English conventions: "programme" not "program", "favourite" not "favorite", "colour" not "color". Respect Indian punctuation habits (em-dashes, serial commas are optional).',
  },
  {
    rule: 'Respectful Addressing',
    description:
      'Always use respectful forms: "Uncle/Aunty" not first names for elders, "Ji" suffix where culturally appropriate, honorifics in Hindi/other languages. Never assume informality.',
  },
  {
    rule: 'Never-Blame Error Messages',
    description:
      'Errors are never the user\'s fault. Use "we" language: "We couldn\'t find that" not "You entered wrong data". Every error must offer a next step.',
  },
  {
    rule: 'Cultural Sensitivity',
    description:
      'Avoid assumptions about religion, caste, region, or family structure. Use inclusive language. Respect the diversity of Indian family structures — joint families, nuclear, single-parent, chosen families.',
  },
  {
    rule: 'Indian Number Formatting',
    description:
      'Use lakhs and crores, not millions/billions. ₹1,00,000 not ₹100,000. Format currency with ₹ symbol. Use Indian date format (DD/MM/YYYY) unless locale specifies otherwise.',
  },
] as const;

// ── Copy Inventory ─────────────────────────────────────────────────
export const COPY_INVENTORY = {
  login: {
    title: 'Welcome Back to Your Family',
    subtitle: 'Sign in to continue building your living archive',
    emailPlaceholder: 'Enter your email or phone',
    passwordPlaceholder: 'Enter your password',
    primaryAction: 'Sign In',
    secondaryAction: 'Create New Account',
    forgotPassword: 'Forgot password? No worries, we\'ll help you reset it.',
    socialLogin: 'Or continue with',
    errorInvalid: 'We couldn\'t sign you in. Please check your details and try again.',
    errorNetwork: 'We can\'t reach our servers right now. Please check your internet and try again.',
  },
  familyCreation: {
    title: 'Start Your Family Tree',
    subtitle: 'Begin with yourself — every branch grows from here',
    familyNamePlaceholder: 'Your family name (e.g., Sharma Parivaar)',
    yourNamePlaceholder: 'Your full name',
    yourRelationLabel: 'You are the...',
    relationOptions: ['Root (First member)', 'Son/Daughter', 'Spouse', 'Other'],
    primaryAction: 'Create My Family Tree',
    successMessage: 'Your family tree has taken root! 🌱 Start adding members to watch it grow.',
  },
  emptyGraph: {
    title: 'Your Tree Awaits Its First Branch',
    subtitle: 'Add a family member to see your connections come alive',
    addParentCta: 'Add Parent',
    addSpouseCta: 'Add Spouse',
    addChildCta: 'Add Child',
    addSiblingCta: 'Add Sibling',
    tip: 'Tip: You can also add members by tapping the + button on any person\'s card.',
  },
  paywall: {
    title: 'Go Deeper with KINREL Premium',
    subtitle: 'Unlock the full power of your family\'s story',
    features: [
      'Unlimited family members',
      'Photo & story archive',
      'Advanced relationship discovery',
      'Matrimonial matching',
      'Priority WhatsApp support',
      'Ad-free experience',
    ],
    monthlyPrice: '₹299/month',
    yearlyPrice: '₹2,499/year',
    yearlySavings: 'Save ₹1,089',
    cta: 'Start 7-Day Free Trial',
    guarantee: 'Cancel anytime. No questions asked.',
  },
  memorial: {
    title: 'In Loving Memory',
    subtitle: 'Their story lives on in every branch of this family',
    addTribute: 'Add a Tribute',
    tributesLabel: 'Tributes from Family',
    addPhoto: 'Add a Memory Photo',
    shareStory: 'Share a Story About Them',
    condolencesClosed: 'This memorial page is a sacred space. No ads, no promotions.',
  },
} as const;

// ── Localization Notes ─────────────────────────────────────────────
export interface LocalizationNote {
  code: string;
  name: string;
  script: string;
  formalRegister: string;
  respectfulForms: string;
  notes: string;
}

export const LOCALIZATION_NOTES: LocalizationNote[] = [
  { code: 'en', name: 'English', script: 'Latin', formalRegister: 'Use "Please" and "Kindly" in CTAs. Indian English prefers "do the needful" informally but avoid in UI.', respectfulForms: 'Mr./Mrs./Ms. for formal; Uncle/Aunty for elders', notes: 'Default language. Indian English conventions throughout.' },
  { code: 'hi', name: 'Hindi', script: 'Devanagari', formalRegister: 'आप (aap) always, never तू (tu) or तुम (tum). Use जी (ji) suffix for respect.', respectfulForms: 'जी suffix, परिवार (parivaar) for family, माता-पिता (maataa-pitaa)', notes: 'Most widely spoken. Use formal register exclusively.' },
  { code: 'bn', name: 'Bengali', script: 'Bengali', formalRegister: 'আপনি (apni) always. Use বাবু (babu) respectfully for men.', respectfulForms: 'পরিবার (poribar) for family, মা-বাবা (maa-baba)', notes: 'Second most spoken. Rich literary tradition.' },
  { code: 'ta', name: 'Tamil', script: 'Tamil', formalRegister: 'நீங்கள் (neengal) always. Never use நீ (nee).', respectfulForms: 'குடும்பம் (kudumbam) for family, அம்மா-அப்பா (ammaa-appaa)', notes: 'Classical language. Very particular about register.' },
  { code: 'te', name: 'Telugu', script: 'Telugu', formalRegister: 'మీరు (meeru) always. Use గారు (gaaru) suffix for respect.', respectfulForms: 'కుటుంబం (kutumbam) for family, అమ్మ-నాన్న (amma-naanna)', notes: 'Third most spoken. Garu suffix is essential.' },
  { code: 'kn', name: 'Kannada', script: 'Kannada', formalRegister: 'ನೀವು (neevu) always. Use ಅವರು (avaru) for third-person respect.', respectfulForms: 'ಕುಟುಂಬ (kutumba) for family, ಅಮ್ಮ-ಅಪ್ಪ (amma-appa)', notes: 'Classical language status. Formal register required.' },
  { code: 'ml', name: 'Malayalam', script: 'Malayalam', formalRegister: 'നിങ്ങൾ (ningal) for formal. Use ചേട്ടൻ/ചേച്ചി (chettan/chechi) for elders.', respectfulForms: 'കുടുംബം (kudumbam) for family, അമ്മ-അച്ഛൻ (amma-achan)', notes: 'Highly literate population. Expect polished translations.' },
  { code: 'gu', name: 'Gujarati', script: 'Gujarati', formalRegister: 'તમે (tame) always. Use જી (ji) suffix.', respectfulForms: 'પરિવાર (parivaar) for family, માતા-પિતા (maataa-pitaa)', notes: 'Business-oriented community. Clear, concise copy preferred.' },
  { code: 'mr', name: 'Marathi', script: 'Devanagari', formalRegister: 'तुम्ही (tumhi) always. Use आजी/आजोबा (aaji/aajoba) for grandparents.', respectfulForms: 'कुटुंब (kutumb) for family, आई-वडील (aai-vadil)', notes: 'Shares Devanagari script with Hindi. Distinct vocabulary.' },
  { code: 'pa', name: 'Punjabi', script: 'Gurmukhi', formalRegister: 'ਤੁਸੀਂ (tusi) always. Use ਜੀ (ji) suffix. ਭੈਣ ਜੀ (bhen ji) for sister.', respectfulForms: 'ਪਰਿਵਾਰ (parivaar) for family, ਮਾਂ-ਪਿਓ (maa-pio)', notes: 'Warm, expressive language. Emotional resonance matters.' },
  { code: 'or', name: 'Odia', script: 'Odia', formalRegister: 'ଆପଣ (aapana) always. Use ବାବୁ (babu) respectfully.', respectfulForms: 'ପରିବାର (poribara) for family, ମା-ବାପା (maa-baapa)', notes: 'Classical language. Temple culture influences register.' },
  { code: 'ur', name: 'Urdu', script: 'Arabic (RTL)', formalRegister: 'آپ (aap) always. Use صاحب (sahab) and جناب (janab) for respect.', respectfulForms: 'خاندان (khandaan) for family, والدہ-والد (walida-walid)', notes: 'RTL layout required. Nastaliq script for cultural accuracy.' },
  { code: 'as', name: 'Assamese', script: 'Bengali', formalRegister: 'আপুনি (apuni) always. Use বাইদেউ/ককাইদেউ (baideu/kokaideu).', respectfulForms: 'পৰিয়াল (poriyaal) for family, মাক-বাপক (maak-baapok)', notes: 'Similar script to Bengali but distinct language.' },
  { code: 'sa', name: 'Sanskrit', script: 'Devanagari', formalRegister: 'भवन्तः (bhavantaḥ) for plural/formal. त्वम् (tvam) never in UI.', respectfulForms: 'कुटुम्बम् (kutumbam) for family, माता-पिता (maataa-pitaa)', notes: 'Ceremonial and religious contexts only. High cultural prestige.' },
];

// ── Error Rewrites ─────────────────────────────────────────────────
export const ERROR_REWRITES = [
  {
    dont: 'Invalid email address',
    do: 'We couldn\'t recognise that email. Could you check and try again?',
  },
  {
    dont: 'Password must be 8 characters',
    do: 'For your security, please choose a password with at least 8 characters.',
  },
  {
    dont: 'User not found',
    do: 'We couldn\'t find an account with those details. Would you like to create one?',
  },
  {
    dont: 'Permission denied',
    do: 'It looks like you don\'t have access to this yet. Would you like to request it?',
  },
  {
    dont: 'Upload failed',
    do: 'We couldn\'t upload that right now. No worries — please try again in a moment.',
  },
  {
    dont: 'Session expired. Log in again.',
    do: 'For your safety, we\'ve signed you out. Please sign in again to continue.',
  },
] as const;

// ── Relationship Labels ────────────────────────────────────────────
export const RELATIONSHIP_LABELS: Record<string, Record<string, string>> = {
  father: {
    en: 'Father', hi: 'पिता', bn: 'পিতা', ta: 'தந்தை', te: 'తండ్రి',
    kn: 'ತಂದೆ', ml: 'അച്ഛൻ', gu: 'પિતા', mr: 'वडील', pa: 'ਪਿਓ',
    or: 'ପିତା', ur: 'والد', as: 'পিতা', sa: 'पिता',
  },
  mother: {
    en: 'Mother', hi: 'माता', bn: 'মাতা', ta: 'தாய்', te: 'తల్లి',
    kn: 'ತಾಯಿ', ml: 'അമ്മ', gu: 'માતા', mr: 'आई', pa: 'ਮਾਂ',
    or: 'ମାତା', ur: 'والدہ', as: 'মাতা', sa: 'माता',
  },
  grandfather_paternal: {
    en: 'Grandfather (Paternal)', hi: 'दादा', bn: 'দাদু', ta: 'தாத்தா', te: 'తాతయ్య',
    kn: 'ಅಜ್ಜ', ml: 'മുത്തച്ഛൻ', gu: 'દાદા', mr: 'आजोबा', pa: 'ਦਾਦਾ',
    or: 'ଜେଜେ', ur: 'دادا', as: 'দদা', sa: 'पितामह',
  },
  grandmother_paternal: {
    en: 'Grandmother (Paternal)', hi: 'दादी', bn: 'দিদা', ta: 'பாட்டி', te: 'అమ్మమ్మ',
    kn: 'ಅಜ್ಜಿ', ml: 'മുത്തശ്ശി', gu: 'દાદી', mr: 'आजी', pa: 'ਦਾਦੀ',
    or: 'ଜେଜେମା', ur: 'دادی', as: 'দদাই', sa: 'पितामही',
  },
  grandfather_maternal: {
    en: 'Grandfather (Maternal)', hi: 'नाना', bn: 'দাদুমশাই', ta: 'மாமா', te: 'మామయ్య',
    kn: 'ತಾತ', ml: 'അമ്മാവൻ', gu: 'નાના', mr: 'नाना', pa: 'ਨਾਨਾ',
    or: 'ନାନା', ur: 'نانا', as: 'নানা', sa: 'मातामह',
  },
  grandmother_maternal: {
    en: 'Grandmother (Maternal)', hi: 'नानी', bn: 'দিদিমা', ta: 'பாட்டி', te: 'నానమ్మ',
    kn: 'ಅಜ್ಜಿ', ml: 'അമ്മച്ചി', gu: 'નાની', mr: 'नानी', pa: 'ਨਾਨੀ',
    or: 'ନାନୀ', ur: 'نانی', as: 'নানী', sa: 'मातामही',
  },
  husband: {
    en: 'Husband', hi: 'पति', bn: 'স্বামী', ta: 'கணவர்', te: 'భర్త',
    kn: 'ಪತಿ', ml: 'ഭർത്താവ്', gu: 'પતિ', mr: 'पती', pa: 'ਪਤੀ',
    or: 'ସ୍ୱାମୀ', ur: 'شوہر', as: 'স্বামী', sa: 'पति',
  },
  wife: {
    en: 'Wife', hi: 'पत्नी', bn: 'স্ত্রী', ta: 'மனைவி', te: 'భార్య',
    kn: 'ಪತ್ನಿ', ml: 'ഭാര്യ', gu: 'પત્ની', mr: 'पत्नी', pa: 'ਪਤਨੀ',
    or: 'ସ୍ତ୍ରୀ', ur: 'بیوی', as: 'পত্নী', sa: 'पत्नी',
  },
  son: {
    en: 'Son', hi: 'बेटा', bn: 'ছেলে', ta: 'மகன்', te: 'కొడుకు',
    kn: 'ಮಗ', ml: 'മകൻ', gu: 'પુત્ર', mr: 'मुलगा', pa: 'ਪੁੱਤਰ',
    or: 'ପୁଅ', ur: 'بیٹا', as: 'পুত্ৰ', sa: 'पुत्र',
  },
  daughter: {
    en: 'Daughter', hi: 'बेटी', bn: 'মেয়ে', ta: 'மகள்', te: 'కూతురు',
    kn: 'ಮಗಳು', ml: 'മകൾ', gu: 'પુત્રી', mr: 'मुलगी', pa: 'ਧੀ',
    or: 'ଝିଅ', ur: 'بیٹی', as: 'জীয়ৰী', sa: 'पुत्री',
  },
  brother: {
    en: 'Brother', hi: 'भाई', bn: 'ভাই', ta: 'சகோதரன்', te: 'సోదరుడు',
    kn: 'ಸಹೋದರ', ml: 'സഹോദരൻ', gu: 'ભાઈ', mr: 'भाऊ', pa: 'ਭਰਾ',
    or: 'ଭାଇ', ur: 'بھائی', as: 'ভাই', sa: 'भ्राता',
  },
  sister: {
    en: 'Sister', hi: 'बहन', bn: 'বোন', ta: 'சகோதரி', te: 'సోదరి',
    kn: 'ಸಹೋದರಿ', ml: 'സഹോദരി', gu: 'બહેન', mr: 'बहीण', pa: 'ਭੈਣ',
    or: 'ଭଉଣୀ', ur: 'بہن', as: 'ভনী', sa: 'भगिनी',
  },
  uncle_paternal: {
    en: 'Uncle (Paternal)', hi: 'चाचा', bn: 'কাকা', ta: 'சித்தப்பா', te: 'చిన్ననాన్న',
    kn: 'ಚಿಕ್ಕಪ್ಪ', ml: 'ചെറിയച്ഛൻ', gu: 'કાકા', mr: 'चुलत भाऊ', pa: 'ਚਾਚਾ',
    or: 'କାକା', ur: 'چاچا', as: 'ককাই', sa: 'पितृव्य',
  },
  aunt_paternal: {
    en: 'Aunt (Paternal)', hi: 'चाची', bn: 'কাকীমা', ta: 'சித்தி', te: 'చిన్నమ్మ',
    kn: 'ಚಿಕ್ಕಮ್ಮ', ml: 'ചെറിയമ്മ', gu: 'કાકી', mr: 'चुलत भावजय', pa: 'ਚਾਚੀ',
    or: 'କାକୀ', ur: 'چاچی', as: 'ককাইনী', sa: 'पितृव्या',
  },
};

// ── Utility Functions ──────────────────────────────────────────────

export function getTone(context: string): { tone: string; example: string } {
  const spec = TONE_SPECTRUM.find((t) => t.context === context);
  if (spec) return { tone: spec.tone, example: spec.example };
  return {
    tone: 'Warm, helpful, like a knowledgeable family elder',
    example: 'We\'re here to help. Let\'s figure this out together.',
  };
}

export function getErrorCopy(errorType: string): string {
  const rewrite = ERROR_REWRITES.find(
    (r) => r.dont.toLowerCase().replace(/[^a-z0-9]/g, '') === errorType.toLowerCase().replace(/[^a-z0-9]/g, '')
  );
  if (rewrite) return rewrite.do;

  // Generic never-blame fallback
  const genericMessages: Record<string, string> = {
    network: 'We can\'t reach our servers right now. Please check your connection and try again.',
    auth: 'We couldn\'t verify your identity. Please sign in again to continue.',
    validation: 'Something doesn\'t look right with that input. Could you double-check?',
    permission: 'It seems you don\'t have access to this. Would you like to request it?',
    server: 'Our servers are having a moment. Please try again in a bit — we\'re on it.',
    timeout: 'That took longer than expected. Let\'s try again — no data was lost.',
  };
  return genericMessages[errorType] ?? 'Something went wrong on our end. Please try again — we\'re here to help.';
}

export function getRelationshipLabel(relation: string, locale: string = 'en'): string {
  const labels = RELATIONSHIP_LABELS[relation];
  if (!labels) return relation;
  return labels[locale] ?? labels.en ?? relation;
}

export function formatIndianNumber(num: number): string {
  if (num < 0) return '-' + formatIndianNumber(-num);
  if (num < 1000) return num.toString();

  const numStr = num.toString();
  const lastThree = numStr.slice(-3);
  const rest = numStr.slice(0, -3);

  if (rest.length === 0) return lastThree;

  // Insert commas every 2 digits from the right for the "rest" portion
  const formatted = rest.replace(/(\d)(?=(\d{2})+(?!\d))/g, '$1,');
  return formatted + ',' + lastThree;
}

export function formatCurrency(amount: number): string {
  return '₹' + formatIndianNumber(Math.round(amount));
}
