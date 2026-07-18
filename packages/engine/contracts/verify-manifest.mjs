#!/usr/bin/env node
// packages/engine/contracts/verify-manifest.mjs
//
// Zero-dependency drift check for the contract kit (WP-07). Recomputes every
// digest recorded in MANIFEST.md against BOTH the contracts/ copy and the
// original in-repo source, prints per-entry OK/DRIFT, and exits 1 on any
// mismatch. Uses only node:crypto + node:fs + node:path + node:url (all
// built-in) so it runs before `npm install` in this workspace, including in
// CI's earliest steps.
//
// Run: node packages/engine/contracts/verify-manifest.mjs
//
// FILE_ENTRIES and DIR_ENTRIES below are the single source of truth for the
// contract kit's expected content; MANIFEST.md's table is generated from the
// same data and must be kept in sync by hand when entries change (add a new
// contract file -> add it here -> re-run to regenerate the expected digest ->
// update MANIFEST.md's table to match).

import { createHash } from 'node:crypto';
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const CONTRACTS_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(CONTRACTS_DIR, '..', '..', '..');

// Strip CR (0x0D) bytes before hashing so CRLF-vs-LF representation never
// affects a digest. Root cause (CI run 29629259173, ubuntu-latest +
// macos-latest only): fixtures/golden-scorer/09-cross-ai-rubber-stamp and
// 10-cross-ai-genuine-bounce are the only manifest entries containing *.txt
// fixture files, which .gitattributes leaves on the generic `* text=auto`
// rule (unlike the .md/.json/.yaml entries elsewhere here, all pinned
// `eol=lf`). Windows checkouts smudge those LF-stored blobs to CRLF on disk
// via core.autocrlf; POSIX checkout runners do not. Source and its
// contracts/ copy always agree with EACH OTHER on a given platform -- the
// false DRIFT was this manifest's expected digest, captured on Windows,
// disagreeing with what POSIX runners compute for the very same (unchanged)
// blobs. This kit's job is CONTENT drift detection; EOL fidelity belongs to
// git's own filters/.gitattributes, so both hashing paths below (per-file
// sha256, and the aggregate directory digest built from these same per-file
// hashes) hash CR-stripped bytes.
function stripCR(buf) {
  const out = Buffer.allocUnsafe(buf.length);
  let j = 0;
  for (let i = 0; i < buf.length; i++) {
    if (buf[i] !== 0x0d) out[j++] = buf[i];
  }
  return out.subarray(0, j);
}

function sha256File(absPath) {
  return createHash('sha256').update(stripCR(readFileSync(absPath))).digest('hex');
}

// Recursively lists files under absDir as relative POSIX-style paths, sorted
// lexically. Sort is on the relative path string so the result is stable
// regardless of filesystem enumeration order or platform.
function listFilesRecursive(absDir) {
  const out = [];
  function walk(dir, relPrefix) {
    for (const entry of readdirSync(dir).sort()) {
      const abs = path.join(dir, entry);
      const rel = relPrefix ? `${relPrefix}/${entry}` : entry;
      const st = statSync(abs);
      if (st.isDirectory()) walk(abs, rel);
      else out.push(rel);
    }
  }
  walk(absDir, '');
  return out.sort();
}

// One aggregate digest for an entire directory tree: hash every file, sort
// by relative path, format each as "<sha256>  <relpath>\n", concatenate, hash
// the concatenation. Matches the recipe documented in MANIFEST.md.
function aggregateDigest(absDir) {
  const relFiles = listFilesRecursive(absDir);
  const lines = relFiles.map((rel) => `${sha256File(path.join(absDir, rel))}  ${rel}\n`);
  const blob = lines.join('');
  return { digest: createHash('sha256').update(blob, 'utf8').digest('hex'), fileCount: relFiles.length };
}

const FILE_ENTRIES = [
  {
    "source": "agent-bouncer/templates/bounce-protocol.md",
    "dest": "templates/agent-bouncer/bounce-protocol.md",
    "sha256": "5920b293a7ba0441f13998161e8b0c677eeb9be0f85e05a57355ff1fa9270bf9"
  },
  {
    "source": "agent-bouncer/templates/role-composer.md",
    "dest": "templates/agent-bouncer/role-composer.md",
    "sha256": "eefbb6d532e7a0d11f558f7e01d8f72557f9f62e5b172a621135434a21001468"
  },
  {
    "source": "agent-bouncer/templates/role-reviewer.md",
    "dest": "templates/agent-bouncer/role-reviewer.md",
    "sha256": "2e7441b27d5af317b30aca358b37653a9f062665c52a172c8cf537160f4c967e"
  },
  {
    "source": "templates/co-evolve/adjudicate.md",
    "dest": "templates/co-evolve/adjudicate.md",
    "sha256": "cd64f5281f4f4b786d08392875d0cb6c67904f98d922e216b2fd089f20fe280a"
  },
  {
    "source": "templates/co-evolve/chain-critique-adversarial.md",
    "dest": "templates/co-evolve/chain-critique-adversarial.md",
    "sha256": "9691fcceee38266b4d1ed343baa919017b8044c8939a92490e77bffb85ecc398"
  },
  {
    "source": "templates/co-evolve/chain-critique.md",
    "dest": "templates/co-evolve/chain-critique.md",
    "sha256": "4d402bdc0c83bd9b918f1ca4871607f593d74d7b451c8c0036b1030e49f695da"
  },
  {
    "source": "templates/co-evolve/chain-defend.md",
    "dest": "templates/co-evolve/chain-defend.md",
    "sha256": "5e561aca7b0e954e00c7128e45fe6f56f07191d9cb63763cd4c87081969faff5"
  },
  {
    "source": "templates/co-evolve/chain-tighten.md",
    "dest": "templates/co-evolve/chain-tighten.md",
    "sha256": "efacc284ef0c1119e47e04198d1b65cb6e3eb2289a700e262134b46951a40fa6"
  },
  {
    "source": "templates/co-evolve/role-composer-light.md",
    "dest": "templates/co-evolve/role-composer-light.md",
    "sha256": "fe0ef319323caef4038a5404d9f3ed64577b26344c235d546cfa6d2dcc78edb4"
  },
  {
    "source": "templates/co-evolve/role-reviewer-adversarial.md",
    "dest": "templates/co-evolve/role-reviewer-adversarial.md",
    "sha256": "2c0264621b18dd2f8479bc3e153651ddc2362b19a4b98dfae2afdeb48eaf61dd"
  },
  {
    "source": "templates/co-evolve/role-reviewer-light.md",
    "dest": "templates/co-evolve/role-reviewer-light.md",
    "sha256": "fb76e68386f31169d335db645f726cbf83abb522171c706a0b428afb0e686c6b"
  },
  {
    "source": "skills/dev-review/templates/bounce-prompt-portable.md",
    "dest": "templates/dev-review/bounce-prompt-portable.md",
    "sha256": "8f98814695d08d8ae9d1054ae1adafc9bad45fafbcdd06c932f0d4a1244407d2"
  },
  {
    "source": "skills/dev-review/templates/bounce-protocol.md",
    "dest": "templates/dev-review/bounce-protocol.md",
    "sha256": "5920b293a7ba0441f13998161e8b0c677eeb9be0f85e05a57355ff1fa9270bf9"
  },
  {
    "source": "skills/dev-review/templates/dev-prompt-codex.md",
    "dest": "templates/dev-review/dev-prompt-codex.md",
    "sha256": "0b493742a0157ce3321f825c51c2e9adbbba1124cbe4bd5659eafdb0cfa266c5"
  },
  {
    "source": "skills/dev-review/templates/dev-prompt-opus.md",
    "dest": "templates/dev-review/dev-prompt-opus.md",
    "sha256": "0ffc180a54ffa38715e9e374ed89e634f4504d42d4be77557e1857eaf62ad306"
  },
  {
    "source": "skills/dev-review/templates/review-prompt-codex.md",
    "dest": "templates/dev-review/review-prompt-codex.md",
    "sha256": "f5d24f7a259e0f4113416d89f1c851f3e42cf6a0af77256694e25c6946416be4"
  },
  {
    "source": "skills/dev-review/templates/review-prompt-opus.md",
    "dest": "templates/dev-review/review-prompt-opus.md",
    "sha256": "f47bd58235c255380bb8bbf733b6a4f92e590df3fa5760d25fd123020785379d"
  },
  {
    "source": "skills/dev-review/schemas/review-verdict.json",
    "dest": "schemas/review-verdict.json",
    "sha256": "6bd9d58c7fb85190bd0a5cbd4879bcef0906d6d9ca3cfee6c32c328039527c26"
  },
  {
    "source": "evals/RUNNER-CONTRACT.md",
    "dest": "runner-contracts/RUNNER-CONTRACT.md",
    "sha256": "13209382457ca4b1e856da4c4d43259988a7fb56b8201a5b8657e695cbf909a4"
  },
  {
    "source": "evals/BOUNCE-RUNNER-CONTRACT.md",
    "dest": "runner-contracts/BOUNCE-RUNNER-CONTRACT.md",
    "sha256": "d236967accd8b1f2a792a0d410770e3dd00b94354643ac89206b818ad31d1b5e"
  },
  {
    "source": "evals/bounce-thresholds.yaml",
    "dest": "thresholds/bounce-thresholds.yaml",
    "sha256": "1de3404cd66964320bfc1de0e5aeb81c5f05fc4dfa58007b184b36e81f23d5da"
  },
  {
    "source": "evals/cases/01-trivial-task.yaml",
    "dest": "fixtures/cases/01-trivial-task.yaml",
    "sha256": "95a099336221d1741972a2618ec4e4b35152e37064ec00042dc07247fc34e2d9"
  },
  {
    "source": "evals/cases/02-simple-md-edit.yaml",
    "dest": "fixtures/cases/02-simple-md-edit.yaml",
    "sha256": "f00ade73c940908a31b4fdfa004de17a29d29cf05cc6e10544220747281391e7"
  },
  {
    "source": "evals/cases/03-contested-decision.yaml",
    "dest": "fixtures/cases/03-contested-decision.yaml",
    "sha256": "1d6ea064244cd93846c7650d012f672e78e77540cc5a61aeda85a72317258340"
  },
  {
    "source": "evals/cases/04-hallucination-trap.yaml",
    "dest": "fixtures/cases/04-hallucination-trap.yaml",
    "sha256": "e4407b7f906a06bd73b8db8f594baddb7f01e18f5f43e3cf3278da44c0c42545"
  },
  {
    "source": "evals/cases/05-ambiguous-task.yaml",
    "dest": "fixtures/cases/05-ambiguous-task.yaml",
    "sha256": "0f4abdbdffa8eb181a398a6aba69b7fd3758e4d988904e28ee19df60048cc7ec"
  },
  {
    "source": "evals/cases/06-multi-file-refactor.yaml",
    "dest": "fixtures/cases/06-multi-file-refactor.yaml",
    "sha256": "3135155f84d1f3ca8a99da2c6ef9d84458c1b984730d1e1282294ede66a6c989"
  },
  {
    "source": "evals/cases/07-real-doc-bounce.yaml",
    "dest": "fixtures/cases/07-real-doc-bounce.yaml",
    "sha256": "ee510539bacff3742d7f5dc84498434b40aee1c5744a940463d503c88870424e"
  },
  {
    "source": "evals/cases/08-real-code-refactor.yaml",
    "dest": "fixtures/cases/08-real-code-refactor.yaml",
    "sha256": "3f53da95711d0dcdb6633b6d9e67d7f0c8a57438dd319ff39ca31e965af83cc0"
  },
  {
    "source": "evals/cases/09-real-python-refactor.yaml",
    "dest": "fixtures/cases/09-real-python-refactor.yaml",
    "sha256": "f289bfaa101a906e30857d69c0c9a82d42b6cdf6dd1fa6db06afa5b0838bbc4c"
  },
  {
    "source": "evals/cases/defaults.yaml",
    "dest": "fixtures/cases/defaults.yaml",
    "sha256": "446f2358e928b4e3c4d296d9874b28ad939d71ef13011129aca72add780272a5"
  }
];

const DIR_ENTRIES = [
  {
    "source": "evals/tests/fixtures/bounce-runs/deleted-with-section",
    "dest": "fixtures/bounce-runs/deleted-with-section",
    "sha256": "b6f1f109411b5f3f12b56c2dc91492e29f1b4a2a0ac300c18780d3d7ac18a5d5",
    "fileCount": 6
  },
  {
    "source": "evals/tests/fixtures/bounce-runs/expired-at-final",
    "dest": "fixtures/bounce-runs/expired-at-final",
    "sha256": "535d3b5a03f13f817be014d62a8a0b2441226bfcc320969db3e241b805139dff",
    "fileCount": 7
  },
  {
    "source": "evals/tests/fixtures/bounce-runs/resolved-with-edit",
    "dest": "fixtures/bounce-runs/resolved-with-edit",
    "sha256": "58bf32bcb4918b6257011ad3df7677e7c480dd411e0a9a7f82704aa0e4b865cd",
    "fileCount": 6
  },
  {
    "source": "evals/tests/fixtures/bounce-runs/rubber-stamp",
    "dest": "fixtures/bounce-runs/rubber-stamp",
    "sha256": "5eb30a24dd1fda0a9dd26d91314a1189d4dbfd7f4c2007c1a67b230abcace6a6",
    "fileCount": 6
  },
  {
    "source": "runners/codex-ps/evals/tests/fixtures/01-all-pass",
    "dest": "fixtures/golden-scorer/01-all-pass",
    "sha256": "4a8c891ecc556bab1c48f5e148b41c16e926cee3a50863fb21fdfcb78854fc29",
    "fileCount": 6
  },
  {
    "source": "runners/codex-ps/evals/tests/fixtures/02-robustness-fail",
    "dest": "fixtures/golden-scorer/02-robustness-fail",
    "sha256": "85e8464aa4396b27653f9ade7614f01224ea07cf3e3c79e0ad6296e7817dce40",
    "fileCount": 5
  },
  {
    "source": "runners/codex-ps/evals/tests/fixtures/03-convergence-partial",
    "dest": "fixtures/golden-scorer/03-convergence-partial",
    "sha256": "3102e9d810c15b98705a9cd20a88a433d6e3854760aa379018ed90f2aed3e05f",
    "fileCount": 6
  },
  {
    "source": "runners/codex-ps/evals/tests/fixtures/04-plan-quality-fail",
    "dest": "fixtures/golden-scorer/04-plan-quality-fail",
    "sha256": "abee4ed1fada187c388cafa46872dc3a458110d88bed1adcdff5e3b0b0d76427",
    "fileCount": 6
  },
  {
    "source": "runners/codex-ps/evals/tests/fixtures/05-exec-fidelity-mismatch",
    "dest": "fixtures/golden-scorer/05-exec-fidelity-mismatch",
    "sha256": "b172f3e732f7b23b55437a078af14f59d8a10c02191147cce66dfab52f30e21f",
    "fileCount": 6
  },
  {
    "source": "runners/codex-ps/evals/tests/fixtures/06-verify-catches-hallucination",
    "dest": "fixtures/golden-scorer/06-verify-catches-hallucination",
    "sha256": "ea81613e43892b380310a83d435c9e6f314858c1e57767f643428c3ccc27d7c5",
    "fileCount": 6
  },
  {
    "source": "runners/codex-ps/evals/tests/fixtures/07-verify-misses-hallucination",
    "dest": "fixtures/golden-scorer/07-verify-misses-hallucination",
    "sha256": "dba36acbe457c70256594c7538038b1cb51a200094126e16ee8e308621ff610c",
    "fileCount": 6
  },
  {
    "source": "runners/codex-ps/evals/tests/fixtures/08-unparseable-verdict",
    "dest": "fixtures/golden-scorer/08-unparseable-verdict",
    "sha256": "8ee7b1c0a86df0bb012919d0fe1de73ef28f1b6993daaebe55cf43ef8786651d",
    "fileCount": 6
  },
  {
    "source": "runners/codex-ps/evals/tests/fixtures/09-cross-ai-rubber-stamp",
    "dest": "fixtures/golden-scorer/09-cross-ai-rubber-stamp",
    "sha256": "095260f9c509ff608814949daccbc0160470e34ee0595b4b30fb1240c57fdcbe",
    "fileCount": 8
  },
  {
    "source": "runners/codex-ps/evals/tests/fixtures/10-cross-ai-genuine-bounce",
    "dest": "fixtures/golden-scorer/10-cross-ai-genuine-bounce",
    "sha256": "6040da15b459420a8bbb6231072f7ecee2bb262ead17622d8235b8a25369cecf",
    "fileCount": 8
  }
];

let failures = 0;
let checked = 0;

console.log('Contract kit manifest verification (WP-07)');
console.log(`  contracts dir: ${CONTRACTS_DIR}`);
console.log(`  repo root:     ${REPO_ROOT}`);
console.log('');

for (const entry of FILE_ENTRIES) {
  checked += 1;
  const srcAbs = path.join(REPO_ROOT, entry.source);
  const dstAbs = path.join(CONTRACTS_DIR, entry.dest);

  const missing = [];
  if (!existsSync(srcAbs)) missing.push(`source missing: ${entry.source}`);
  if (!existsSync(dstAbs)) missing.push(`dest missing: ${entry.dest}`);
  if (missing.length > 0) {
    failures += 1;
    console.log(`DRIFT  ${entry.dest}`);
    for (const m of missing) console.log(`       ${m}`);
    continue;
  }

  const srcHash = sha256File(srcAbs);
  const dstHash = sha256File(dstAbs);
  const ok = srcHash === dstHash && srcHash === entry.sha256;

  if (ok) {
    console.log(`OK     ${entry.dest}`);
  } else {
    failures += 1;
    console.log(`DRIFT  ${entry.dest}`);
    console.log(`       manifest expected: ${entry.sha256}`);
    console.log(`       source  ${entry.source}: ${srcHash}`);
    console.log(`       dest    ${entry.dest}: ${dstHash}`);
  }
}

for (const entry of DIR_ENTRIES) {
  checked += 1;
  const srcAbs = path.join(REPO_ROOT, entry.source);
  const dstAbs = path.join(CONTRACTS_DIR, entry.dest);

  const missing = [];
  if (!existsSync(srcAbs)) missing.push(`source dir missing: ${entry.source}`);
  if (!existsSync(dstAbs)) missing.push(`dest dir missing: ${entry.dest}`);
  if (missing.length > 0) {
    failures += 1;
    console.log(`DRIFT  ${entry.dest}/`);
    for (const m of missing) console.log(`       ${m}`);
    continue;
  }

  const src = aggregateDigest(srcAbs);
  const dst = aggregateDigest(dstAbs);
  const ok =
    src.digest === dst.digest &&
    src.digest === entry.sha256 &&
    src.fileCount === entry.fileCount &&
    dst.fileCount === entry.fileCount;

  if (ok) {
    console.log(`OK     ${entry.dest}/  (files=${dst.fileCount})`);
  } else {
    failures += 1;
    console.log(`DRIFT  ${entry.dest}/`);
    console.log(`       manifest expected: ${entry.sha256}  (files=${entry.fileCount})`);
    console.log(`       source  ${entry.source}: ${src.digest}  (files=${src.fileCount})`);
    console.log(`       dest    ${entry.dest}: ${dst.digest}  (files=${dst.fileCount})`);
  }
}

console.log('');
console.log(`${checked} entries checked, ${failures} drift${failures === 1 ? '' : 's'}`);

if (failures > 0) {
  console.error(`FAIL: ${failures} of ${checked} manifest entries drifted (see DRIFT lines above).`);
  process.exit(1);
}

console.log('All manifest entries verified OK.');
