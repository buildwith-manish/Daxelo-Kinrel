import { Injectable } from '@nestjs/common';

// ── Types ────────────────────────────────────────────────────────────

export interface KinshipTranslation {
  native: string;
  latin: string;
}

export interface KinshipTerm {
  relationshipKey: string;
  englishTerm: string;
  gender: 'male' | 'female' | 'neutral';
  lineage: 'paternal' | 'maternal' | 'neutral';
  relationshipCategory: string;
  translations: Record<string, KinshipTranslation>;
  aliases?: string[];
}

// ── Comprehensive Indian Kinship Database ────────────────────────────

const KINSHIP_DATABASE: KinshipTerm[] = [
  // ── Immediate Family ──────────────────────────────────────────────
  {
    relationshipKey: 'father',
    englishTerm: 'Father',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'पिता', latin: 'Pita' },
      mr: { native: 'वडील', latin: 'Vadil' },
      ta: { native: 'தந்தை', latin: 'Thanthai' },
      te: { native: 'తండ్రి', latin: 'Thandri' },
      kn: { native: 'ತಂದೆ', latin: 'Thande' },
      bn: { native: 'পিতা', latin: 'Pita' },
      gu: { native: 'પિતા', latin: 'Pita' },
    },
    aliases: ['papa', 'dad', 'baap', 'appa'],
  },
  {
    relationshipKey: 'mother',
    englishTerm: 'Mother',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'माता', latin: 'Mata' },
      mr: { native: 'आई', latin: 'Aai' },
      ta: { native: 'தாய்', latin: 'Thai' },
      te: { native: 'తల్లి', latin: 'Thalli' },
      kn: { native: 'ತಾಯಿ', latin: 'Thayi' },
      bn: { native: 'মাতা', latin: 'Mata' },
      gu: { native: 'માતા', latin: 'Mata' },
    },
    aliases: ['mummy', 'mom', 'amma', 'maa'],
  },
  {
    relationshipKey: 'brother',
    englishTerm: 'Brother',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'भाई', latin: 'Bhai' },
      mr: { native: 'भाऊ', latin: 'Bhau' },
      ta: { native: 'சகோதரன்', latin: 'Sagotharan' },
      te: { native: 'సోదరుడు', latin: 'Sodharudu' },
      kn: { native: 'ಸಹೋದರ', latin: 'Sahodara' },
      bn: { native: 'ভাই', latin: 'Bhai' },
      gu: { native: 'ભાઈ', latin: 'Bhai' },
    },
    aliases: ['bhai', 'anna', 'chetta'],
  },
  {
    relationshipKey: 'sister',
    englishTerm: 'Sister',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'बहन', latin: 'Behan' },
      mr: { native: 'बहिण', latin: 'Bahin' },
      ta: { native: 'சகோதரி', latin: 'Sagothari' },
      te: { native: 'సోదరి', latin: 'Sodhari' },
      kn: { native: 'ಸಹೋದರಿ', latin: 'Sahodari' },
      bn: { native: 'বোন', latin: 'Bon' },
      gu: { native: 'બહેન', latin: 'Bahen' },
    },
    aliases: ['didi', 'akka', 'chechi'],
  },
  {
    relationshipKey: 'son',
    englishTerm: 'Son',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'बेटा', latin: 'Beta' },
      mr: { native: 'मुलगा', latin: 'Mulga' },
      ta: { native: 'மகன்', latin: 'Magan' },
      te: { native: 'కొడుకు', latin: 'Koduku' },
      kn: { native: 'ಮಗ', latin: 'Maga' },
      bn: { native: 'ছেলে', latin: 'Chele' },
      gu: { native: 'દીકરો', latin: 'Dikro' },
    },
    aliases: ['beta', 'putra'],
  },
  {
    relationshipKey: 'daughter',
    englishTerm: 'Daughter',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'बेटी', latin: 'Beti' },
      mr: { native: 'मुलगी', latin: 'Mulgi' },
      ta: { native: 'மகள்', latin: 'Magal' },
      te: { native: 'కూతురు', latin: 'Koothuru' },
      kn: { native: 'ಮಗಳು', latin: 'Magalu' },
      bn: { native: 'মেয়ে', latin: 'Meye' },
      gu: { native: 'દીકરી', latin: 'Dikri' },
    },
    aliases: ['beti', 'putri'],
  },
  {
    relationshipKey: 'husband',
    englishTerm: 'Husband',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'पति', latin: 'Pati' },
      mr: { native: 'नवरा', latin: 'Navra' },
      ta: { native: 'கணவர்', latin: 'Kanavar' },
      te: { native: 'భర్త', latin: 'Bhartha' },
      kn: { native: 'ಪತಿ', latin: 'Pathi' },
      bn: { native: 'স্বামী', latin: 'Swami' },
      gu: { native: 'પતિ', latin: 'Pati' },
    },
    aliases: ['pati'],
  },
  {
    relationshipKey: 'wife',
    englishTerm: 'Wife',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'पत्नी', latin: 'Patni' },
      mr: { native: 'बायको', latin: 'Bayko' },
      ta: { native: 'மனைவி', latin: 'Manaivi' },
      te: { native: 'భార్య', latin: 'Bharya' },
      kn: { native: 'ಪತ್ನಿ', latin: 'Pathni' },
      bn: { native: 'স্ত্রী', latin: 'Stree' },
      gu: { native: 'પત્ની', latin: 'Patni' },
    },
    aliases: ['patni', 'vivaha'],
  },

  // ── Extended Paternal ─────────────────────────────────────────────
  {
    relationshipKey: 'grandfather_paternal',
    englishTerm: 'Paternal Grandfather',
    gender: 'male',
    lineage: 'paternal',
    relationshipCategory: 'extended_paternal',
    translations: {
      hi: { native: 'दादा', latin: 'Dada' },
      mr: { native: 'आजोबा', latin: 'Ajoba' },
      ta: { native: 'தாத்தா', latin: 'Thatha' },
      te: { native: 'తాతయ్య', latin: 'Thathayya' },
      kn: { native: 'ಅಜ್ಜ', latin: 'Ajja' },
      bn: { native: 'দাদু', latin: 'Dadu' },
      gu: { native: 'દાદા', latin: 'Dada' },
    },
    aliases: ['dada', 'babuji', 'thatha'],
  },
  {
    relationshipKey: 'grandmother_paternal',
    englishTerm: 'Paternal Grandmother',
    gender: 'female',
    lineage: 'paternal',
    relationshipCategory: 'extended_paternal',
    translations: {
      hi: { native: 'दादी', latin: 'Dadi' },
      mr: { native: 'आजी', latin: 'Aaji' },
      ta: { native: 'பாட்டி', latin: 'Paati' },
      te: { native: 'అమ్మమ్మ', latin: 'Ammamma' },
      kn: { native: 'ಅಜ್ಜಿ', latin: 'Ajji' },
      bn: { native: 'দিদা', latin: 'Dida' },
      gu: { native: 'દાદી', latin: 'Dadi' },
    },
    aliases: ['dadi', 'nani', 'paati'],
  },
  {
    relationshipKey: 'fathers_brother',
    englishTerm: "Father's Brother (Uncle)",
    gender: 'male',
    lineage: 'paternal',
    relationshipCategory: 'extended_paternal',
    translations: {
      hi: { native: 'चाचा', latin: 'Chacha' },
      mr: { native: 'काका', latin: 'Kaka' },
      ta: { native: 'சித்தப்பா', latin: 'Chithappa' },
      te: { native: 'బాబాయి', latin: 'Babai' },
      kn: { native: 'ಚಿಕ್ಕಪ್ಪ', latin: 'Chikkappa' },
      bn: { native: 'জ্যাঠামশাই', latin: 'Jyathamashai' },
      gu: { native: 'કાકા', latin: 'Kaka' },
    },
    aliases: ['chacha', 'kaka', 'chithappa', 'babai'],
  },
  {
    relationshipKey: 'fathers_brothers_wife',
    englishTerm: "Father's Brother's Wife (Aunt)",
    gender: 'female',
    lineage: 'paternal',
    relationshipCategory: 'extended_paternal',
    translations: {
      hi: { native: 'चाची', latin: 'Chachi' },
      mr: { native: 'काकू', latin: 'Kaku' },
      ta: { native: 'சித்தி', latin: 'Chithi' },
      te: { native: 'బావమ్మ', latin: 'Bavamma' },
      kn: { native: 'ಚಿಕ್ಕಮ್ಮ', latin: 'Chikkamma' },
      bn: { native: 'জ্যাঠিমা', latin: 'Jyathima' },
      gu: { native: 'કાકી', latin: 'Kaki' },
    },
    aliases: ['chachi', 'kaku', 'chithi'],
  },
  {
    relationshipKey: 'fathers_sister',
    englishTerm: "Father's Sister (Aunt)",
    gender: 'female',
    lineage: 'paternal',
    relationshipCategory: 'extended_paternal',
    translations: {
      hi: { native: 'बुआ', latin: 'Bua' },
      mr: { native: 'आत्या', latin: 'Atya' },
      ta: { native: 'அத்தை', latin: 'Athai' },
      te: { native: 'పిన్ని', latin: 'Pinni' },
      kn: { native: 'ಅತ್ತೆ', latin: 'Atthe' },
      bn: { native: 'পিসিমা', latin: 'Pishima' },
      gu: { native: 'ફોઈ', latin: 'Foi' },
    },
    aliases: ['bua', 'atya', 'athai', 'pinni'],
  },
  {
    relationshipKey: 'fathers_sisters_husband',
    englishTerm: "Father's Sister's Husband (Uncle)",
    gender: 'male',
    lineage: 'paternal',
    relationshipCategory: 'extended_paternal',
    translations: {
      hi: { native: 'फूफा', latin: 'Foofa' },
      mr: { native: 'आत्याचे नवरे', latin: 'Atyache Navre' },
      ta: { native: 'அத்தான்', latin: 'Aththan' },
      te: { native: 'మేనమామ', latin: 'Menamama' },
      kn: { native: 'ಅತ್ತಿಗೆಯ ಗಂಡ', latin: 'Atthigeya Ganda' },
      bn: { native: 'পিসিমশাই', latin: 'Pishimashai' },
      gu: { native: 'ફોઈફાળા', latin: 'Foifala' },
    },
    aliases: ['foofa', 'foofi'],
  },

  // ── Extended Maternal ─────────────────────────────────────────────
  {
    relationshipKey: 'grandfather_maternal',
    englishTerm: 'Maternal Grandfather',
    gender: 'male',
    lineage: 'maternal',
    relationshipCategory: 'extended_maternal',
    translations: {
      hi: { native: 'नाना', latin: 'Nana' },
      mr: { native: 'सासरे', latin: 'Sasare' },
      ta: { native: 'தாத்தா', latin: 'Thatha' },
      te: { native: 'మామయ్య', latin: 'Mamayya' },
      kn: { native: 'ಮಾವ', latin: 'Mava' },
      bn: { native: 'নানা', latin: 'Nana' },
      gu: { native: 'નાના', latin: 'Nana' },
    },
    aliases: ['nana', 'nanaji'],
  },
  {
    relationshipKey: 'grandmother_maternal',
    englishTerm: 'Maternal Grandmother',
    gender: 'female',
    lineage: 'maternal',
    relationshipCategory: 'extended_maternal',
    translations: {
      hi: { native: 'नानी', latin: 'Nani' },
      mr: { native: 'सासूबाई', latin: 'Sasubai' },
      ta: { native: 'பாட்டி', latin: 'Paati' },
      te: { native: 'అవ్వ', latin: 'Avva' },
      kn: { native: 'ಅಜ್ಜಿ', latin: 'Ajji' },
      bn: { native: 'নানী', latin: 'Nani' },
      gu: { native: 'નાની', latin: 'Nani' },
    },
    aliases: ['nani', 'naniamma'],
  },
  {
    relationshipKey: 'mothers_brother',
    englishTerm: "Mother's Brother (Uncle)",
    gender: 'male',
    lineage: 'maternal',
    relationshipCategory: 'extended_maternal',
    translations: {
      hi: { native: 'मामा', latin: 'Mama' },
      mr: { native: 'मामा', latin: 'Mama' },
      ta: { native: 'மாமா', latin: 'Mama' },
      te: { native: 'మామ', latin: 'Mama' },
      kn: { native: 'ಮಾವ', latin: 'Mava' },
      bn: { native: 'মামা', latin: 'Mama' },
      gu: { native: 'મામા', latin: 'Mama' },
    },
    aliases: ['mama', 'mamaji'],
  },
  {
    relationshipKey: 'mothers_brothers_wife',
    englishTerm: "Mother's Brother's Wife (Aunt)",
    gender: 'female',
    lineage: 'maternal',
    relationshipCategory: 'extended_maternal',
    translations: {
      hi: { native: 'मामी', latin: 'Mami' },
      mr: { native: 'मामी', latin: 'Mami' },
      ta: { native: 'மாமி', latin: 'Mami' },
      te: { native: 'అత్త', latin: 'Atta' },
      kn: { native: 'ಅತ್ತೆ', latin: 'Atthe' },
      bn: { native: 'মামী', latin: 'Mami' },
      gu: { native: 'મામી', latin: 'Mami' },
    },
    aliases: ['mami', 'mamiji'],
  },
  {
    relationshipKey: 'mothers_sister',
    englishTerm: "Mother's Sister (Aunt)",
    gender: 'female',
    lineage: 'maternal',
    relationshipCategory: 'extended_maternal',
    translations: {
      hi: { native: 'मौसी', latin: 'Mausi' },
      mr: { native: 'मावशी', latin: 'Mavshi' },
      ta: { native: 'சித்தி', latin: 'Chithi' },
      te: { native: 'పెద్దమ్మ', latin: 'Peddamma' },
      kn: { native: 'ಚಿಕ್ಕಮ್ಮ', latin: 'Chikkamma' },
      bn: { native: 'খুড়ি', latin: 'Khuri' },
      gu: { native: 'માસી', latin: 'Masi' },
    },
    aliases: ['mausi', 'mavshi', 'masi'],
  },
  {
    relationshipKey: 'mothers_sisters_husband',
    englishTerm: "Mother's Sister's Husband (Uncle)",
    gender: 'male',
    lineage: 'maternal',
    relationshipCategory: 'extended_maternal',
    translations: {
      hi: { native: 'मौसा', latin: 'Mausa' },
      mr: { native: 'मावसे', latin: 'Mavse' },
      ta: { native: 'சித்தப்பா', latin: 'Chithappa' },
      te: { native: 'పెద్దబాబాయి', latin: 'Peddababai' },
      kn: { native: 'ಚಿಕ್ಕಪ್ಪ', latin: 'Chikkappa' },
      bn: { native: 'খুড়ো', latin: 'Khuro' },
      gu: { native: 'માસા', latin: 'Masa' },
    },
    aliases: ['mausa', 'mavse', 'masa'],
  },

  // ── Cousin Relationships ──────────────────────────────────────────
  {
    relationshipKey: 'cousin_paternal_male',
    englishTerm: 'Paternal Male Cousin',
    gender: 'male',
    lineage: 'paternal',
    relationshipCategory: 'extended_paternal',
    translations: {
      hi: { native: 'चचेरा भाई', latin: 'Chachera Bhai' },
      mr: { native: 'चुलत भाऊ', latin: 'Chulat Bhau' },
      ta: { native: 'சித்தப்பா மகன்', latin: 'Chithappa Magan' },
      te: { native: 'బాబాయి కొడుకు', latin: 'Babai Koduku' },
      kn: { native: 'ಸೋದರ ಸಂಬಂಧಿ', latin: 'Sodara Sambandhi' },
      bn: { native: 'জ্যাঠাতো ভাই', latin: 'Jythato Bhai' },
      gu: { native: 'ફોઈફાળાનો દીકરો', latin: 'Foi Fala no Dikro' },
    },
    aliases: ['chachera bhai', 'cousin bhai'],
  },
  {
    relationshipKey: 'cousin_maternal_male',
    englishTerm: 'Maternal Male Cousin',
    gender: 'male',
    lineage: 'maternal',
    relationshipCategory: 'extended_maternal',
    translations: {
      hi: { native: 'ममेरा भाई', latin: 'Mamera Bhai' },
      mr: { native: 'मावस भाऊ', latin: 'Mavas Bhau' },
      ta: { native: 'மாமா மகன்', latin: 'Mama Magan' },
      te: { native: 'మామ కొడుకు', latin: 'Mama Koduku' },
      kn: { native: 'ಮಾವನ ಮಗ', latin: 'Mavana Maga' },
      bn: { native: 'খালাতো ভাই', latin: 'Khalato Bhai' },
      gu: { native: 'માસાનો દીકરો', latin: 'Masano Dikro' },
    },
    aliases: ['mamera bhai'],
  },

  // ── In-Laws ───────────────────────────────────────────────────────
  {
    relationshipKey: 'father_in_law',
    englishTerm: 'Father-in-Law',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'in_laws',
    translations: {
      hi: { native: 'ससुर', latin: 'Sasur' },
      mr: { native: 'सासरे', latin: 'Sasare' },
      ta: { native: 'மாமனார்', latin: 'Mamanar' },
      te: { native: 'మామయ్య', latin: 'Mamayya' },
      kn: { native: 'ಮಾವ', latin: 'Mava' },
      bn: { native: 'শ্বশুর', latin: 'Shoshur' },
      gu: { native: 'સસરા', latin: 'Sasra' },
    },
    aliases: ['sasur', 'sasare'],
  },
  {
    relationshipKey: 'mother_in_law',
    englishTerm: 'Mother-in-Law',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'in_laws',
    translations: {
      hi: { native: 'सास', latin: 'Saas' },
      mr: { native: 'सासूबाई', latin: 'Sasubai' },
      ta: { native: 'மாமியார்', latin: 'Mamiyar' },
      te: { native: 'అత్తగారు', latin: 'Attagaru' },
      kn: { native: 'ಅತ್ತೆ', latin: 'Atthe' },
      bn: { native: 'শাশুড়ি', latin: 'Shashuri' },
      gu: { native: 'સાસુ', latin: 'Saasu' },
    },
    aliases: ['saas', 'sasubai'],
  },
  {
    relationshipKey: 'brother_in_law_husbands_brother',
    englishTerm: "Brother-in-Law (Husband's Brother)",
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'in_laws',
    translations: {
      hi: { native: 'देवर', latin: 'Devar' },
      mr: { native: 'दीर', latin: 'Dir' },
      ta: { native: 'மச்சான்', latin: 'Machchan' },
      te: { native: 'మరదలు', latin: 'Maradalu' },
      kn: { native: 'ದಿರ', latin: 'Dira' },
      bn: { native: 'দেওর', latin: 'Deor' },
      gu: { native: 'દેવર', latin: 'Devar' },
    },
    aliases: ['devar', 'jeth'],
  },
  {
    relationshipKey: 'sister_in_law_husbands_sister',
    englishTerm: "Sister-in-Law (Husband's Sister)",
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'in_laws',
    translations: {
      hi: { native: 'ननद', latin: 'Nanad' },
      mr: { native: 'नणंद', latin: 'Nanand' },
      ta: { native: 'நாத்தினம்', latin: 'Naaththinam' },
      te: { native: 'మరదలు', latin: 'Maradalu' },
      kn: { native: 'ನಂದಿನಿ', latin: 'Nandini' },
      bn: { native: 'ননদ', latin: 'Nonod' },
      gu: { native: 'નણંદ', latin: 'Nanand' },
    },
    aliases: ['nanad', 'nandini'],
  },
  {
    relationshipKey: 'brother_in_law_wifes_brother',
    englishTerm: "Brother-in-Law (Wife's Brother)",
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'in_laws',
    translations: {
      hi: { native: 'साला', latin: 'Sala' },
      mr: { native: 'साला', latin: 'Sala' },
      ta: { native: 'மைத்துனன்', latin: 'Maithunan' },
      te: { native: 'బావమరుదులు', latin: 'Bavamarudulu' },
      kn: { native: 'ಬಾವ', latin: 'Bava' },
      bn: { native: 'শ্যালক', latin: 'Shyalok' },
      gu: { native: 'સાળો', latin: 'Salo' },
    },
    aliases: ['sala', 'sadhu bhai'],
  },
  {
    relationshipKey: 'sister_in_law_wifes_sister',
    englishTerm: "Sister-in-Law (Wife's Sister)",
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'in_laws',
    translations: {
      hi: { native: 'साली', latin: 'Sali' },
      mr: { native: 'साली', latin: 'Sali' },
      ta: { native: 'மைத்துனி', latin: 'Maithuni' },
      te: { native: 'వదిన', latin: 'Vadina' },
      kn: { native: 'ಅಳಿಯ', latin: 'Aliya' },
      bn: { native: 'শ্যালিকা', latin: 'Shyalika' },
      gu: { native: 'સાળી', latin: 'Sali' },
    },
    aliases: ['sali'],
  },
  {
    relationshipKey: 'son_in_law',
    englishTerm: 'Son-in-Law',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'in_laws',
    translations: {
      hi: { native: 'दामाद', latin: 'Damad' },
      mr: { native: 'जावई', latin: 'Jawai' },
      ta: { native: 'மருமகன்', latin: 'Marumagan' },
      te: { native: 'అల్లుడు', latin: 'Alludu' },
      kn: { native: 'ಅಳಿಯ', latin: 'Aliya' },
      bn: { native: 'জামাই', latin: 'Jamai' },
      gu: { native: 'જમાઇ', latin: 'Jamai' },
    },
    aliases: ['damad', 'jawai', 'jamai'],
  },
  {
    relationshipKey: 'daughter_in_law',
    englishTerm: 'Daughter-in-Law',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'in_laws',
    translations: {
      hi: { native: 'बहू', latin: 'Bahu' },
      mr: { native: 'सून', latin: 'Soon' },
      ta: { native: 'மருமகள்', latin: 'Marumagal' },
      te: { native: 'కోడలు', latin: 'Kodalu' },
      kn: { native: 'ಸೊಸೆ', latin: 'Sose' },
      bn: { native: 'বউমা', latin: 'Bouma' },
      gu: { native: 'પુત્રવધૂ', latin: 'Putravadhu' },
    },
    aliases: ['bahu', 'soon', 'kodalu'],
  },

  // ── By Marriage ───────────────────────────────────────────────────
  {
    relationshipKey: 'co_brother_in_law',
    englishTerm: "Co-Brother-in-Law (Wife's Sister's Husband)",
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'by_marriage',
    translations: {
      hi: { native: 'समंधी', latin: 'Samandhi' },
      mr: { native: 'समंधी', latin: 'Samandhi' },
      ta: { native: 'சகோதரியின் கணவர்', latin: 'Sagothiriyin Kanavar' },
      te: { native: 'సర్దారు', latin: 'Sardaru' },
      kn: { native: 'ಸಮಂಧಿ', latin: 'Samandhi' },
      bn: { native: 'সমধি', latin: 'Samadhi' },
      gu: { native: 'સમંધી', latin: 'Samandhi' },
    },
    aliases: ['samandhi', 'sadhu bhai'],
  },
  {
    relationshipKey: 'co_sister_in_law',
    englishTerm: "Co-Sister-in-Law (Husband's Brother's Wife)",
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'by_marriage',
    translations: {
      hi: { native: 'भाभी', latin: 'Bhabhi' },
      mr: { native: 'भावजी', latin: 'Bhavji' },
      ta: { native: 'அண்ணி', latin: 'Anni' },
      te: { native: 'వదిన', latin: 'Vadina' },
      kn: { native: 'ಅತ್ತಿಗೆ', latin: 'Atthige' },
      bn: { native: 'ভাবী', latin: 'Bhabi' },
      gu: { native: 'ભાભી', latin: 'Bhabhi' },
    },
    aliases: ['bhabhi', 'bhavji', 'anni', 'vadina'],
  },
  {
    relationshipKey: 'elder_brothers_wife',
    englishTerm: "Elder Brother's Wife",
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'by_marriage',
    translations: {
      hi: { native: 'भाभी', latin: 'Bhabhi' },
      mr: { native: 'वाहिनी', latin: 'Vahini' },
      ta: { native: 'அண்ணி', latin: 'Anni' },
      te: { native: 'వదిన', latin: 'Vadina' },
      kn: { native: 'ಅತ್ತಿಗೆ', latin: 'Atthige' },
      bn: { native: 'ভাবী', latin: 'Bhabi' },
      gu: { native: 'ભાભી', latin: 'Bhabhi' },
    },
    aliases: ['bhabhi', 'vahini', 'anni', 'vadina'],
  },
  {
    relationshipKey: 'younger_brothers_wife',
    englishTerm: "Younger Brother's Wife",
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'by_marriage',
    translations: {
      hi: { native: 'भाभी', latin: 'Bhabhi' },
      mr: { native: 'भावजी', latin: 'Bhavji' },
      ta: { native: 'நாத்தினி', latin: 'Naathini' },
      te: { native: 'కోడలు', latin: 'Kodalu' },
      kn: { native: 'ಸೊಸೆ', latin: 'Sose' },
      bn: { native: 'ভাবী', latin: 'Bhabi' },
      gu: { native: 'ભાભી', latin: 'Bhabhi' },
    },
    aliases: ['bhabhi'],
  },
  {
    relationshipKey: 'sisters_husband',
    englishTerm: "Sister's Husband",
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'by_marriage',
    translations: {
      hi: { native: 'जीजा', latin: 'Jija' },
      mr: { native: 'मेहुणा', latin: 'Mehuna' },
      ta: { native: 'மைத்துனன்', latin: 'Maithunan' },
      te: { native: 'బావ', latin: 'Bava' },
      kn: { native: 'ಬಾವ', latin: 'Bava' },
      bn: { native: 'বিয়াই', latin: 'Biyai' },
      gu: { native: 'જીજા', latin: 'Jija' },
    },
    aliases: ['jija', 'mehuna', 'bava'],
  },

  // ── Nephew/Niece ──────────────────────────────────────────────────
  {
    relationshipKey: 'nephew_brothers_son',
    englishTerm: "Brother's Son (Nephew)",
    gender: 'male',
    lineage: 'paternal',
    relationshipCategory: 'extended_paternal',
    translations: {
      hi: { native: 'भतीजा', latin: 'Bhatija' },
      mr: { native: 'भाचा', latin: 'Bhacha' },
      ta: { native: 'சகோதரன் மகன்', latin: 'Sagotharan Magan' },
      te: { native: 'సోదరుని కొడుకు', latin: 'Sodharuni Koduku' },
      kn: { native: 'ಸೋದರನ ಮಗ', latin: 'Sodarana Maga' },
      bn: { native: 'ভাইপো', latin: 'Bhaipo' },
      gu: { native: 'ભત્રીજો', latin: 'Bhatrijo' },
    },
    aliases: ['bhatija', 'bhacha'],
  },
  {
    relationshipKey: 'niece_brothers_daughter',
    englishTerm: "Brother's Daughter (Niece)",
    gender: 'female',
    lineage: 'paternal',
    relationshipCategory: 'extended_paternal',
    translations: {
      hi: { native: 'भतीजी', latin: 'Bhatiji' },
      mr: { native: 'भाची', latin: 'Bhachi' },
      ta: { native: 'சகோதரன் மகள்', latin: 'Sagotharan Magal' },
      te: { native: 'సోదరుని కూతురు', latin: 'Sodharuni Koothuru' },
      kn: { native: 'ಸೋದರನ ಮಗಳು', latin: 'Sodarana Magalu' },
      bn: { native: 'ভাইঝি', latin: 'Bhaijhi' },
      gu: { native: 'ભત્રીજી', latin: 'Bhatriji' },
    },
    aliases: ['bhatiji', 'bhachi'],
  },
  {
    relationshipKey: 'nephew_sisters_son',
    englishTerm: "Sister's Son (Nephew)",
    gender: 'male',
    lineage: 'maternal',
    relationshipCategory: 'extended_maternal',
    translations: {
      hi: { native: 'भांजा', latin: 'Bhanja' },
      mr: { native: 'भाचा', latin: 'Bhacha' },
      ta: { native: 'சகோதரி மகன்', latin: 'Sagothari Magan' },
      te: { native: 'సోదరి కొడుకు', latin: 'Sodhari Koduku' },
      kn: { native: 'ಮೈದುನ', latin: 'Maiduna' },
      bn: { native: 'ভাগ্নে', latin: 'Bhagne' },
      gu: { native: 'ભાણેજ', latin: 'Bhanej' },
    },
    aliases: ['bhanja', 'bhagne'],
  },
  {
    relationshipKey: 'niece_sisters_daughter',
    englishTerm: "Sister's Daughter (Niece)",
    gender: 'female',
    lineage: 'maternal',
    relationshipCategory: 'extended_maternal',
    translations: {
      hi: { native: 'भांजी', latin: 'Bhanji' },
      mr: { native: 'भाची', latin: 'Bhachi' },
      ta: { native: 'சகோதரி மகள்', latin: 'Sagothari Magal' },
      te: { native: 'సోదరి కూతురు', latin: 'Sodhari Koothuru' },
      kn: { native: 'ಮೈದುನಳು', latin: 'Maidunalu' },
      bn: { native: 'ভাগ্নী', latin: 'Bhagni' },
      gu: { native: 'ભાણેજી', latin: 'Bhaneji' },
    },
    aliases: ['bhanji', 'bhagni'],
  },

  // ── Great Grandparents ────────────────────────────────────────────
  {
    relationshipKey: 'great_grandfather',
    englishTerm: 'Great Grandfather',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'परदादा', latin: 'Pardada' },
      mr: { native: 'पणजोबा', latin: 'Panajoba' },
      ta: { native: 'பெரியப்பா', latin: 'Periyappa' },
      te: { native: 'ముత్తయ్య', latin: 'Muthayya' },
      kn: { native: 'ಮುತ್ತಜ್ಜ', latin: 'Muttajja' },
      bn: { native: 'পরদাদু', latin: 'Pordadu' },
      gu: { native: 'પરદાદા', latin: 'Pardada' },
    },
    aliases: ['pardada', 'parnana'],
  },
  {
    relationshipKey: 'great_grandmother',
    englishTerm: 'Great Grandmother',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'परदादी', latin: 'Pardadi' },
      mr: { native: 'पणजी', latin: 'Panaji' },
      ta: { native: 'பெரியம்மா', latin: 'Periyamma' },
      te: { native: 'ముత్తయమ్మ', latin: 'Muthayamma' },
      kn: { native: 'ಮುತ್ತಜ್ಜಿ', latin: 'Muttajji' },
      bn: { native: 'পরদিদা', latin: 'Pordida' },
      gu: { native: 'પરદાદી', latin: 'Pardadi' },
    },
    aliases: ['pardadi', 'parnani'],
  },

  // ── Additional Extended Family ────────────────────────────────────
  {
    relationshipKey: 'elder_brother',
    englishTerm: 'Elder Brother',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'बड़ा भाई', latin: 'Bada Bhai' },
      mr: { native: 'थोरले भाऊ', latin: 'Thorle Bhau' },
      ta: { native: 'அண்ணன்', latin: 'Annan' },
      te: { native: 'అన్నయ్య', latin: 'Annayya' },
      kn: { native: 'ಅಣ್ಣ', latin: 'Anna' },
      bn: { native: 'দাদা', latin: 'Dada' },
      gu: { native: 'મોટા ભાઈ', latin: 'Mota Bhai' },
    },
    aliases: ['anna', 'bada bhai', 'dada', 'annayya'],
  },
  {
    relationshipKey: 'younger_brother',
    englishTerm: 'Younger Brother',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'छोटा भाई', latin: 'Chhota Bhai' },
      mr: { native: 'धाकटे भाऊ', latin: 'Dhakte Bhau' },
      ta: { native: 'தம்பி', latin: 'Thambi' },
      te: { native: 'తమ్ముడు', latin: 'Thammudu' },
      kn: { native: 'ತಮ್ಮ', latin: 'Thamma' },
      bn: { native: 'ছোট ভাই', latin: 'Choto Bhai' },
      gu: { native: 'નાના ભાઈ', latin: 'Nana Bhai' },
    },
    aliases: ['chhota bhai', 'thambi', 'thammudu'],
  },
  {
    relationshipKey: 'elder_sister',
    englishTerm: 'Elder Sister',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'बड़ी बहन', latin: 'Badi Behan' },
      mr: { native: 'थोरली बहिण', latin: 'Thorli Bahin' },
      ta: { native: 'அக்கா', latin: 'Akka' },
      te: { native: 'అక్క', latin: 'Akka' },
      kn: { native: 'ಅಕ್ಕ', latin: 'Akka' },
      bn: { native: 'দিদি', latin: 'Didi' },
      gu: { native: 'મોટી બહેન', latin: 'Moti Bahen' },
    },
    aliases: ['didi', 'akka', 'badi behan'],
  },
  {
    relationshipKey: 'younger_sister',
    englishTerm: 'Younger Sister',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'छोटी बहन', latin: 'Chhoti Behan' },
      mr: { native: 'धाकटी बहिण', latin: 'Dhakti Bahin' },
      ta: { native: 'தங்கை', latin: 'Thangai' },
      te: { native: 'చెల్లి', latin: 'Chelli' },
      kn: { native: 'ತಂಗಿ', latin: 'Thangi' },
      bn: { native: 'ছোট বোন', latin: 'Choto Bon' },
      gu: { native: 'નાની બહેન', latin: 'Nani Bahen' },
    },
    aliases: ['chhoti behan', 'thangai', 'chelli'],
  },
  {
    relationshipKey: 'stepfather',
    englishTerm: 'Stepfather',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'सौतेले पिता', latin: 'Sautele Pita' },
      mr: { native: 'सावत्र वडील', latin: 'Savatr Vadil' },
      ta: { native: 'வளர்ப்பு தந்தை', latin: 'Valarppu Thanthai' },
      te: { native: 'సవతి తండ్రి', latin: 'Savathi Thandri' },
      kn: { native: 'ಮಲತಂದೆ', latin: 'Malathande' },
      bn: { native: 'সতীয় পিতা', latin: 'Sotiyo Pita' },
      gu: { native: 'સાવકા પિતા', latin: 'Savaka Pita' },
    },
    aliases: ['sautele pita'],
  },
  {
    relationshipKey: 'stepmother',
    englishTerm: 'Stepmother',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'सौतेली माँ', latin: 'Sautele Maa' },
      mr: { native: 'सावत्र आई', latin: 'Savatr Aai' },
      ta: { native: 'வளர்ப்பு தாய்', latin: 'Valarppu Thai' },
      te: { native: 'సవతి తల్లి', latin: 'Savathi Thalli' },
      kn: { native: 'ಮಲತಾಯಿ', latin: 'Malathayi' },
      bn: { native: 'সতীয় মাতা', latin: 'Sotiyo Mata' },
      gu: { native: 'સાવકા માતા', latin: 'Savaka Mata' },
    },
    aliases: ['sautele maa', 'savatr aai'],
  },
  {
    relationshipKey: 'grandson',
    englishTerm: 'Grandson',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'पोता', latin: 'Pota' },
      mr: { native: 'नातू', latin: 'Natu' },
      ta: { native: 'பேரப்பிள்ளை', latin: 'Perappillai' },
      te: { native: 'మనుమడు', latin: 'Manumadu' },
      kn: { native: 'ಮೊಮ್ಮಗ', latin: 'Mommaga' },
      bn: { native: 'নাতি', latin: 'Nati' },
      gu: { native: 'પૌત્ર', latin: 'Pautra' },
    },
    aliases: ['pota', 'natu'],
  },
  {
    relationshipKey: 'granddaughter',
    englishTerm: 'Granddaughter',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'पोती', latin: 'Poti' },
      mr: { native: 'नातिनी', latin: 'Natinī' },
      ta: { native: 'பேத்தி', latin: 'Pethi' },
      te: { native: 'మనుమరాలు', latin: 'Manumaralu' },
      kn: { native: 'ಮೊಮ್ಮಗಳು', latin: 'Mommagalu' },
      bn: { native: 'নাতনী', latin: 'Natni' },
      gu: { native: 'પૌત્રી', latin: 'Pautri' },
    },
    aliases: ['poti', 'pethi'],
  },
  {
    relationshipKey: 'uncle_generic',
    englishTerm: 'Uncle (Generic/Respectful)',
    gender: 'male',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'काका', latin: 'Kaka' },
      mr: { native: 'काका', latin: 'Kaka' },
      ta: { native: 'மாமா', latin: 'Mama' },
      te: { native: 'బాబాయి', latin: 'Babai' },
      kn: { native: 'ಕಾಕ', latin: 'Kaaka' },
      bn: { native: 'কাকু', latin: 'Kaku' },
      gu: { native: 'કાકા', latin: 'Kaka' },
    },
    aliases: ['kaka', 'mama', 'uncle'],
  },
  {
    relationshipKey: 'aunt_generic',
    englishTerm: 'Aunt (Generic/Respectful)',
    gender: 'female',
    lineage: 'neutral',
    relationshipCategory: 'immediate_family',
    translations: {
      hi: { native: 'काकी', latin: 'Kaki' },
      mr: { native: 'काकू', latin: 'Kaku' },
      ta: { native: 'அத்தை', latin: 'Athai' },
      te: { native: 'పిన్ని', latin: 'Pinni' },
      kn: { native: 'ಕಾಕಿ', latin: 'Kaaki' },
      bn: { native: 'কাকীমা', latin: 'Kakima' },
      gu: { native: 'કાકી', latin: 'Kaki' },
    },
    aliases: ['kaki', 'aunty', 'athai'],
  },
];

@Injectable()
export class KinshipService {
  private readonly kinshipTerms: Map<string, KinshipTerm> = new Map();

  constructor() {
    // Index the database for fast lookups
    for (const term of KINSHIP_DATABASE) {
      this.kinshipTerms.set(term.relationshipKey, term);
    }
  }

  /**
   * Lookup kinship terms with flexible query parameters.
   */
  lookup(params: {
    key?: string;
    search?: string;
    category?: string;
    gender?: string;
    lineage?: string;
  }): KinshipTerm[] {
    let results = [...KINSHIP_DATABASE];

    if (params.key) {
      const term = this.kinshipTerms.get(params.key);
      return term ? [term] : [];
    }

    if (params.search) {
      const query = params.search.toLowerCase().trim();
      results = results.filter((term) => {
        // Match against English term
        if (term.englishTerm.toLowerCase().includes(query)) return true;
        // Match against relationship key
        if (term.relationshipKey.toLowerCase().includes(query)) return true;
        // Match against aliases
        if (term.aliases?.some((a) => a.toLowerCase().includes(query)))
          return true;
        // Match against native/latin translations
        for (const lang of Object.values(term.translations)) {
          if (
            lang.native.toLowerCase().includes(query) ||
            lang.latin.toLowerCase().includes(query)
          )
            return true;
        }
        return false;
      });
    }

    if (params.category) {
      results = results.filter(
        (term) => term.relationshipCategory === params.category,
      );
    }

    if (params.gender) {
      results = results.filter((term) => term.gender === params.gender);
    }

    if (params.lineage) {
      results = results.filter((term) => term.lineage === params.lineage);
    }

    return results;
  }

  /**
   * Get a single term by its relationship key.
   */
  getByKey(key: string): KinshipTerm | undefined {
    return this.kinshipTerms.get(key);
  }

  /**
   * Search kinship terms by a free-text query across all fields.
   */
  search(query: string): KinshipTerm[] {
    return this.lookup({ search: query });
  }

  /**
   * Get all available categories.
   */
  getCategories(): string[] {
    const categories = new Set(KINSHIP_DATABASE.map((t) => t.relationshipCategory));
    return [...categories];
  }

  /**
   * Get all terms in a given category.
   */
  getByCategory(category: string): KinshipTerm[] {
    return KINSHIP_DATABASE.filter(
      (term) => term.relationshipCategory === category,
    );
  }

  /**
   * Get random terms for quiz generation.
   */
  getRandomTerms(count: number, category?: string): KinshipTerm[] {
    let pool = category
      ? KINSHIP_DATABASE.filter((t) => t.relationshipCategory === category)
      : KINSHIP_DATABASE;

    // Shuffle and take `count`
    const shuffled = [...pool].sort(() => Math.random() - 0.5);
    return shuffled.slice(0, Math.min(count, shuffled.length));
  }

  /**
   * Find terms that match a native-language string (used by AI Voice).
   */
  findByNativeTerm(text: string): Array<KinshipTerm & { confidence: number }> {
    const lowerText = text.toLowerCase().trim();
    const matches: Array<KinshipTerm & { confidence: number }> = [];

    for (const term of KINSHIP_DATABASE) {
      let confidence = 0;

      // Check aliases (exact match = high confidence)
      if (term.aliases?.some((a) => a.toLowerCase() === lowerText)) {
        confidence = 0.95;
      }

      // Check english term
      if (term.englishTerm.toLowerCase() === lowerText) {
        confidence = Math.max(confidence, 0.9);
      } else if (term.englishTerm.toLowerCase().includes(lowerText)) {
        confidence = Math.max(confidence, 0.7);
      }

      // Check relationship key
      if (term.relationshipKey.toLowerCase().includes(lowerText)) {
        confidence = Math.max(confidence, 0.6);
      }

      // Check translations (native + latin)
      for (const lang of Object.values(term.translations)) {
        if (lang.native.toLowerCase() === lowerText) {
          confidence = Math.max(confidence, 0.95);
        } else if (lang.latin.toLowerCase() === lowerText) {
          confidence = Math.max(confidence, 0.9);
        } else if (lang.latin.toLowerCase().includes(lowerText)) {
          confidence = Math.max(confidence, 0.65);
        }
      }

      // Partial word match in aliases
      if (confidence === 0 && term.aliases) {
        for (const alias of term.aliases) {
          if (
            alias.toLowerCase().includes(lowerText) ||
            lowerText.includes(alias.toLowerCase())
          ) {
            confidence = Math.max(confidence, 0.5);
          }
        }
      }

      if (confidence > 0) {
        matches.push({ ...term, confidence });
      }
    }

    // Sort by confidence descending
    return matches.sort((a, b) => b.confidence - a.confidence);
  }

  /**
   * Get the full kinship database (for use by other services).
   */
  getAllTerms(): KinshipTerm[] {
    return [...KINSHIP_DATABASE];
  }
}
