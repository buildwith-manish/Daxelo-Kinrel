// server/src/addictiveness/festival-data.ts
//
// A-6 Festival Intelligence — Indian festival dataset (8 languages).
//
// This file is PURE DATA — no NestJS dependencies, no side effects.
// It can be imported by the seed script, the FestivalService, and tests.
//
// Structure:
//   Each festival has:
//     - festivalKey: stable identifier (e.g., 'diwali')
//     - dateType: 'fixed' (same Gregorian date every year) or 'lunar' (pre-computed)
//     - region: where it's primarily celebrated
//     - names: 8-language name map
//     - greetings: 8-language greeting map
//     - description: English description
//     - themes: cultural themes for AI personalization
//     - rituals: common rituals (for the brief body text)
//
// For lunar festivals, the `dates` field contains pre-computed Gregorian dates
// for the next 3 years. The seed script inserts the NEXT upcoming occurrence.
// A monthly cron updates the dates as time passes.
//
// Languages covered: en, hi, ta, te, kn, mr, gu, bn
//

export interface FestivalSeed {
  festivalKey: string;
  dateType: 'fixed' | 'lunar';
  region: 'north' | 'south' | 'east' | 'west' | 'all';
  // For 'fixed' festivals: month (1-12) + day (1-31)
  // For 'lunar' festivals: pre-computed Gregorian dates for next 3 years (YYYY-MM-DD)
  fixedMonth?: number;
  fixedDay?: number;
  lunarDates?: string[]; // ['2026-11-08', '2027-10-28', '2028-11-17']
  names: Record<string, string>; // 8-language names
  greetings: Record<string, string>; // 8-language greetings
  description: string;
  themes: string[];
  rituals: string[];
}

// ─────────────────────────────────────────────────────────────────────────────
// Festival dataset
// ─────────────────────────────────────────────────────────────────────────────
//
// Note on lunar dates: these are approximate Gregorian dates for the next 3
// years (2026-2028). In production, these should be updated annually by a
// script that consults an authoritative Hindu panchangam. For now, these
// approximate dates are good enough for the MVP.
//

export const FESTIVAL_SEEDS: FestivalSeed[] = [
  // ── Major pan-Indian festivals ──────────────────────────────────────────
  {
    festivalKey: 'diwali',
    dateType: 'lunar',
    region: 'all',
    lunarDates: ['2026-11-08', '2027-10-28', '2028-11-17'],
    names: {
      en: 'Diwali',
      hi: 'दीपावली',
      ta: 'தீபாவளி',
      te: 'దీపావళి',
      kn: 'ದೀಪಾವಳಿ',
      mr: 'दिवाळी',
      gu: 'દિવાળી',
      bn: 'দীপাবলি',
    },
    greetings: {
      en: 'May the festival of lights bring joy to your family. शुभ दीपावली!',
      hi: 'दीपों के त्योहार पर आपके परिवार को ढेरों खुशियाँ मिलें। शुभ दीपावली!',
      ta: 'தீபாவளி நன்னாள் உங்கள் குடும்பத்திற்கு மகிழ்ச்சி தரட்டும்!',
      te: 'దీపావళి శుభాకాంక్షలు! మీ కుటుంబానికి ఆనందం తెస్తుంది.',
      kn: 'ದೀಪಾವಳಿಯ ಶುಭಾಶಯಗಳು! ನಿಮ್ಮ ಕುಟುಂಬಕ್ಕೆ ಸಂತೋಷ ತರಲಿ.',
      mr: 'दिवाळीच्या शुभेच्छा! तुमच्या कुटुंबाला आनंद मिळो.',
      gu: 'દિવાળીની શુભેચ્છાઓ! તમારા પરિવારને આનંદ મળો.',
      bn: 'দীপাবলির শুভেচ্ছা! আপনার পরিবারে আনন্দ আসুক।',
    },
    description: 'The festival of lights, celebrating the victory of light over darkness and good over evil.',
    themes: ['lights', 'victory', 'renewal', 'family'],
    rituals: ['rangoli', 'diya_lighting', 'lakshmi_puja', 'sweets', 'fireworks'],
  },
  {
    festivalKey: 'holi',
    dateType: 'lunar',
    region: 'all',
    lunarDates: ['2026-03-04', '2027-03-22', '2028-03-11'],
    names: {
      en: 'Holi',
      hi: 'होली',
      ta: 'ஹோலி',
      te: 'హోళి',
      kn: 'ಹೋಳಿ',
      mr: 'होळी',
      gu: 'હોળી',
      bn: 'হোলি',
    },
    greetings: {
      en: 'May the colors of Holi fill your family with joy. Happy Holi!',
      hi: 'होली के रंग आपके परिवार को खुशियों से भर दें। होली हार्दिक शुभकामनाएँ!',
      ta: 'ஹோலி வண்ணங்கள் உங்கள் குடும்பத்தை மகிழ்ச்சியால் நிரப்க!',
      te: 'హోళి రంగులు మీ కుటుంబాన్ని ఆనందంతో నింపుతాయి!',
      kn: 'ಹೋಳಿಯ ಬಣ್ಣಗಳು ನಿಮ್ಮ ಕುಟುಂಬವನ್ನು ಸಂತೋಷದಿಂದ ತುಂಬಲಿ!',
      mr: 'होळीच्या रंगांनी तुमचे कुटुंब आनंदाने भरो!',
      gu: 'હોળીના રંગો તમારા પરિવારને આનંદથી ભરી દો!',
      bn: 'হোলির রঙে আপনার পরিবার আনন্দে ভরে যাক!',
    },
    description: 'The festival of colors, celebrating the arrival of spring and the triumph of devotion.',
    themes: ['colors', 'spring', 'joy', 'forgiveness'],
    rituals: ['color_play', 'bonfire', 'gujiya', 'dance'],
  },
  {
    festivalKey: 'raksha_bandhan',
    dateType: 'lunar',
    region: 'north',
    lunarDates: ['2026-08-19', '2027-08-08', '2028-08-27'],
    names: {
      en: 'Raksha Bandhan',
      hi: 'रक्षा बंधन',
      ta: 'ரக்ஷா பந்தன்',
      te: 'రక్షా బంధన్',
      kn: 'ರಕ್ಷಾ ಬಂಧನ',
      mr: 'राखी पौर्णिमा',
      gu: 'રક્ષા બંધન',
      bn: 'রক্ষা বন্ধন',
    },
    greetings: {
      en: 'Celebrating the bond between brothers and sisters. Happy Raksha Bandhan!',
      hi: 'भाई-बहन के पवित्र बंधन की शुभकामनाएँ। रक्षा बंधन की हार्दिक शुभकामनाएँ!',
      ta: 'சகோதர சகோதரி பிணைப்பை கொண்டாடும் நன்னாள்!',
      te: 'అన్నా చెల్లెలు బంధాన్ని జరుపుకుందాం!',
      kn: 'ಸಹೋದರ ಸಹೋದರಿಯರ ಬಂಧವನ್ನು ಆಚರಿಸೋಣ!',
      mr: 'भाऊ-बहिणीच्या पवित्र बंधनाच्या शुभेच्छा!',
      gu: 'ભાઈ-બહેનના પવિત્ર બંધનની શુભેચ્છાઓ!',
      bn: 'ভাই-বোনের পবিত্র বন্ধনের শুভেচ্ছা!',
    },
    description: 'Celebrating the sacred bond between brothers and sisters.',
    themes: ['sibling_bond', 'protection', 'love'],
    rituals: ['rakhi_tying', 'gift_exchange', 'sweets'],
  },
  {
    festivalKey: 'ganesh_chaturthi',
    dateType: 'lunar',
    region: 'west',
    lunarDates: ['2026-09-04', '2027-08-25', '2028-09-13'],
    names: {
      en: 'Ganesh Chaturthi',
      hi: 'गणेश चतुर्थी',
      ta: 'விநாயகர் சதுர்த்தி',
      te: 'వినాయక చవితి',
      kn: 'ಗಣೇಶ ಚತುರ್ಥಿ',
      mr: 'गणेश चतुर्थी',
      gu: 'ગણેશ ચતુર્થી',
      bn: 'গণেশ চতুর্থী',
    },
    greetings: {
      en: 'May Lord Ganesha remove all obstacles. Ganpati Bappa Morya!',
      hi: 'भगवान गणेश सभी बाधाओं को दूर करें। गणपति बप्पा मोरया!',
      ta: 'விநாயகர் அனைத்து தடைகளையும் நீக்கட்டும்!',
      te: 'వినాయకుడు అన్ని ఆటంకాలను తొలగించుగాక!',
      kn: 'ಗಣೇಶನು ಎಲ್ಲಾ ಅಡ್ಡಿಗಳನ್ನು ತೆಗೆದುಹಾಕಲಿ!',
      mr: 'गणपती बाप्पा सर्व अडथळे दूर करोत!',
      gu: 'ગણપતિ બાપ્પા બધી અડચણો દૂર કરો!',
      bn: 'গণেশ সব বাধা দূর করুক!',
    },
    description: 'Celebrating the birth of Lord Ganesha, the remover of obstacles.',
    themes: ['new_beginnings', 'obstacle_removal', 'devotion'],
    rituals: ['ganesh_idol', 'puja', 'modak', 'visarjan'],
  },
  {
    festivalKey: 'navratri',
    dateType: 'lunar',
    region: 'all',
    lunarDates: ['2026-10-11', '2027-09-30', '2028-10-19'],
    names: {
      en: 'Navratri',
      hi: 'नवरात्रि',
      ta: 'நவராத்திரி',
      te: 'నవరాత్రి',
      kn: 'ನವರಾತ್ರಿ',
      mr: 'नवरात्र',
      gu: 'નવરાત્રિ',
      bn: 'নবরাত্রি',
    },
    greetings: {
      en: 'Nine nights of devotion and dance. Happy Navratri!',
      hi: 'नौ रातों का भक्ति और नृत्य का त्योहार। नवरात्रि की शुभकामनाएँ!',
      ta: 'ஒன்பது இரவுகளின் பக்தி மற்றும் நடனம்!',
      te: 'తొమ్మిది రాత్రుల భక్తి, నాట్యం!',
      kn: 'ಒಂಬತ್ತು ರಾತ್ರಿಗಳ ಭಕ್ತಿ ಮತ್ತು ನೃತ್ಯ!',
      mr: 'नऊ रात्रींची भक्ती आणि नृत्य!',
      gu: 'નવ રાત્રિની ભક્તિ અને નૃત્ય!',
      bn: 'নয় রাতের ভক্তি ও নৃত্য!',
    },
    description: 'Nine nights celebrating the divine feminine, with garba and dandiya dances.',
    themes: ['divine_feminine', 'dance', 'devotion', 'fasting'],
    rituals: ['garba', 'dandiya', 'fasting', 'puja'],
  },
  {
    festivalKey: 'dussehra',
    dateType: 'lunar',
    region: 'all',
    lunarDates: ['2026-10-19', '2027-10-08', '2028-10-27'],
    names: {
      en: 'Dussehra',
      hi: 'दशहरा',
      ta: 'தசரா',
      te: 'దసరా',
      kn: 'ದಸರಾ',
      mr: 'दसरा',
      gu: 'દસેરા',
      bn: 'দশেরা',
    },
    greetings: {
      en: 'Celebrating the victory of good over evil. Happy Dussehra!',
      hi: 'अच्छाई की बुराई पर जीत का उत्सव। दशहरा की हार्दिक शुभकामनाएँ!',
      ta: 'நன்மையின் தீமையின் மீதான வெற்றியை கொண்டாடுவோம்!',
      te: 'మంచికి చెడుపై విజయాన్ని జరుపుకుందాం!',
      kn: 'ಒಳ್ಳೆಯದರ ಕೆಟ್ಟದ್ದರ ಮೇಲೆ ವಿಜಯವನ್ನು ಆಚರಿಸೋಣ!',
      mr: 'चांगल्याचा वाईटावर विजयाचा सण!',
      gu: 'સારાની ખરાબ પર વિજયનો ઉત્સવ!',
      bn: 'ভালোর খারাপের উপর বিজয়ের উৎসব!',
    },
    description: 'Celebrating the victory of Lord Rama over Ravana — good over evil.',
    themes: ['victory', 'good_over_evil', 'courage'],
    rituals: ['rama_lyla', 'ravana_burn', 'puja'],
  },
  {
    festivalKey: 'eid_al_fitr',
    dateType: 'lunar',
    region: 'all',
    lunarDates: ['2026-03-20', '2027-03-10', '2028-02-27'],
    names: {
      en: 'Eid al-Fitr',
      hi: 'ईद उल-फित्र',
      ta: 'ஈத் உல்-ஃபித்ர்',
      te: 'ఈద్ ఉల్-ఫితర్',
      kn: 'ಈದ್ ಉಲ್-ಫಿತರ್',
      mr: 'ईद उल-फित्र',
      gu: 'ઈદ ઉલ-ફિતર',
      bn: 'ঈদ উল-ফিতর',
    },
    greetings: {
      en: 'Eid Mubarak! May this blessed day bring peace to your family.',
      hi: 'ईद मुबारक! यह पवित्र दिन आपके परिवार को शांति लाए।',
      ta: 'ஈத் முபாரக்! இந்த பாக்கியமான நாள் உங்கள் குடும்பத்திற்கு அமைதி தரட்டும்.',
      te: 'ఈద్ ముబారక్! ఈ దినం మీ కుటుంబానికి శాంతి తెస్తుంది.',
      kn: 'ಈದ್ ಮುಬಾರಕ್! ಈ ಪವಿತ್ರ ದಿನ ನಿಮ್ಮ ಕುಟುಂಬಕ್ಕೆ ಶಾಂತಿ ತರಲಿ.',
      mr: 'ईद मुबारक! हा पवित्र दिवस तुमच्या कुटुंबाला शांती देवो.',
      gu: 'ઈદ મુબારક! આ પવિત્ર દિવસ તમારા પરિવારને શાંતિ આપો.',
      bn: 'ঈদ মুবারক! এই পবিত্র দিন আপনার পরিবারে শান্তি আনুক।',
    },
    description: 'The festival of breaking the fast, marking the end of Ramadan.',
    themes: ['community', 'charity', 'gratitude', 'feast'],
    rituals: ['eid_prayer', 'feast', 'charity', 'new_clothes'],
  },
  {
    festivalKey: 'christmas',
    dateType: 'fixed',
    region: 'all',
    fixedMonth: 12,
    fixedDay: 25,
    names: {
      en: 'Christmas',
      hi: 'क्रिसमस',
      ta: 'கிறிஸ்துமஸ்',
      te: 'క్రిస్మస్',
      kn: 'ಕ್ರಿಸ್ಮಸ್',
      mr: 'ख्रिस्तमस',
      gu: 'ક્રિસમસ',
      bn: 'বড়দিন',
    },
    greetings: {
      en: 'Merry Christmas! Wishing your family joy and peace.',
      hi: 'मेरी क्रिसमस! आपके परिवार को खुशी और शांति की कामना।',
      ta: 'கிறிஸ்துமஸ் நன்னாள்! உங்கள் குடும்பத்திற்கு மகிழ்ச்சியும் அமைதியும்.',
      te: 'క్రిస్మస్ శుభాకాంక్షలు! మీ కుటుంబానికి ఆనందం, శాంతి.',
      kn: 'ಕ್ರಿಸ್ಮಸ್ ಶುಭಾಶಯಗಳು! ನಿಮ್ಮ ಕುಟುಂಬಕ್ಕೆ ಸಂತೋಷ, ಶಾಂತಿ.',
      mr: 'मेरी क्रिस्मस! तुमच्या कुटुंबाला आनंद आणि शांती.',
      gu: 'મેરી ક્રિસમસ! તમારા પરિવારને આનંદ અને શાંતિ.',
      bn: 'বড়দিনের শুভেচ্ছা! আপনার পরিবারে আনন্দ ও শান্তি।',
    },
    description: 'Celebrating the birth of Jesus Christ, with family gatherings and gift-giving.',
    themes: ['family', 'giving', 'love', 'peace'],
    rituals: ['christmas_tree', 'gifts', 'feast', 'carols'],
  },
  {
    festivalKey: 'pongal',
    dateType: 'fixed',
    region: 'south',
    fixedMonth: 1,
    fixedDay: 14,
    names: {
      en: 'Pongal',
      hi: 'पोंगल',
      ta: 'பொங்கல்',
      te: 'పొంగల్',
      kn: 'ಸಂಕ್ರಾಂತಿ',
      mr: 'पोंगल',
      gu: 'ઉત્તરાયણ',
      bn: 'পোঙ্গল',
    },
    greetings: {
      en: 'Happy Pongal! May the harvest bring prosperity to your family.',
      hi: 'पोंगल की हार्दिक शुभकामनाएँ! फसल आपके परिवार को समृद्धि लाए।',
      ta: 'பொங்கல் நல்லாள்! அறுவடை உங்கள் குடும்பத்திற்கு வளம் தரட்டும்.',
      te: 'పొంగలి శుభాకాంక్షలు! పంట మీ కుటుంబానికి సంపద తెస్తుంది.',
      kn: 'ಸಂಕ್ರಾಂತಿ ಶುಭಾಶಯಗಳು! ಬೆಳೆ ನಿಮ್ಮ ಕುಟುಂಬಕ್ಕೆ ಸಮೃದ್ಧಿ ತರಲಿ.',
      mr: 'पोंगलच्या शुभेच्छा! पीक तुमच्या कुटुंबाला समृद्धी आणो.',
      gu: 'ઉત્તરાયણની શુભેચ્છાઓ! પાક તમારા પરિવારને સમૃદ્ધિ લાવો.',
      bn: 'পোঙ্গলের শুভেচ্ছা! ফসল আপনার পরিবারে সমৃদ্ধি আনুক।',
    },
    description: 'Tamil harvest festival thanking the Sun God and nature for a bountiful harvest.',
    themes: ['harvest', 'gratitude', 'sun', 'nature'],
    rituals: ['pongal_cooking', 'rangoli', 'cattle_worship', 'sugarcane'],
  },
  {
    festivalKey: 'onam',
    dateType: 'lunar',
    region: 'south',
    lunarDates: ['2026-09-05', '2027-08-26', '2028-09-14'],
    names: {
      en: 'Onam',
      hi: 'ओणम',
      ta: 'ஓணம்',
      te: 'ఓణం',
      kn: 'ಓಣಂ',
      mr: 'ओणम',
      gu: 'ઓણમ',
      bn: 'ওণম',
    },
    greetings: {
      en: 'Happy Onam! May King Mahabali bless your family.',
      hi: 'ओणम की शुभकामनाएँ! राजा महाबली आपके परिवार को आशीर्वाद दें।',
      ta: 'ஓணம் நன்னாள்! மகாபலி உங்கள் குடும்பத்தை ஆசீர்வதிக்கட்டும்.',
      te: 'ఓణం శుభాకాంక్షలు! మహాబలి మీ కుటుంబాన్ని ఆశీర్వదించుగాక.',
      kn: 'ಓಣಂ ಶುಭಾಶಯಗಳು! ಮಹಾಬಲಿ ನಿಮ್ಮ ಕುಟುಂಬವನ್ನು ಆಶೀರ್ವದಿಸಲಿ.',
      mr: 'ओणमच्या शुभेच्छा! राजा महाबली तुमच्या कुटुंबाला आशीर्वाद देवो.',
      gu: 'ઓણમની શુભેચ્છાઓ! રાજા મહાબલિ તમારા પરિવારને આશીર્વાદ આપો.',
      bn: 'ওণমের শুভেচ্ছা! রাজা মহাবলী আপনার পরিবারকে আশীর্বাদ করুক।',
    },
    description: 'Kerala harvest festival welcoming the legendary King Mahabali.',
    themes: ['harvest', 'kerala', 'returning_king', 'feast'],
    rituals: ['onam_sadya', 'flower_carpet', 'boat_race', 'dance'],
  },
  {
    festivalKey: 'janmashtami',
    dateType: 'lunar',
    region: 'north',
    lunarDates: ['2026-09-04', '2027-08-25', '2028-09-13'],
    names: {
      en: 'Janmashtami',
      hi: 'जन्माष्टमी',
      ta: 'கிருஷ்ண ஜெயந்தி',
      te: 'జన్మాష్టమి',
      kn: 'ಶ್ರೀ ಕೃಷ್ಣ ಜನ್ಮಾಷ್ಟಮಿ',
      mr: 'गोकुळ अष्टमी',
      gu: 'જન્માષ્ટમી',
      bn: 'জন্মাষ্টমী',
    },
    greetings: {
      en: 'Jai Shri Krishna! May Lord Krishna bless your family.',
      hi: 'जय श्री कृष्णा! भगवान कृष्णा आपके परिवार का भला करें।',
      ta: 'கிருஷ்ணா தரிசனம்! அவர் உங்கள் குடும்பத்தை ஆசீர்வதிக்கட்டும்.',
      te: 'జయ శ్రీ కృష్ణా! కృష్ణుడు మీ కుటుంబాన్ని ఆశీర్వదించుగాక.',
      kn: 'ಜಯ ಶ್ರೀ ಕೃಷ್ಣ! ಕೃಷ್ಣನು ನಿಮ್ಮ ಕುಟುಂಬವನ್ನು ಆಶೀರ್ವದಿಸಲಿ.',
      mr: 'जय श्री कृष्णा! तुमच्या कुटुंबाला त्यांचा आशीर्वाद लाभो.',
      gu: 'જય શ્રી કૃષ્ણ! કૃષ્ણ તમારા પરિવારને આશીર્વાદ આપો.',
      bn: 'জয় শ্রী কৃষ্ণ! কৃষ্ণ আপনার পরিবারকে আশীর্বাদ করুক।',
    },
    description: 'Celebrating the birth of Lord Krishna, with dahi-handi and midnight celebrations.',
    themes: ['birth', 'playfulness', 'devotion', 'childhood'],
    rituals: ['dahi_handi', 'midnight_puja', 'bhajan', 'fast'],
  },

  // ── National holidays (not religious, but culturally important) ──────────
  {
    festivalKey: 'republic_day',
    dateType: 'fixed',
    region: 'all',
    fixedMonth: 1,
    fixedDay: 26,
    names: {
      en: 'Republic Day',
      hi: 'गणतंत्र दिवस',
      ta: 'குடியரசு தினம்',
      te: 'గణతంత్ర దినోత్సవం',
      kn: 'ಗಣರಾಜ್ಯೋತ್ಸವ',
      mr: 'गणतंत्र दिवस',
      gu: 'ગણતંત્ર દિવસ',
      bn: 'প্রজাতন্ত্র দিবস',
    },
    greetings: {
      en: 'Happy Republic Day! Proud to be Indian.',
      hi: 'गणतंत्र दिवस की शुभकामनाएँ! भारत माता की जय।',
      ta: 'குடியரசு தின வாழ்த்துக்கள்!',
      te: 'గణతంత్ర దినోత్సవ శుభాకాంక్షలు!',
      kn: 'ಗಣರಾಜ್ಯೋತ್ಸವದ ಶುಭಾಶಯಗಳು!',
      mr: 'गणतंत्र दिवसाच्या शुभेच्छा!',
      gu: 'ગણતંત્ર દિવસની શુભેચ્છાઓ!',
      bn: 'প্রজাতন্ত্র দিবসের শুভেচ্ছা!',
    },
    description: 'Celebrating the adoption of the Constitution of India in 1950.',
    themes: ['nation', 'constitution', 'pride', 'democracy'],
    rituals: ['flag_hoisting', 'parade', 'patriotic_songs'],
  },
  {
    festivalKey: 'independence_day',
    dateType: 'fixed',
    region: 'all',
    fixedMonth: 8,
    fixedDay: 15,
    names: {
      en: 'Independence Day',
      hi: 'स्वतंत्रता दिवस',
      ta: 'சுதந்திர தினம்',
      te: 'స్వాతంత్ర్య దినోత్సవం',
      kn: 'ಸ್ವಾತಂತ್ರ್ಯ ದಿನಾಚರಣೆ',
      mr: 'स्वातंत्र्य दिन',
      gu: 'સ્વતંત્રતા દિવસ',
      bn: 'স্বাধীনতা দিবস',
    },
    greetings: {
      en: 'Happy Independence Day! Jai Hind!',
      hi: 'स्वतंत्रता दिवस की शुभकामनाएँ! जय हिन्द!',
      ta: 'சுதந்திர தின வாழ்த்துக்கள்! ஜெய் ஹிந்த்!',
      te: 'స్వాతంత్ర్య దినోత్సవ శుభాకాంక్షలు! జై హింద్!',
      kn: 'ಸ್ವಾತಂತ್ರ್ಯ ದಿನಾಚರಣೆಯ ಶುಭಾಶಯಗಳು! ಜೈ ಹಿಂದ್!',
      mr: 'स्वातंत्र्य दिनाच्या शुभेच्छा! जय हिंद!',
      gu: 'સ્વતંત્રતા દિવસની શુભેચ્છાઓ! જય હિન્દ!',
      bn: 'স্বাধীনতা দিবসের শুভেচ্ছা! জয় হিন্দ!',
    },
    description: 'Celebrating India\'s independence from British rule in 1947.',
    themes: ['freedom', 'nation', 'sacrifice', 'pride'],
    rituals: ['flag_hoisting', 'patriotic_songs', 'kite_flying'],
  },
];

// ─────────────────────────────────────────────────────────────────────────────
// Helper: compute the next occurrence date for a festival
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Compute the next upcoming Gregorian date for a festival seed.
 * For fixed festivals: next occurrence of month/day from today.
 * For lunar festivals: the first date in lunarDates[] that is >= today.
 * Returns null if no upcoming date is available.
 */
export function computeNextFestivalDate(seed: FestivalSeed, now: Date = new Date()): Date | null {
  if (seed.dateType === 'fixed' && seed.fixedMonth && seed.fixedDay) {
    // Fixed festival — compute next occurrence
    const year = now.getUTCFullYear();
    let candidate = new Date(Date.UTC(year, seed.fixedMonth - 1, seed.fixedDay));
    if (candidate.getTime() < now.getTime()) {
      candidate = new Date(Date.UTC(year + 1, seed.fixedMonth - 1, seed.fixedDay));
    }
    return candidate;
  }

  if (seed.dateType === 'lunar' && seed.lunarDates && seed.lunarDates.length > 0) {
    // Lunar festival — find the first pre-computed date >= today
    const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
    for (const dateStr of seed.lunarDates) {
      const candidate = new Date(dateStr + 'T00:00:00Z');
      if (candidate.getTime() >= today.getTime()) {
        return candidate;
      }
    }
    // All pre-computed dates are in the past — return the last one (stale, but better than null)
    return new Date(seed.lunarDates[seed.lunarDates.length - 1] + 'T00:00:00Z');
  }

  return null;
}

/**
 * Compute days until the next occurrence of a festival.
 * Returns 0 if the festival is today, negative if past (shouldn't happen with computeNextFestivalDate).
 */
export function computeDaysUntil(festivalDate: Date, now: Date = new Date()): number {
  const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const target = new Date(Date.UTC(festivalDate.getUTCFullYear(), festivalDate.getUTCMonth(), festivalDate.getUTCDate()));
  const msPerDay = 1000 * 60 * 60 * 24;
  return Math.round((target.getTime() - today.getTime()) / msPerDay);
}
