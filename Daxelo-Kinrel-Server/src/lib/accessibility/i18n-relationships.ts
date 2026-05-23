/**
 * DAXELO KINREL — Relationship Name Translations
 *
 * Complete multilingual relationship name system for
 * 14 Indian languages and 46 relationship types.
 * Supports both lookup directions: type→label and label→type.
 *
 * Pack 06: Accessibility — i18n for Indian relationships
 */

// ── Supported Locales ─────────────────────────────────────────────

export interface LocaleInfo {
  /** ISO 639-1 language code */
  code: string;
  /** Human-readable language name */
  name: string;
  /** Writing script name */
  script: string;
  /** Whether this locale uses right-to-left text direction */
  isRTL: boolean;
}

/**
 * All 14 supported Indian locales.
 * Covers all officially recognized languages of India
 * plus English as the bridge language.
 */
export const SUPPORTED_LOCALES: LocaleInfo[] = [
  { code: 'en', name: 'English',    script: 'Latin',       isRTL: false },
  { code: 'hi', name: 'Hindi',      script: 'Devanagari',  isRTL: false },
  { code: 'bn', name: 'Bengali',    script: 'Bengali',     isRTL: false },
  { code: 'te', name: 'Telugu',     script: 'Telugu',      isRTL: false },
  { code: 'mr', name: 'Marathi',    script: 'Devanagari',  isRTL: false },
  { code: 'ta', name: 'Tamil',      script: 'Tamil',       isRTL: false },
  { code: 'gu', name: 'Gujarati',   script: 'Gujarati',    isRTL: false },
  { code: 'kn', name: 'Kannada',    script: 'Kannada',     isRTL: false },
  { code: 'ml', name: 'Malayalam',  script: 'Malayalam',   isRTL: false },
  { code: 'pa', name: 'Punjabi',    script: 'Gurmukhi',    isRTL: false },
  { code: 'or', name: 'Odia',       script: 'Odia',        isRTL: false },
  { code: 'ur', name: 'Urdu',       script: 'Arabic',      isRTL: true  },
  { code: 'as', name: 'Assamese',   script: 'Bengali',     isRTL: false },
  { code: 'sa', name: 'Sanskrit',   script: 'Devanagari',  isRTL: false },
] as const;

// ── Relationship Type Keys ────────────────────────────────────────

/**
 * The 46 relationship type keys used across the application.
 * Covers common, paternal, maternal, in-law, and uniquely Indian terms.
 */
export type RelationshipType =
  | 'father' | 'mother' | 'spouse' | 'son' | 'daughter'
  | 'brother' | 'sister'
  | 'grandfather_paternal' | 'grandmother_paternal'
  | 'grandfather_maternal' | 'grandmother_maternal'
  | 'uncle_paternal' | 'aunt_paternal'
  | 'uncle_maternal' | 'aunt_maternal'
  | 'cousin' | 'nephew' | 'niece'
  | 'father_in_law' | 'mother_in_law'
  | 'brother_in_law' | 'sister_in_law'
  | 'son_in_law' | 'daughter_in_law'
  | 'bua' | 'chacha' | 'chachi' | 'mama' | 'mami'
  | 'tau' | 'tai' | 'devar' | 'devrani'
  | 'jeth' | 'jethani' | 'nanad' | 'sarhaj'
  | 'sala' | 'sali' | 'behnoi' | 'samdhi' | 'samdhan'
  | 'bhatija' | 'bhatiji' | 'pota' | 'poti';

// ── Complete Relationship Name Map ────────────────────────────────

/**
 * 46 relationship types × 14 languages.
 * Each entry is the native script name for that relationship.
 *
 * Key format: relationshipType → localeCode → nativeName
 */
export const RELATIONSHIP_NAMES: Record<string, Record<string, string>> = {
  // ── Core Family ────────────────────────────────────────────
  father: {
    en: 'Father', hi: 'पिता', bn: 'পিতা', te: 'తండ్రి', mr: 'वडील',
    ta: 'தந்தை', gu: 'પિતા', kn: 'ತಂದೆ', ml: 'അച്ഛൻ', pa: 'ਪਿਤਾ',
    or: 'ପିତା', ur: 'والد', as: 'পিতা', sa: 'पितृ',
  },
  mother: {
    en: 'Mother', hi: 'माता', bn: 'মাতা', te: 'తల్లి', mr: 'आई',
    ta: 'தாய்', gu: 'માતા', kn: 'ತಾಯಿ', ml: 'അമ്മ', pa: 'ਮਾਤਾ',
    or: 'ମାତା', ur: 'والدہ', as: 'মাক', sa: 'मातृ',
  },
  spouse: {
    en: 'Spouse', hi: 'पति/पत्नी', bn: 'স্বামী/স্ত্রী', te: 'భర్త/భార్య', mr: 'पती/पत्नी',
    ta: 'கணவன்/மனைவி', gu: 'પતિ/પત્ની', kn: 'ಪತಿ/ಪತ್ನಿ', ml: 'ഭർത്താവ്/ഭാര്യ', pa: 'ਪਤੀ/ਪਤਨੀ',
    or: 'ସ୍ୱାମୀ/ସ୍ତ୍ରୀ', ur: 'شوہر/بیوی', as: 'স্বামী/স্ত্ৰী', sa: 'पति/पत्नी',
  },
  son: {
    en: 'Son', hi: 'बेटा', bn: 'ছেলে', te: 'కొడుకు', mr: 'मुलगा',
    ta: 'மகன்', gu: 'પુત્ર', kn: 'ಮಗ', ml: 'മകൻ', pa: 'ਪੁੱਤਰ',
    or: 'ପୁତ୍ର', ur: 'بیٹا', as: 'পুত্ৰ', sa: 'पुत्र',
  },
  daughter: {
    en: 'Daughter', hi: 'बेटी', bn: 'মেয়ে', te: 'కూతురు', mr: 'मुलगी',
    ta: 'மகள்', gu: 'પુત્રી', kn: 'ಮಗಳು', ml: 'മകൾ', pa: 'ਧੀ',
    or: 'ଝିଅ', ur: 'بیٹی', as: 'জীৱিতা', sa: 'पुत्री',
  },
  brother: {
    en: 'Brother', hi: 'भाई', bn: 'ভাই', te: 'సోదరుడు', mr: 'भाऊ',
    ta: 'சகோதரன்', gu: 'ભાઈ', kn: 'ಸಹೋದರ', ml: 'സഹോദരൻ', pa: 'ਭਰਾ',
    or: 'ଭାଇ', ur: 'بھائی', as: 'ভাই', sa: 'भ्राता',
  },
  sister: {
    en: 'Sister', hi: 'बहन', bn: 'বোন', te: 'సోదరి', mr: 'बहीण',
    ta: 'சகோதரி', gu: 'બહેન', kn: 'ಸಹೋದರಿ', ml: 'സഹോദരി', pa: 'ਭੈਣ',
    or: 'ଭଉଣୀ', ur: 'بہن', as: 'ভনী', sa: 'भगिनी',
  },

  // ── Grandparents ───────────────────────────────────────────
  grandfather_paternal: {
    en: 'Grandfather (Paternal)', hi: 'दादा', bn: 'দাদু', te: 'తాతయ్య', mr: 'आजोबा',
    ta: 'பாட்டன்', gu: 'દાદા', kn: 'ಅಜ್ಜ', ml: 'മുത്തച്ഛൻ', pa: 'ਦਾਦਾ',
    or: 'ଜେଜେ', ur: 'دادا', as: 'দাদা', sa: 'पितामह',
  },
  grandmother_paternal: {
    en: 'Grandmother (Paternal)', hi: 'दादी', bn: 'দিদা', te: 'అమ్మమ్మ', mr: 'आजी',
    ta: 'பாட்டி', gu: 'દાદી', kn: 'ಅಜ್ಜಿ', ml: 'മുത്തശ്ശി', pa: 'ਦਾਦੀ',
    or: 'ଆଇ', ur: 'دادی', as: 'দাদী', sa: 'पितामही',
  },
  grandfather_maternal: {
    en: 'Grandfather (Maternal)', hi: 'नाना', bn: 'দাদু', te: 'మామయ్య', mr: 'आजोबा',
    ta: 'தாத்தா', gu: 'નાના', kn: 'ತಾತ', ml: 'അമ്മൂപ്പൻ', pa: 'ਨਾਨਾ',
    or: 'ନାନା', ur: 'نانا', as: 'নানা', sa: 'मातामह',
  },
  grandmother_maternal: {
    en: 'Grandmother (Maternal)', hi: 'नानी', bn: 'দিদা', te: 'నానమ్మ', mr: 'आजी',
    ta: 'பாட்டி', gu: 'નાની', kn: 'ಅಜ್ಜಿ', ml: 'അമ്മൂമ്മ', pa: 'ਨਾਨੀ',
    or: 'ନାନୀ', ur: 'نانی', as: 'নানী', sa: 'मातामही',
  },

  // ── Paternal Uncles/Aunts ──────────────────────────────────
  uncle_paternal: {
    en: 'Uncle (Paternal)', hi: 'ताऊ', bn: 'জেঠা', te: 'పెద్దబాబాయి', mr: 'काका',
    ta: 'பெரியப்பா', gu: 'કાકા', kn: 'ದೊಡ್ಡಪ್ಪ', ml: 'അച്ഛന്റെ സഹോദരൻ', pa: 'ਤਾਇਆ',
    or: 'ପିତୃବ୍ୟ', ur: 'تایا', as: 'ককাই', sa: 'पितृव्य',
  },
  aunt_paternal: {
    en: 'Aunt (Paternal)', hi: 'ताई', bn: 'জেঠি', te: 'పెద్దబావ', mr: 'काकू',
    ta: 'பெரியம்மா', gu: 'કાકી', kn: 'ದೊಡ್ಡಅಮ್ಮ', ml: 'അച്ഛന്റെ സഹോദരി', pa: 'ਤਾਈ',
    or: 'ପିତୃବ୍ୟୀ', ur: 'تائی', as: 'ককাই', sa: 'पितृव्या',
  },

  // ── Maternal Uncles/Aunts ──────────────────────────────────
  uncle_maternal: {
    en: 'Uncle (Maternal)', hi: 'मामा', bn: 'মামা', te: 'మామయ్య', mr: 'मामा',
    ta: 'மாமா', gu: 'મામા', kn: 'ಮಾವ', ml: 'അമ്മാവൻ', pa: 'ਮਾਮਾ',
    or: 'ମାମୁ', ur: 'ماما', as: 'মামা', sa: 'मातुल',
  },
  aunt_maternal: {
    en: 'Aunt (Maternal)', hi: 'मामी', bn: 'মামী', te: 'మామ్మ', mr: 'मामी',
    ta: 'மாமி', gu: 'મામી', kn: 'ಮಾವಣ್ಣಿ', ml: 'അമ്മായി', pa: 'ਮਾਮੀ',
    or: 'ମାମୀ', ur: 'مامی', as: 'মামী', sa: 'मातुली',
  },

  // ── Extended ───────────────────────────────────────────────
  cousin: {
    en: 'Cousin', hi: 'चचेरा भाई/बहन', bn: 'কাজিন', te: 'కజిన్', mr: 'चुलत भाऊ/बहीण',
    ta: 'உறவினர்', gu: 'કઝિન', kn: 'ಸೋದರ ಸಂಬಂಧಿ', ml: 'അമ്മാവൻ്റെ/പിതൃസഹോദരൻ്റെ മക്കൾ', pa: 'ਕਜ਼ਿਨ',
    or: 'କଜିନ', ur: 'کزن', as: 'কাজিন', sa: 'पितृव्यसुत',
  },
  nephew: {
    en: 'Nephew', hi: 'भतीजा', bn: 'ভাইপো', te: 'మేనల్లుడు', mr: 'भाचा',
    ta: 'மருமகன்', gu: 'ભત્રીજો', kn: 'ಸೋದರ ಮಗ', ml: 'സഹോദരന്റെ മകൻ', pa: 'ਭਤੀਜਾ',
    or: 'ଭାଣଜା', ur: 'بھتیجا', as: 'ভতীজা', sa: 'भ्रातृज',
  },
  niece: {
    en: 'Niece', hi: 'भतीजी', bn: 'ভাইঝি', te: 'మేనకోడలు', mr: 'भाची',
    ta: 'மருமகள்', gu: 'ભત્રીજી', kn: 'ಸೋದರ ಮಗಳು', ml: 'സഹോദരന്റെ മകൾ', pa: 'ਭਤੀਜੀ',
    or: 'ଭାଣଜୀ', ur: 'بھتیجی', as: 'ভতীজী', sa: 'भ्रातृजा',
  },

  // ── In-Laws ────────────────────────────────────────────────
  father_in_law: {
    en: 'Father-in-law', hi: 'ससुर', bn: 'শ্বশুর', te: 'మామయ్య', mr: 'सासरे',
    ta: 'மாமனார்', gu: 'સસરા', kn: 'ಮಾವ', ml: 'അത്താൻ', pa: 'ਸਹੁਰਾ',
    or: 'ଶ୍ୱଶୁର', ur: 'سسر', as: 'শহুৰ', sa: 'श्वशुर',
  },
  mother_in_law: {
    en: 'Mother-in-law', hi: 'सास', bn: 'শাশুড়ি', te: 'అత్తగారు', mr: 'सासू',
    ta: 'மாமியார்', gu: 'સાસુ', kn: 'ಅತ್ತೆ', ml: 'അമ്മായി', pa: 'ਸੱਸ',
    or: 'ଶ୍ୱଶୁରୀ', ur: 'ساس', as: 'শাহুৱা', sa: 'श्वश्रू',
  },
  brother_in_law: {
    en: 'Brother-in-law', hi: 'साला/देवर', bn: 'শালা/দেবর', te: 'బావ/దేవరుడు', mr: 'साला/दिर',
    ta: 'மச்சான்/நண்பன்', gu: 'સાળો/દેવર', kn: 'ಬಾವ/ದೇವರು', ml: 'ചാമൂണ്ഡൻ/ദേവരൻ', pa: 'ਸਾਲਾ/ਦੇਵਰ',
    or: 'ଶାଳା/ଦେବର', ur: 'سالا/دیور', as: 'শালা/দেৱৰ', sa: 'श्याल/देवर',
  },
  sister_in_law: {
    en: 'Sister-in-law', hi: 'साली/ननद', bn: 'শালী/ননদ', te: 'వదిన/నాన్ని', mr: 'साली/नणंद',
    ta: 'நாத்தனார்/அக்கா', gu: 'સાળી/નંદ', kn: 'ಅತ್ತಿಗೆ/ನಂದಿನಿ', ml: 'അത്തിന്റെ സഹോദരി/നന്ദിനി', pa: 'ਸਾਲੀ/ਨਣੰਦ',
    or: 'ଶାଳୀ/ନଣନ୍ଦ', ur: 'سالی/نند', as: 'শালী/ননদ', sa: 'श्याला/ननाम्बा',
  },
  son_in_law: {
    en: 'Son-in-law', hi: 'दामाद', bn: 'জামাই', te: 'అల్లుడు', mr: 'जावई',
    ta: 'மருமகன்', gu: 'જમાઈ', kn: 'ಅಳಿಯ', ml: 'മരുമകൻ', pa: 'ਜੁਆਈ',
    or: 'ଜାମାତା', ur: 'داماد', as: 'জামাই', sa: 'जामातृ',
  },
  daughter_in_law: {
    en: 'Daughter-in-law', hi: 'बहू', bn: 'বউ', te: 'కోడలు', mr: 'सून',
    ta: 'மருமகள்', gu: 'પુત્રવધૂ', kn: 'ಸೊಸೆ', ml: 'മരുമകൾ', pa: 'ਨੂੰਹ',
    or: 'ପୁତ୍ରବଧୂ', ur: 'بہو', as: 'বোৱা', sa: 'पुत्रवधू',
  },

  // ── Uniquely Indian Terms ──────────────────────────────────
  bua: {
    en: "Father's Sister", hi: 'बुआ', bn: 'পিসি', te: 'పిన్ని', mr: 'आत्या',
    ta: 'சித்தி', gu: 'ફોઈ', kn: 'ಅತ್ತೆ/ಚಿಕ್ಕಮ್ಮ', ml: 'അച്ഛന്റെ സഹോദരി', pa: 'ਬੂਆ',
    or: 'ପିସୀ', ur: 'بوا', as: 'পিসি', sa: 'पितृस्वसा',
  },
  chacha: {
    en: "Father's Younger Brother", hi: 'चाचा', bn: 'কাকা', te: 'చిన్నబాబాయి', mr: 'काका',
    ta: 'சித்தப்பா', gu: 'કાકા', kn: 'ಚಿಕ್ಕಪ್ಪ', ml: 'അച്ഛന്റെ ഇളയ സഹോദരൻ', pa: 'ਚਾਚਾ',
    or: 'କାକା', ur: 'چاچا', as: 'ককাই', sa: 'पितृव्य',
  },
  chachi: {
    en: "Father's Younger Brother's Wife", hi: 'चाची', bn: 'কাকীমা', te: 'చిన్నబావ', mr: 'काकू',
    ta: 'சித்தி', gu: 'કાકી', kn: 'ಚಿಕ್ಕಮ್ಮ', ml: 'അച്ഛന്റെ ഇളയ സഹോദരൻ്റെ ഭാര്യ', pa: 'ਚਾਚੀ',
    or: 'କାକୀ', ur: 'چاچی', as: 'ককাই', sa: 'पितृव्या',
  },
  mama: {
    en: "Mother's Brother", hi: 'मामा', bn: 'মামা', te: 'మామయ్య', mr: 'मामा',
    ta: 'மாமா', gu: 'મામા', kn: 'ಮಾವ', ml: 'അമ്മാവൻ', pa: 'ਮਾਮਾ',
    or: 'ମାମୁ', ur: 'ماما', as: 'মামা', sa: 'मातुल',
  },
  mami: {
    en: "Mother's Brother's Wife", hi: 'मामी', bn: 'মামী', te: 'మామ్మ', mr: 'मामी',
    ta: 'மாமி', gu: 'મામી', kn: 'ಮಾವಣ್ಣಿ', ml: 'അമ്മായി', pa: 'ਮਾਮੀ',
    or: 'ମାମୀ', ur: 'مامی', as: 'মামী', sa: 'मातुली',
  },
  tau: {
    en: "Father's Elder Brother", hi: 'ताऊ', bn: 'জেঠা', te: 'పెద్దబాబాయి', mr: 'काका',
    ta: 'பெரியப்பா', gu: 'તાયા', kn: 'ದೊಡ್ಡಪ್ಪ', ml: 'അച്ഛന്റെ മൂത്ത സഹോദരൻ', pa: 'ਤਾਇਆ',
    or: 'ଜେଠା', ur: 'تایا', as: 'বৰককাই', sa: 'ज्येष्ठपितृव्य',
  },
  tai: {
    en: "Father's Elder Brother's Wife", hi: 'ताई', bn: 'জেঠিমা', te: 'పెద్దబావ', mr: 'काकू',
    ta: 'பெரியம்மா', gu: 'તાઈ', kn: 'ದೊಡ್ಡಮ್ಮ', ml: 'അച്ഛന്റെ മൂത്ത സഹോദരൻ്റെ ഭാര്യ', pa: 'ਤਾਈ',
    or: 'ଜେଠୀ', ur: 'تائی', as: 'বৰককাই', sa: 'ज्येष्ठपितृव्या',
  },
  devar: {
    en: "Husband's Younger Brother", hi: 'देवर', bn: 'দেবর', te: 'దేవరుడు', mr: 'दिर',
    ta: 'தம்பி', gu: 'દેવર', kn: 'ದೇವರು', ml: 'ദേവരൻ', pa: 'ਦੇਵਰ',
    or: 'ଦେବର', ur: 'دیور', as: 'দেৱৰ', sa: 'देवृ',
  },
  devrani: {
    en: "Husband's Younger Brother's Wife", hi: 'देवरानी', bn: 'দেবরানী', te: 'దేవరాణి', mr: 'दिराणी',
    ta: 'தம்பியின் மனைவி', gu: 'દેવરાણી', kn: 'ದೇವರುವಿನ ಹೆಂಡತಿ', ml: 'ദേവരൻ്റെ ഭാര്യ', pa: 'ਦੇਵਰਾਣੀ',
    or: 'ଦେବରାଣୀ', ur: 'دیورانی', as: 'দেৱৰানী', sa: 'देवराणी',
  },
  jeth: {
    en: "Husband's Elder Brother", hi: 'जेठ', bn: 'জেঠ', te: 'బావగారు', mr: 'जेठ',
    ta: 'அண்ணன்', gu: 'જેઠ', kn: 'ಬಾವ', ml: 'അത്താൻ', pa: 'ਜੇਠ',
    or: 'ଜେଠ', ur: 'جیٹھ', as: 'জেঠ', sa: 'ज्येष्ठदेवृ',
  },
  jethani: {
    en: "Husband's Elder Brother's Wife", hi: 'जेठानी', bn: 'জেঠিমণি', te: 'బావమరాలు', mr: 'जेठाणी',
    ta: 'அண்ணியார்', gu: 'જેઠાણી', kn: 'ಬಾವನ ಹೆಂಡತಿ', ml: 'അത്തിൻ്റെ ഭാര്യ', pa: 'ਜੇਠਾਣੀ',
    or: 'ଜେଠାଣୀ', ur: 'جیٹھانی', as: 'জেঠানী', sa: 'ज्येष्ठदेव्राणी',
  },
  nanad: {
    en: "Husband's Sister", hi: 'ननद', bn: 'ননদ', te: 'నాన్ని', mr: 'नणंद',
    ta: 'நன்னா', gu: 'નણંદ', kn: 'ನಂದಿನಿ', ml: 'നന്ദിനി', pa: 'ਨਣੰਦ',
    or: 'ନଣନ୍ଦ', ur: 'نند', as: 'ননদ', sa: 'ननाम्बा',
  },
  sarhaj: {
    en: "Husband's Elder Brother's Wife (Punjabi)", hi: 'साढ़ू', bn: 'জেঠিমণি', te: 'బావమరాలు', mr: 'जेठाणी',
    ta: 'அண்ணியார்', gu: 'સાઢું', kn: 'ಬಾವನ ಹೆಂಡತಿ', ml: 'അത്തിൻ്റെ ഭാര്യ', pa: 'ਸਰਹਜ',
    or: 'ଜେଠାଣୀ', ur: 'سڑھو', as: 'জেঠানী', sa: 'ज्येष्ठवधू',
  },
  sala: {
    en: "Wife's Brother", hi: 'साला', bn: 'শালা', te: 'బావమరాలి', mr: 'साला',
    ta: 'மச்சான்', gu: 'સાળો', kn: 'ಬಾವ', ml: 'ഭാര്യയുടെ സഹോദരൻ', pa: 'ਸਾਲਾ',
    or: 'ଶାଳା', ur: 'سالا', as: 'শালা', sa: 'श्यालक',
  },
  sali: {
    en: "Wife's Sister", hi: 'साली', bn: 'শালী', te: 'వదిన', mr: 'साली',
    ta: 'மச்சினான்', gu: 'સાળી', kn: 'ನಂದಿನಿ', ml: 'ഭാര്യയുടെ സഹോദരി', pa: 'ਸਾਲੀ',
    or: 'ଶାଳୀ', ur: 'سالی', as: 'শালী', sa: 'श्याला',
  },
  behnoi: {
    en: "Sister's Husband", hi: 'बहनोई', bn: 'বোনের স্বামী', te: 'బావ', mr: 'बहिणोई',
    ta: 'மைதுனன்', gu: 'બહેનોઈ', kn: 'ಬಾವ', ml: 'സഹോദരിയുടെ ഭർത്താവ്', pa: 'ਬਹਿਣੋਈ',
    or: 'ଭାଉଜ', ur: 'بہنوئی', as: 'ভনই', sa: 'भगिनीपति',
  },
  samdhi: {
    en: "Child's Father-in-law", hi: 'समधी', bn: 'সমধি', te: 'సంబంధి', mr: 'समधी',
    ta: 'சமதி', gu: 'સમધી', kn: 'ಸಂಬಂಧಿ', ml: 'മകന്റെ/മകളുടെ അത്താൻ', pa: 'ਸਮਧੀ',
    or: 'ସମଧୀ', ur: 'سمدھی', as: 'সমধী', sa: 'समधि',
  },
  samdhan: {
    en: "Child's Mother-in-law", hi: 'समधन', bn: 'সমধিন', te: 'సంబంధిత', mr: 'समधन',
    ta: 'சமதினி', gu: 'સમધન', kn: 'ಸಂಬಂಧಿನಿ', ml: 'മകന്റെ/മകളുടെ അമ്മായി', pa: 'ਸਮਧਨ',
    or: 'ସମଧୀଣୀ', ur: 'سمدھن', as: 'সমধীন', sa: 'समध्नी',
  },
  bhatija: {
    en: "Brother's Son (Nephew)", hi: 'भतीजा', bn: 'ভাইপো', te: 'మేనల్లుడు', mr: 'भाचा',
    ta: 'சகோதரன் மகன்', gu: 'ભત્રીજો', kn: 'ಸೋದರ ಮಗ', ml: 'സഹോദരന്റെ മകൻ', pa: 'ਭਤੀਜਾ',
    or: 'ଭାଣଜା', ur: 'بھتیجا', as: 'ভতীজা', sa: 'भ्रातृज',
  },
  bhatiji: {
    en: "Brother's Daughter (Niece)", hi: 'भतीजी', bn: 'ভাইঝি', te: 'మేనకోడలు', mr: 'भाची',
    ta: 'சகோதரன் மகள்', gu: 'ભત્રીજી', kn: 'ಸೋದರ ಮಗಳು', ml: 'സഹോദരന്റെ മകൾ', pa: 'ਭਤੀਜੀ',
    or: 'ଭାଣଜୀ', ur: 'بھتیجی', as: 'ভতীজী', sa: 'भ्रातृजा',
  },
  pota: {
    en: "Grandson (through son)", hi: 'पोता', bn: 'নাতি', te: 'మనుమడు', mr: 'नातू',
    ta: 'பேரப்பிள்ளை', gu: 'પૌત્ર', kn: 'ಮೊಮ್ಮಗ', ml: 'മകന്റെ മകൻ', pa: 'ਪੋਤਾ',
    or: 'ନାତି', ur: 'پوتا', as: 'নাতি', sa: 'पौत्र',
  },
  poti: {
    en: "Granddaughter (through son)", hi: 'पोती', bn: 'নাতনি', te: 'మనుమరాలు', mr: 'नातिन',
    ta: 'பேரப்பிள்ளை', gu: 'પૌત્રી', kn: 'ಮೊಮ್ಮಳು', ml: 'മകന്റെ മകൾ', pa: 'ਪੋਤੀ',
    or: 'ନାତୁଣୀ', ur: 'پوتی', as: 'নাতিনী', sa: 'पौत्री',
  },
} as const;

// ── Lookup Functions ───────────────────────────────────────────────

/**
 * Get the localized label for a relationship type.
 * Falls back to English if the locale is not found,
 * and to the raw relationship key if neither exist.
 *
 * @param type - Relationship type key (e.g., 'bua', 'father')
 * @param locale - Locale code (e.g., 'hi', 'ta')
 * @returns Localized relationship label
 *
 * @example
 * getRelationshipLabel('bua', 'hi')   // 'बुआ'
 * getRelationshipLabel('bua', 'ta')   // 'சித்தி'
 * getRelationshipLabel('bua', 'xx')   // "Father's Sister" (falls back to en)
 */
export function getRelationshipLabel(type: string, locale: string): string {
  const names = RELATIONSHIP_NAMES[type];
  if (!names) return type;

  // Try exact locale
  if (names[locale]) return names[locale];

  // Fallback to English
  if (names['en']) return names['en'];

  // Fallback to first available translation
  const firstKey = Object.keys(names)[0];
  return firstKey ? names[firstKey] : type;
}

/**
 * Reverse lookup: find the relationship type from a localized label.
 * Useful for parsing user input in the user's language.
 *
 * @param label - The relationship label in the given locale
 * @param locale - The locale of the label
 * @returns The relationship type key, or null if not found
 *
 * @example
 * getRelationshipTypeFromLabel('बुआ', 'hi')    // 'bua'
 * getRelationshipTypeFromLabel('தந்தை', 'ta')   // 'father'
 * getRelationshipTypeFromLabel('Unknown', 'hi')  // null
 */
export function getRelationshipTypeFromLabel(
  label: string,
  locale: string
): string | null {
  for (const [type, names] of Object.entries(RELATIONSHIP_NAMES)) {
    if (names[locale] === label) {
      return type;
    }
  }
  return null;
}
