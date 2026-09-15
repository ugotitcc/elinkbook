import fs from 'node:fs';
import path from 'node:path';
import OpenCC from 'opencc-js';

const s2twp = OpenCC.Converter({ from: 'cn', to: 'twp' });
const tw2s = OpenCC.Converter({ from: 'tw', to: 'cn' });
const tw2sp = OpenCC.Converter({ from: 'twp', to: 'cn' });
const s2t = OpenCC.Converter({ from: 'cn', to: 't' });
const t2s = OpenCC.Converter({ from: 't', to: 'cn' });

const dictModules = [
  'STCharacters', 'STPhrases', 'STPhrases_GeneratedFromRegionalPhrases',
  'TSCharacters', 'TSPhrases',
  'TWPhrases', 'TWPhrasesRev',
  'TWVariants', 'TWVariantsPhrases', 'TWVariantsRev', 'TWVariantsRevPhrases'
];

async function loadDicts() {
  const dictData = {};
  for (const name of dictModules) {
    const mod = await import('./node_modules/opencc-js/dist/esm-lib/dict/' + name + '.js');
    const raw = mod.default;
    const pairs = [];
    if (typeof raw === 'string') {
      for (const line of raw.split('|')) {
        if (!line) continue;
        const [k, v] = line.split(' ');
        if (k && v) pairs.push([k, v]);
      }
    }
    dictData[name] = pairs;
  }
  return dictData;
}

async function main() {
  const dicts = await loadDicts();

  console.log('Dictionaries loaded:');
  for (const [k, v] of Object.entries(dicts)) {
    console.log(`  ${k}: ${v.length} entries`);
  }

  // 1. Specific Analysis of TWPhrases (台灣常用詞：簡體/繁體 -> 台灣用語)
  console.log('\n============================================================');
  console.log('1. TWPhrases (台灣常用詞) in s2twp');
  console.log('============================================================');
  
  const twpResults = [];
  let twpUtf16Changed = 0;
  let twpCpChangedUtf16Same = 0;
  let twpCompletelySame = 0;
  let twpUtf16Inc = 0;
  let twpUtf16Dec = 0;
  const twpCategories = {};

  for (const [tradKey, target] of dicts.TWPhrases) {
    const simpKey = t2s(tradKey);
    // Effective output when fed simplified word
    const effOut = s2twp(simpKey);

    const inU16 = simpKey.length;
    const outU16 = effOut.length;
    const diffU16 = outU16 - inU16;

    const inCP = [...simpKey].length;
    const outCP = [...effOut].length;
    const diffCP = outCP - inCP;

    const record = {
      tradKey,
      simpKey,
      target,
      effOut,
      inU16,
      outU16,
      diffU16,
      inCP,
      outCP,
      diffCP,
      cat: `${inU16}→${outU16}`
    };
    twpResults.push(record);

    if (diffU16 !== 0) {
      twpUtf16Changed++;
      if (diffU16 > 0) twpUtf16Inc++; else twpUtf16Dec++;
      twpCategories[record.cat] = (twpCategories[record.cat] || 0) + 1;
    } else if (diffCP !== 0) {
      twpCpChangedUtf16Same++;
    } else {
      twpCompletelySame++;
    }
  }

  console.log(`Total TWPhrases: ${dicts.TWPhrases.length}`);
  console.log(`🔴 UTF-16 Changed: ${twpUtf16Changed} (${(twpUtf16Changed / dicts.TWPhrases.length * 100).toFixed(2)}%)`);
  console.log(`   Increased (+): ${twpUtf16Inc}`);
  console.log(`   Decreased (-): ${twpUtf16Dec}`);
  console.log(`   Length change categories:`, twpCategories);
  console.log(`🟡 CP Changed, UTF-16 Same: ${twpCpChangedUtf16Same}`);
  console.log(`🟢 Completely Same: ${twpCompletelySame} (${(twpCompletelySame / dicts.TWPhrases.length * 100).toFixed(2)}%)`);

  // 2. Specific Analysis of TWPhrasesRev (台灣常用詞 -> 大陸詞彙，用於 tw2sp)
  console.log('\n============================================================');
  console.log('2. TWPhrasesRev (台灣用語 -> 大陸用語) in tw2sp');
  console.log('============================================================');
  
  const twpRevResults = [];
  let twpRevUtf16Changed = 0;
  let twpRevCpChangedUtf16Same = 0;
  let twpRevCompletelySame = 0;
  let twpRevUtf16Inc = 0;
  let twpRevUtf16Dec = 0;
  const twpRevCategories = {};

  for (const [twKey, target] of dicts.TWPhrasesRev) {
    const effOut = tw2sp(twKey);

    const inU16 = twKey.length;
    const outU16 = effOut.length;
    const diffU16 = outU16 - inU16;

    const inCP = [...twKey].length;
    const outCP = [...effOut].length;
    const diffCP = outCP - inCP;

    const record = {
      twKey,
      target,
      effOut,
      inU16,
      outU16,
      diffU16,
      inCP,
      outCP,
      diffCP,
      cat: `${inU16}→${outU16}`
    };
    twpRevResults.push(record);

    if (diffU16 !== 0) {
      twpRevUtf16Changed++;
      if (diffU16 > 0) twpRevUtf16Inc++; else twpRevUtf16Dec++;
      twpRevCategories[record.cat] = (twpRevCategories[record.cat] || 0) + 1;
    } else if (diffCP !== 0) {
      twpRevCpChangedUtf16Same++;
    } else {
      twpRevCompletelySame++;
    }
  }

  console.log(`Total TWPhrasesRev: ${dicts.TWPhrasesRev.length}`);
  console.log(`🔴 UTF-16 Changed: ${twpRevUtf16Changed} (${(twpRevUtf16Changed / dicts.TWPhrasesRev.length * 100).toFixed(2)}%)`);
  console.log(`   Increased (+): ${twpRevUtf16Inc}`);
  console.log(`   Decreased (-): ${twpRevUtf16Dec}`);
  console.log(`   Length change categories:`, twpRevCategories);
  console.log(`🟡 CP Changed, UTF-16 Same: ${twpRevCpChangedUtf16Same}`);
  console.log(`🟢 Completely Same: ${twpRevCompletelySame} (${(twpRevCompletelySame / dicts.TWPhrasesRev.length * 100).toFixed(2)}%)`);

  // 3. Full Scope Analysis: s2twp (All characters + phrases)
  console.log('\n============================================================');
  console.log('3. Full s2twp Pipeline (All 54,506 vocabulary entries)');
  console.log('============================================================');
  
  const allS2twpInputs = new Map(); // word -> source
  for (const [k] of dicts.STPhrases) allS2twpInputs.set(k, 'STPhrases');
  for (const [k] of dicts.STPhrases_GeneratedFromRegionalPhrases) allS2twpInputs.set(k, 'STPhrases_Regional');
  for (const [k] of dicts.STCharacters) allS2twpInputs.set(k, 'STCharacters');
  for (const [k] of dicts.TWPhrases) {
    allS2twpInputs.set(t2s(k), 'TWPhrases_Simp');
    allS2twpInputs.set(k, 'TWPhrases_Trad');
  }

  let fullS2twpU16Changed = 0;
  let fullS2twpCPChangedUtf16Same = 0;
  let fullS2twpSame = 0;
  let fullS2twpInc = 0;
  let fullS2twpDec = 0;
  const fullS2twpCategories = {};
  const s2twpSurrogateItems = [];
  const s2twpPhraseItems = [];

  for (const [word, source] of allS2twpInputs.entries()) {
    const effOut = s2twp(word);
    const inU16 = word.length;
    const outU16 = effOut.length;
    const diffU16 = outU16 - inU16;
    const inCP = [...word].length;
    const outCP = [...effOut].length;
    const diffCP = outCP - inCP;

    if (diffU16 !== 0) {
      fullS2twpU16Changed++;
      if (diffU16 > 0) fullS2twpInc++; else fullS2twpDec++;
      const cat = `${inU16}→${outU16}`;
      fullS2twpCategories[cat] = (fullS2twpCategories[cat] || 0) + 1;

      if (diffCP === 0) {
        // Surrogate pair case (Code point length unchanged, but UTF-16 changed!)
        s2twpSurrogateItems.push({ word, effOut, source, inU16, outU16, diffU16 });
      } else {
        // Word/phrase length difference (Characters added/removed)
        s2twpPhraseItems.push({ word, effOut, source, inU16, outU16, diffU16, inCP, outCP, diffCP });
      }
    } else if (diffCP !== 0) {
      fullS2twpCPChangedUtf16Same++;
    } else {
      fullS2twpSame++;
    }
  }

  const totalS2twp = allS2twpInputs.size;
  console.log(`Total inputs: ${totalS2twp}`);
  console.log(`🔴 UTF-16 Changed: ${fullS2twpU16Changed} (${(fullS2twpU16Changed / totalS2twp * 100).toFixed(3)}%)`);
  console.log(`   - Phrase length changed: ${s2twpPhraseItems.length} (${(s2twpPhraseItems.length / totalS2twp * 100).toFixed(3)}%)`);
  console.log(`   - Surrogate pair length changed (diffCP=0): ${s2twpSurrogateItems.length} (${(s2twpSurrogateItems.length / totalS2twp * 100).toFixed(3)}%)`);
  console.log(`   - Increased (+): ${fullS2twpInc}`);
  console.log(`   - Decreased (-): ${fullS2twpDec}`);
  console.log(`🟡 CP Changed, UTF-16 Same: ${fullS2twpCPChangedUtf16Same}`);
  console.log(`🟢 Completely Same: ${fullS2twpSame} (${(fullS2twpSame / totalS2twp * 100).toFixed(3)}%)`);

  // 4. Full Scope Analysis: tw2s (Taiwan Traditional to Simplified)
  console.log('\n============================================================');
  console.log('4. Full tw2s Pipeline (Taiwan Traditional -> Simplified)');
  console.log('============================================================');
  
  const allTw2sInputs = new Map();
  for (const [k] of dicts.TWVariantsRevPhrases) allTw2sInputs.set(k, 'TWVariantsRevPhrases');
  for (const [k] of dicts.TWVariantsRev) allTw2sInputs.set(k, 'TWVariantsRev');
  for (const [k] of dicts.TSPhrases) allTw2sInputs.set(k, 'TSPhrases');
  for (const [k] of dicts.TSCharacters) allTw2sInputs.set(k, 'TSCharacters');

  let fullTw2sU16Changed = 0;
  let fullTw2sCPChangedUtf16Same = 0;
  let fullTw2sSame = 0;
  let fullTw2sInc = 0;
  let fullTw2sDec = 0;
  const fullTw2sCategories = {};
  const tw2sSurrogateItems = [];
  const tw2sPhraseItems = [];

  for (const [word, source] of allTw2sInputs.entries()) {
    const effOut = tw2s(word);
    const inU16 = word.length;
    const outU16 = effOut.length;
    const diffU16 = outU16 - inU16;
    const inCP = [...word].length;
    const outCP = [...effOut].length;
    const diffCP = outCP - inCP;

    if (diffU16 !== 0) {
      fullTw2sU16Changed++;
      if (diffU16 > 0) fullTw2sInc++; else fullTw2sDec++;
      const cat = `${inU16}→${outU16}`;
      fullTw2sCategories[cat] = (fullTw2sCategories[cat] || 0) + 1;

      if (diffCP === 0) {
        tw2sSurrogateItems.push({ word, effOut, source, inU16, outU16, diffU16 });
      } else {
        tw2sPhraseItems.push({ word, effOut, source, inU16, outU16, diffU16, inCP, outCP, diffCP });
      }
    } else if (diffCP !== 0) {
      fullTw2sCPChangedUtf16Same++;
    } else {
      fullTw2sSame++;
    }
  }

  const totalTw2s = allTw2sInputs.size;
  console.log(`Total inputs: ${totalTw2s}`);
  console.log(`🔴 UTF-16 Changed: ${fullTw2sU16Changed} (${(fullTw2sU16Changed / totalTw2s * 100).toFixed(3)}%)`);
  console.log(`   - Phrase length changed: ${tw2sPhraseItems.length}`);
  console.log(`   - Surrogate pair length changed: ${tw2sSurrogateItems.length}`);
  console.log(`   - Increased (+): ${fullTw2sInc}`);
  console.log(`   - Decreased (-): ${fullTw2sDec}`);
  console.log(`   - Categories:`, fullTw2sCategories);
  console.log(`🟡 CP Changed, UTF-16 Same: ${fullTw2sCPChangedUtf16Same}`);
  console.log(`🟢 Completely Same: ${fullTw2sSame} (${(fullTw2sSame / totalTw2s * 100).toFixed(3)}%)`);

  // Write CSV of all TWPhrases that change length
  const csvHeaders = 'simpKey,tradKey,target,effOut,diffUtf16,diffCodePoints,lengthChangeType\n';
  const csvRows = twpResults
    .filter(r => r.diffU16 !== 0)
    .sort((a, b) => Math.abs(b.diffU16) - Math.abs(a.diffU16) || a.simpKey.localeCompare(b.simpKey))
    .map(r => `"${r.simpKey}","${r.tradKey}","${r.target}","${r.effOut}",${r.diffU16},${r.diffCP},"${r.cat}"`)
    .join('\n');
  fs.writeFileSync('opencc/OpenCC-TWPhrases-s2twp-LengthChanged.csv', csvHeaders + csvRows, 'utf8');
  console.log('\nWrote opencc/OpenCC-TWPhrases-s2twp-LengthChanged.csv');

  // Write CSV of all TWPhrasesRev that change length
  const csvRevRows = twpRevResults
    .filter(r => r.diffU16 !== 0)
    .sort((a, b) => Math.abs(b.diffU16) - Math.abs(a.diffU16) || a.twKey.localeCompare(b.twKey))
    .map(r => `"${r.twKey}","${r.target}","${r.effOut}",${r.diffU16},${r.diffCP},"${r.cat}"`)
    .join('\n');
  fs.writeFileSync('opencc/OpenCC-TWPhrasesRev-tw2sp-LengthChanged.csv', 'twKey,target,effOut,diffUtf16,diffCodePoints,lengthChangeType\n' + csvRevRows, 'utf8');
  console.log('Wrote opencc/OpenCC-TWPhrasesRev-tw2sp-LengthChanged.csv');
}

main().catch(console.error);
