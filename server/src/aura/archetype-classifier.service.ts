// server/src/aura/archetype-classifier.service.ts
//
// AURA — Archetype Classification Service
//
// Maps graph metrics → one of 6 archetypes:
//   banyan       — dense, multi-generational (high clustering, deep)
//   river_delta  — dispersed, wide (low clustering, long diameter)
//   confluence   — many lineages merging (3+ distinct lineages)
//   spine        — linear, deep (deep generations, low degree)
//   lotus        — balanced center (mid clustering)
//   forest       — distributed, no single center (fallback)
//
// Algorithm:
//   1. For each archetype, count how many of its thresholds the metrics satisfy.
//   2. Score = (thresholds met) / (total thresholds). Forest always = 0.5.
//   3. Sort by score desc, then by weight desc (for tie-breaking).
//   4. Winner = top, runner-up = second.
//   5. Confidence = 0.5 + (winner.score - runnerUp.score) / (2 * maxPossibleScore)
//      where maxPossibleScore = 6 (normalization constant).
//
// This file has zero NestJS dependencies — it can be unit-tested in isolation
// (same pattern as graph-metrics.ts).

// ─────────────────────────────────────────────────────────────────────────
// TYPES
// ─────────────────────────────────────────────────────────────────────────

import { GraphMetrics } from './graph-metrics';

export type ArchetypeKey =
  | 'banyan'
  | 'river_delta'
  | 'confluence'
  | 'spine'
  | 'lotus'
  | 'forest';

export interface ArchetypeDefinition {
  key: ArchetypeKey;
  names: Record<string, string>;         // locale → display name
  descriptions: Record<string, string>;  // locale → poetic 2-line description
  glyphStyle: string;                    // visual treatment for the symbol
  thresholds: {
    minClusteringCoefficient?: number;
    maxClusteringCoefficient?: number;
    minGenerationDepth?: number;
    maxGenerationDepth?: number;
    minDistinctLineages?: number;
    maxDistinctLineages?: number;
    minGraphDiameter?: number;
    maxAvgDegree?: number;
    minAvgDegree?: number;
  };
  weight: number; // Tie-breaker priority (higher = preferred when scores tie)
}

export interface ClassificationResult {
  archetypeKey: ArchetypeKey;
  confidence: number;   // 0.0–1.0
  definition: ArchetypeDefinition;
  scores: Array<{ key: ArchetypeKey; score: number; weight: number; checksPassed: number; checksTotal: number }>;
}

// ─────────────────────────────────────────────────────────────────────────
// ARCHETYPE DEFINITIONS
// ─────────────────────────────────────────────────────────────────────────

export const ARCHETYPES: ArchetypeDefinition[] = [
  {
    key: 'banyan',
    glyphStyle: 'dense_radial',
    weight: 6,
    thresholds: {
      minClusteringCoefficient: 0.4,
      minGenerationDepth: 3,
    },
    names: {
      en: 'The Banyan',
      hi: 'बरगद',
      ta: 'ஆலமரம்',
      te: 'మర్రిచెట్టు',
      kn: 'ಆಲದ ಮರ',
      ml: 'ആൽമരം',
      mr: 'वटवृक्ष',
      bn: 'বটগাছ',
    },
    descriptions: {
      en: 'One or two roots hold the entire family in their shade.\nStrength passes through you, generation to generation.',
      hi: 'एक या दो जड़ें पूरे परिवार को छाया देती हैं।\nपीढ़ी दर पीढ़ी शक्ति तुमसे गुजरती है।',
      ta: 'ஒன்று அல்லது இரண்டு வேர்கள் குடும்பம் முழுவதையும் நிழல் கொடுக்கின்றன.\nசக்தி தலைமுறை தாண்டி உன்னில் ஓடுகிறது.',
      te: 'ఒకటి లేదా రెండు వేర్లు మొత్తం కుటుంబాన్ని నీడలో ఉంచుతాయి.\nశక్తి తరాల గుండా నీలో ప్రవహిస్తుంది.',
      kn: 'ಒಂದು ಅಥವಾ ಎರಡು ಬೇರುಗಳು ಇಡೀ ಕುಟುಂಬಕ್ಕೆ ನೆರಳು ನೀಡುತ್ತವೆ.\nಶಕ್ತಿ ತಲೆಮಾರಿನಿಂದ ತಲೆಮಾರಿಗೆ ನಿನ್ನ ಮೂಲಕ ಹರಿಯುತ್ತದೆ.',
      ml: 'ഒന്നോ രണ്ടോ വേരുകൾ കുടുംബം മുഴുവൻ നിഴൽ നൽകുന്നു.\nതലമുറകളിലൂടെ ശക്തി നിന്നിലൂടെ ഒഴുകുന്നു.',
      mr: 'एक किंवा दोन मुळे संपूर्ण कुटुंबाला सावली देतात.\nपिढ्यानपिढ्या शक्ती तुमच्यातून वाहते.',
      bn: 'এক বা দুটি শিকড় পুরো পরিবারকে ছায়া দেয়।\nশক্তি প্রজন্মের পর প্রজন্ম তোমার মধ্য দিয়ে প্রবাহিত হয়।',
    },
  },
  {
    key: 'river_delta',
    glyphStyle: 'wide_spiral',
    weight: 4,
    thresholds: {
      maxClusteringCoefficient: 0.2,
      minGraphDiameter: 6,
    },
    names: {
      en: 'The River Delta',
      hi: 'नदी का डेल्टा',
      ta: 'நதி டெல்டா',
      te: 'నది డెల్టా',
      kn: 'ನದಿ ಡೆಲ್ಟಾ',
      ml: 'നദി ഡെൽറ്റ',
      mr: 'नदीचे डेल्टा',
      bn: 'নদীর বদ্বীপ',
    },
    descriptions: {
      en: 'Your family flows outward, branching into the world.\nEach branch carries the same river — born from the same source.',
      hi: 'तुम्हारा परिवार बाहर की ओर बहता है, दुनिया में शाखाएं फैलाता है।\nहर शाखा एक ही नदी को आगे बढ़ाती है।',
      ta: 'உங்கள் குடும்பம் வெளிப்புறமாக ஓடுகிறது, உலகில் கிளை பரப்புகிறது.\nஒவ்வொரு கிளையும் அதே நதியை — அதே மூலத்திலிருந்து.',
      te: 'మీ కుటుంబం బయటికి ప్రవహిస్తుంది, ప్రపంచంలో విస్తరిస్తుంది.\nప్రతి శాఖ అదే నది — అదే మూలం నుండి.',
      kn: 'ನಿಮ್ಮ ಕುಟುಂಬ ಹೊರಕ್ಕೆ ಹರಿಯುತ್ತದೆ, ಜಗತ್ತಿನಲ್ಲಿ ಶಾಖೆಗಳನ್ನು ಹರಡುತ್ತದೆ.\nಪ್ರತಿ ಶಾಖೆ ಅದೇ ನದಿ — ಅದೇ ಮೂಲದಿಂದ ಹುಟ್ಟಿದ.',
      ml: 'നിങ്ങളുടെ കുടുംബം പുറത്തേക്ക് ഒഴുകുന്നു, ലോകത്ത് ശാഖകൾ പരത്തുന്നു.\nഓരോ ശാഖയും ഒരേ നദി — ഒരേ ഉറവിടത്തിൽ നിന്ന്.',
      mr: 'तुमचे कुटुंब बाहेरच्या दिशेने वाहते, जगात शाखा पसरते.\nप्रत्येक शाखा त्याच नदीला पुढे नेते.',
      bn: 'তোমার পরিবার বাইরের দিকে প্রবাহিত হয়, বিশ্বে শাখা ছড়িয়ে পড়ে।\nপ্রতিটি শাখা একই নদী — একই উৎস থেকে জন্ম নেওয়া।',
    },
  },
  {
    key: 'confluence',
    glyphStyle: 'multi_cluster',
    weight: 5,
    thresholds: {
      minDistinctLineages: 3,
    },
    names: {
      en: 'The Confluence',
      hi: 'संगम',
      ta: 'சங்கமம்',
      te: 'సంగమం',
      kn: 'ಸಂಗಮ',
      ml: 'സംഗമം',
      mr: 'संगम',
      bn: 'সংগম',
    },
    descriptions: {
      en: 'Many rivers have joined at your family\'s heart.\nYou are richer for every stream that chose to merge.',
      hi: 'कई नदियाँ तुम्हारे परिवार के हृदय में मिली हैं।\nहर धारा जो मिली उससे तुम और समृद्ध हो।',
      ta: 'பல ஆறுகள் உங்கள் குடும்பத்தின் இதயத்தில் சேர்ந்துள்ளன.\nகலந்த ஒவ்வொரு நீரோடையாலும் நீங்கள் மேலும் வளமானீர்கள்.',
      te: 'అనేక నదులు మీ కుటుంబ హృదయంలో కలిశాయి.\nకలిసిన ప్రతి ప్రవాహంతో మీరు మరింత సంపన్నులయ్యారు.',
      kn: 'ಹಲವು ನದಿಗಳು ನಿಮ್ಮ ಕುಟುಂಬದ ಹೃದಯದಲ್ಲಿ ಸೇರಿವೆ.\nಕಲೆತ ಪ್ರತಿ ಹೊಳೆಯಿಂದ ನೀವು ಇನ್ನಷ್ಟು ಶ್ರೀಮಂತರಾಗಿದ್ದೀರಿ.',
      ml: 'പലനദികൾ നിങ്ങളുടെ കുടുംബഹൃദയത്തിൽ ഒന്നിച്ചു.\nകൂടിച്ചേർന്ന ഓരോ ധാരയാലും നിങ്ങൾ കൂടുതൽ സമ്പന്നരായി.',
      mr: 'अनेक नद्या तुमच्या कुटुंबाच्या हृदयात एकत्र आल्या आहेत.\nमिसळलेल्या प्रत्येक प्रवाहामुळे तुम्ही अधिक श्रीमंत झालात.',
      bn: 'অনেক নদী তোমার পরিবারের হৃদয়ে মিলিত হয়েছে।\nমিলিত প্রতিটি স্রোতের কারণে তুমি আরও সমৃদ্ধ।',
    },
  },
  {
    key: 'spine',
    glyphStyle: 'linear_spine',
    weight: 3,
    thresholds: {
      minGenerationDepth: 4,
      maxAvgDegree: 2.5,
    },
    names: {
      en: 'The Spine',
      hi: 'रीढ़',
      ta: 'தண்டுவடம்',
      te: 'వెన్నెముక',
      kn: 'ಬೆನ್ನೆಲುಬು',
      ml: 'നട്ടെല്ല്',
      mr: 'कणा',
      bn: 'মেরুদণ্ড',
    },
    descriptions: {
      en: 'Yours is a family of deep roots and tall lineage.\nEvery generation stands on the shoulders of the last.',
      hi: 'तुम्हारा परिवार गहरी जड़ों और ऊँचे वंश का है।\nहर पीढ़ी पिछली पीढ़ी के कंधों पर खड़ी है।',
      ta: 'உங்களுடையது ஆழமான வேர்களும் உயரமான வம்சமும் கொண்ட குடும்பம்.\nஒவ்வொரு தலைமுறையும் முந்தைய தலைமுறையின் தோளில் நிற்கிறது.',
      te: 'మీది లోతైన వేర్లు మరియు ఉన్నత వంశం కలిగిన కుటుంబం.\nప్రతి తరం మునుపటి తరం భుజాలపై నిలబడుతుంది.',
      kn: 'ನಿಮ್ಮದು ಆಳವಾದ ಬೇರುಗಳು ಮತ್ತು ಎತ್ತರದ ವಂಶವಿರುವ ಕುಟುಂಬ.\nಪ್ರತಿ ಪೀಳಿಗೆ ಹಿಂದಿನ ಪೀಳಿಗೆಯ ಭುಜದ ಮೇಲೆ ನಿಲ್ಲುತ್ತದೆ.',
      ml: 'നിങ്ങളുടേത് ആഴമേറിയ വേരുകളും ഉയർന്ന വംശവുമുള്ള കുടുംബം.\nഓരോ തലമുറയും മുൻ തലമുറയുടെ ചുമലിൽ നിൽക്കുന്നു.',
      mr: 'तुमचे खोल मुळे आणि उंच वंश असलेले कुटुंब आहे.\nप्रत्येक पिढी मागच्या पिढीच्या खांद्यावर उभी आहे.',
      bn: 'তোমার পরিবার গভীর শিকড় এবং দীর্ঘ বংশের।\nপ্রতিটি প্রজন্ম আগের প্রজন্মের কাঁধে দাঁড়িয়ে আছে।',
    },
  },
  {
    key: 'lotus',
    glyphStyle: 'lotus_petal',
    weight: 2,
    thresholds: {
      minClusteringCoefficient: 0.25,
      maxClusteringCoefficient: 0.4,
    },
    names: {
      en: 'The Lotus',
      hi: 'कमल',
      ta: 'தாமரை',
      te: 'తామర',
      kn: 'ಕಮಲ',
      ml: 'താമര',
      mr: 'कमळ',
      bn: 'পদ্ম',
    },
    descriptions: {
      en: 'A strong center holds, while new petals are still unfolding.\nYour family is becoming — not yet complete, and more beautiful for it.',
      hi: 'एक मजबूत केंद्र टिका है, जबकि नई पंखुड़ियाँ अभी खुल रही हैं।\nतुम्हारा परिवार बन रहा है — अभी पूरा नहीं, और इसीलिए और सुंदर।',
      ta: 'ஒரு வலுவான மையம் நிற்கிறது, புதிய இதழ்கள் இன்னும் விரிகின்றன.\nஉங்கள் குடும்பம் தயாராகி வருகிறது — இன்னும் முழுமையடையவில்லை, அதனால் இன்னும் அழகு.',
      te: 'బలమైన కేంద్రం నిలబడుతుంది, కొత్త రేకులు ఇంకా విచ్చుకుంటున్నాయి.\nమీ కుటుంబం రూపొందుతోంది — ఇంకా పూర్తి కాలేదు, అందుకే మరింత అందంగా ఉంది.',
      kn: 'ಒಂದು ಬಲವಾದ ಕೇಂದ್ರ ನಿಲ್ಲುತ್ತದೆ, ಹೊಸ ದಳಗಳು ಇನ್ನೂ ತೆರೆದುಕೊಳ್ಳುತ್ತಿವೆ.\nನಿಮ್ಮ ಕುಟುಂಬ ರೂಪುಗೊಳ್ಳುತ್ತಿದೆ — ಇನ್ನೂ ಪೂರ್ಣವಾಗಿಲ್ಲ, ಆದ್ದರಿಂದ ಇನ್ನಷ್ಟು ಸುಂದರ.',
      ml: 'ഒരു ശക്തമായ കേന്ദ്രം നിൽക്കുന്നു, പുതിയ ഇതളുകൾ ഇനിയും വിടരുന്നു.\nനിങ്ങളുടെ കുടുംബം രൂപപ്പെട്ടുകൊണ്ടിരിക്കുന്നു — ഇതേ പൂർണ്ണമായിട്ടില്ല, അതുകൊണ്ടാണ് കൂടുതൽ മനോഹരം.',
      mr: 'एक मजबूत केंद्र टिकते, नवीन पाकळ्या अजून उलगडत आहेत.\nतुमचे कुटुंब तयार होत आहे — अजून पूर्ण नाही, आणि म्हणून अधिक सुंदर.',
      bn: 'একটি শক্তিশালী কেন্দ্র ধরে আছে, নতুন পাপড়ি এখনও মেলছে।\nতোমার পরিবার তৈরি হচ্ছে — এখনও সম্পূর্ণ নয়, তাই আরও সুন্দর।',
    },
  },
  {
    key: 'forest',
    glyphStyle: 'distributed_nodes',
    weight: 1,
    thresholds: {}, // Fallback archetype — matches when no other archetype's thresholds are met
    names: {
      en: 'The Forest',
      hi: 'वन',
      ta: 'காடு',
      te: 'అడవి',
      kn: 'ಅರಣ್ಯ',
      ml: 'കാട്',
      mr: 'वन',
      bn: 'বন',
    },
    descriptions: {
      en: 'Many trees, each strong in their own right.\nYour family needs no single center — you are strongest together.',
      hi: 'कई पेड़, हर एक अपने दम पर मजबूत।\nतुम्हारे परिवार को किसी एक केंद्र की जरूरत नहीं — तुम मिलकर सबसे मजबूत हो।',
      ta: 'பல மரங்கள், ஒவ்வொன்றும் தன் வலிமையில் உறுதியாக.\nஉங்கள் குடும்பத்திற்கு ஒரே மையம் தேவையில்லை — நீங்கள் இணைந்திருக்கும்போது மிகவும் வலிமையானவர்கள்.',
      te: 'అనేక చెట్లు, ప్రతి ఒక్కటి దాని స్వంత శక్తిలో బలంగా.\nమీ కుటుంబానికి ఒకే కేంద్రం అవసరం లేదు — మీరు కలిసి బలంగా ఉన్నారు.',
      kn: 'ಅನೇಕ ಮರಗಳು, ಪ್ರತಿಯೊಂದೂ ತಮ್ಮ ಶಕ್ತಿಯಲ್ಲಿ ಗಟ್ಟಿಯಾಗಿ.\nನಿಮ್ಮ ಕುಟುಂಬಕ್ಕೆ ಒಂದೇ ಕೇಂದ್ರದ ಅಗತ್ಯವಿಲ್ಲ — ನೀವು ಒಟ್ಟಿಗೆ ಅತ್ಯಂತ ಶಕ್ತಿಶಾಲಿ.',
      ml: 'പല മരങ്ങൾ, ഓരോന്നും അതിന്റേതായ ശക്തിയിൽ ഉറച്ചുനിൽക്കുന്നു.\nനിങ്ങളുടെ കുടുംബത്തിന് ഒരു കേന്ദ്രം ആവശ്യമില്ല — ഒന്നിച്ചിരിക്കുമ്പോൾ നിങ്ങൾ ഏറ്റവും ശക്തർ.',
      mr: 'अनेक झाडे, प्रत्येक आपल्या शक्तीत मजबूत.\nतुमच्या कुटुंबाला एकाच केंद्राची गरज नाही — तुम्ही एकत्र सर्वात मजबूत आहात.',
      bn: 'অনেক গাছ, প্রতিটি নিজের শক্তিতে শক্তিশালী।\nতোমার পরিবারের একটি মাত্র কেন্দ্রের দরকার নেই — একসাথে তুমি সবচেয়ে শক্তিশালী।',
    },
  },
];

// ─────────────────────────────────────────────────────────────────────────
// CLASSIFIER SERVICE
// ─────────────────────────────────────────────────────────────────────────

export class ArchetypeClassifierService {
  // Max possible score = the highest number of thresholds any archetype has.
  // Used to normalize the confidence gap. Set to 6 as a safe upper bound
  // (no archetype currently has more than 2 thresholds, but the constant
  // preserves the guide's formula verbatim).
  private static readonly MAX_POSSIBLE_SCORE = 6;

  classify(metrics: GraphMetrics): ClassificationResult {
    // Score each archetype against the metrics
    const scored = ARCHETYPES.map((archetype) => {
      const { score, checksPassed, checksTotal } = this.scoreArchetype(archetype, metrics);
      return {
        archetype,
        score,
        weight: archetype.weight,
        checksPassed,
        checksTotal,
      };
    });

    // Sort by score desc, then by weight desc for tie-breaking
    scored.sort((a, b) =>
      b.score !== a.score
        ? b.score - a.score
        : b.archetype.weight - a.archetype.weight,
    );

    const winner = scored[0];
    const runnerUp = scored[1];

    // Confidence = gap between winner and runner-up scores, normalized
    const confidence = Math.min(
      1.0,
      0.5 + (winner.score - runnerUp.score) / (2 * ArchetypeClassifierService.MAX_POSSIBLE_SCORE),
    );

    return {
      archetypeKey: winner.archetype.key,
      confidence,
      definition: winner.archetype,
      scores: scored.map((s) => ({
        key: s.archetype.key,
        score: s.score,
        weight: s.archetype.weight,
        checksPassed: s.checksPassed,
        checksTotal: s.checksTotal,
      })),
    };
  }

  private scoreArchetype(
    archetype: ArchetypeDefinition,
    metrics: GraphMetrics,
  ): { score: number; checksPassed: number; checksTotal: number } {
    const t = archetype.thresholds;
    let score = 0;
    let checksPassed = 0;
    let checksTotal = 0;

    if (t.minClusteringCoefficient !== undefined) {
      checksTotal++;
      if (metrics.clusteringCoefficient >= t.minClusteringCoefficient) {
        score++;
        checksPassed++;
      }
    }
    if (t.maxClusteringCoefficient !== undefined) {
      checksTotal++;
      if (metrics.clusteringCoefficient <= t.maxClusteringCoefficient) {
        score++;
        checksPassed++;
      }
    }
    if (t.minGenerationDepth !== undefined) {
      checksTotal++;
      if (metrics.generationDepth >= t.minGenerationDepth) {
        score++;
        checksPassed++;
      }
    }
    if (t.maxGenerationDepth !== undefined) {
      checksTotal++;
      if (metrics.generationDepth <= t.maxGenerationDepth) {
        score++;
        checksPassed++;
      }
    }
    if (t.minDistinctLineages !== undefined) {
      checksTotal++;
      if (metrics.distinctLineages >= t.minDistinctLineages) {
        score++;
        checksPassed++;
      }
    }
    if (t.maxDistinctLineages !== undefined) {
      checksTotal++;
      if (metrics.distinctLineages <= t.maxDistinctLineages) {
        score++;
        checksPassed++;
      }
    }
    if (t.minGraphDiameter !== undefined) {
      checksTotal++;
      if (metrics.graphDiameter >= t.minGraphDiameter) {
        score++;
        checksPassed++;
      }
    }
    if (t.maxAvgDegree !== undefined) {
      checksTotal++;
      if (metrics.avgDegree <= t.maxAvgDegree) {
        score++;
        checksPassed++;
      }
    }
    if (t.minAvgDegree !== undefined) {
      checksTotal++;
      if (metrics.avgDegree >= t.minAvgDegree) {
        score++;
        checksPassed++;
      }
    }

    // Forest is the fallback — always scores 0.5 so it wins only when
    // nothing else has score > 0.5
    if (checksTotal === 0) {
      return { score: 0.5, checksPassed: 0, checksTotal: 0 };
    }
    return { score, checksPassed, checksTotal };
  }

  getDefinition(key: ArchetypeKey): ArchetypeDefinition {
    return ARCHETYPES.find((a) => a.key === key) ?? ARCHETYPES[4]; // lotus fallback
  }
}
