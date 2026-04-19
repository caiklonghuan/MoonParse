#!/usr/bin/env node
/**
 * gen_grammar.js
 *
 * Converts moonbitlang/tree-sitter-moonbit/grammar.js to a MoonParse DSL string,
 * then writes it as a MoonBit source file.
 *
 * Usage:
 *   node gen_grammar.js                      # fetches grammar.js from GitHub
 *   node gen_grammar.js path/to/grammar.js   # uses local file
 *
 * Output: grammar_generated.mbt (in the parent directory)
 */

'use strict';

const fs = require('fs');
const vm = require('vm');
const path = require('path');
const https = require('https');

// ──────────────────────────────────────────────────────────────────────────────
// 1. Tree-sitter DSL mock
//    grammar.js uses these as globals (injected by tree-sitter CLI).
//    We provide our own versions that return plain JS objects for inspection.
// ──────────────────────────────────────────────────────────────────────────────

const mkSeq    = (...a) => ({ _t: 'SEQ',       members: a.flat(1) });
const mkChoice = (...a) => ({ _t: 'CHOICE',    members: a.flat(1) });
const mkRepeat  = (c)   => ({ _t: 'REPEAT',    c });
const mkRepeat1 = (c)   => ({ _t: 'REPEAT1',   c });
const mkOptional= (c)   => ({ _t: 'OPTIONAL',  c });
const mkBlank   = ()    => ({ _t: 'BLANK' });

const mkToken = (c) => ({ _t: 'TOKEN', c });
mkToken.immediate = (c) => ({ _t: 'TOKEN_IMMED', c });

// prec functions accept either (level, content) or just (content)
const _prec = (t) => (n, c) => c !== undefined
  ? { _t: t, n, c }
  : { _t: t, n: 0, c: n };  // single-arg form: prec.left(content)
const mkPrec = _prec('PREC');
mkPrec.left    = _prec('PREC_LEFT');
mkPrec.right   = _prec('PREC_RIGHT');
mkPrec.dynamic = _prec('PREC_DYN');

const mkField = (name, c) => ({ _t: 'FIELD', name, c });
const mkAlias = (c, nameOrRule) => ({
  _t: 'ALIAS', c,
  name: typeof nameOrRule === 'string' ? nameOrRule
      : (nameOrRule?._name ?? String(nameOrRule)),
});

// $ proxy – $.ruleName → symbol reference
const $ = new Proxy({}, { get: (_, p) => ({ _t: 'SYM', _name: String(p) }) });

// ──────────────────────────────────────────────────────────────────────────────
// 2. Evaluate grammar.js inside a sandboxed VM context
// ──────────────────────────────────────────────────────────────────────────────

function evaluateGrammar(source) {
  const mod = { exports: null };
  const ctx = vm.createContext({
    grammar: (s) => s,   // just return the spec object unchanged
    seq: mkSeq, choice: mkChoice, repeat: mkRepeat, repeat1: mkRepeat1,
    optional: mkOptional, blank: mkBlank, token: mkToken,
    prec: mkPrec, field: mkField, alias: mkAlias,
    module: mod, exports: mod.exports,
    require: (id) => { throw new Error(`require("${id}") not supported`); },
    console,
  });

  vm.runInContext(source, ctx);
  const spec = mod.exports;

  const evalWith$ = (fn) => typeof fn === 'function' ? fn($) : fn;

  const result = {
    name:        spec.name,
    extras:      evalWith$(spec.extras)     ?? [],
    externals:   evalWith$(spec.externals)  ?? [],
    word:        evalWith$(spec.word)       ?? null,
    supertypes:  evalWith$(spec.supertypes) ?? [],
    precedences: evalWith$(spec.precedences)?? [],
    conflicts:   evalWith$(spec.conflicts)  ?? [],
    rules: {},
  };

  for (const [name, fn] of Object.entries(spec.rules ?? {})) {
    try {
      result.rules[name] = evalWith$(fn);
    } catch (e) {
      result.rules[name] = { _t: 'ERR', msg: e.message };
    }
  }

  return result;
}

// ──────────────────────────────────────────────────────────────────────────────
// 3. Build a numeric precedence map from tree-sitter's named-precedence arrays
//
//    tree-sitter precedences: [[low, ..., high], [low, ..., high], ...]
//    Each item is a string name or a $-symbol.
//    We number them 1, 2, 3, ... from low to high across all groups.
// ──────────────────────────────────────────────────────────────────────────────

function buildPrecMap(precedences) {
  const map = new Map();
  let level = 1;
  for (const group of (precedences ?? [])) {
    for (const item of group) {
      const key = typeof item === 'string'         ? item
                : item?._t === 'SYM'               ? item._name
                : null;
      if (key && !map.has(key)) map.set(key, level++);
    }
  }
  return map;
}

function resolvePrec(n, precMap) {
  if (typeof n === 'number') return n;
  if (typeof n === 'string') return precMap.get(n) ?? 1;
  if (n?._t === 'SYM')       return precMap.get(n._name) ?? 1;
  return 1;
}

// ──────────────────────────────────────────────────────────────────────────────
// 4. Serialize a pattern node to DSL text
// ──────────────────────────────────────────────────────────────────────────────

// Binding strength for deciding when to add parens
const P = { TOP: 0, CHOICE: 1, SEQ: 2, POSTFIX: 3, ATOM: 4 };

// Cross-realm RegExp check (vm sandbox creates different RegExp class)
const isRegExp = (v) =>
  v !== null && typeof v === 'object' &&
  typeof v.source === 'string' && typeof v.flags === 'string';

function ser(node, precMap, outer = P.TOP) {
  if (node === null || node === undefined) return '/* null */';

  // Bare string → quoted literal
  if (typeof node === 'string') return JSON.stringify(node);

  // RegExp object → /source/  (use cross-realm check)
  if (isRegExp(node)) return `/${node.source}/`;

  const { _t } = node;

  switch (_t) {
    case 'SYM':   return node._name;
    case 'BLANK': return '/* blank */';
    case 'ERR':   return `/* ERROR: ${node.msg} */`;

    case 'SEQ': {
      // Skip BLANK members (they're usually there for empty alternatives)
      const parts = node.members
        .filter(m => m?._t !== 'BLANK')
        .map(m => ser(m, precMap, P.SEQ));
      if (parts.length === 0) return '/* empty */';
      if (parts.length === 1) return parts[0];
      const s = parts.join(' ');
      return outer > P.SEQ ? `(${s})` : s;
    }

    case 'CHOICE': {
      const members = node.members.filter(m => m?._t !== 'BLANK');
      const hasBlank = node.members.some(m => m?._t === 'BLANK');
      if (members.length === 0) return '/* blank */';
      if (members.length === 1 && hasBlank) {
        // choice(A, blank()) == optional(A)
        return `${ser(members[0], precMap, P.POSTFIX)}?`;
      }
      const parts = members.map(m => ser(m, precMap, P.CHOICE));
      const s = parts.join(' | ');
      return outer > P.CHOICE ? `(${s})` : s;
    }

    case 'REPEAT':      return `${ser(node.c, precMap, P.POSTFIX)}*`;
    case 'REPEAT1':     return `${ser(node.c, precMap, P.POSTFIX)}+`;
    case 'OPTIONAL':    return `${ser(node.c, precMap, P.POSTFIX)}?`;

    case 'TOKEN':
    case 'TOKEN_IMMED':
      // token() just marks the subtree as lexical; serialize inner as-is
      return ser(node.c, precMap, outer);

    case 'PREC':
    case 'PREC_LEFT':
    case 'PREC_DYN': {
      const n = resolvePrec(node.n, precMap);
      const fn = _t === 'PREC_LEFT' ? 'prec.left' : 'prec';
      return `${fn}(${n}, ${ser(node.c, precMap, P.ATOM)})`;
    }
    case 'PREC_RIGHT': {
      const n = resolvePrec(node.n, precMap);
      return `prec.right(${n}, ${ser(node.c, precMap, P.ATOM)})`;
    }

    case 'FIELD': {
      // field("name", pat) → name: pat
      return `${node.name}: ${ser(node.c, precMap, P.SEQ)}`;
    }

    case 'ALIAS': {
      return `alias(${JSON.stringify(node.name)}, ${ser(node.c, precMap, P.ATOM)})`;
    }

    default:
      if (typeof node === 'object' && '_name' in node) return node._name;
      return `/* unknown _t=${_t} */`;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// 5. Heuristic: is this rule purely lexical (a token rule)?
//    A rule is a token rule when its pattern contains no non-terminal references.
// ──────────────────────────────────────────────────────────────────────────────

function isLexical(node, visited = new Set()) {
  if (!node || typeof node !== 'object') return true;
  if (typeof node === 'string')  return true;
  if (isRegExp(node))            return true;

  switch (node._t) {
    case 'SYM':         return false;   // non-terminal reference
    case 'TOKEN':
    case 'TOKEN_IMMED': return true;    // explicitly lexical
    case 'BLANK':       return true;
    case 'ERR':         return false;
    case 'SEQ':
    case 'CHOICE':
      return node.members.every(m => isLexical(m, visited));
    case 'REPEAT':
    case 'REPEAT1':
    case 'OPTIONAL':
    case 'PREC':
    case 'PREC_LEFT':
    case 'PREC_RIGHT':
    case 'PREC_DYN':
    case 'FIELD':
    case 'ALIAS':
      return isLexical(node.c, visited);
    default:
      return false;
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// 6. Generate the full DSL text
// ──────────────────────────────────────────────────────────────────────────────

function generateDSL(grammar) {
  const precMap = buildPrecMap(grammar.precedences);
  const lines = [];

  // start – first public rule or 'structure' for MoonBit
  const startRule = grammar.name === 'moonbit' ? 'structure'
                  : Object.keys(grammar.rules ?? {}).find(n => !n.startsWith('_'))
                  ?? 'unknown';
  lines.push(`start ${startRule}`, '');

  // extras – skip external-scanner symbol refs, keep literals/regexes
  const extraPats = (grammar.extras ?? [])
    .filter(e => e?._t !== 'SYM')
    .map(e => ser(e, precMap));
  if (extraPats.length) lines.push(`extras [${extraPats.join(', ')}]`);

  // externals
  const extNames = (grammar.externals ?? [])
    .map(e => e?._t === 'SYM' ? e._name
            : typeof e === 'string' ? JSON.stringify(e)
            : null)
    .filter(Boolean);
  if (extNames.length) lines.push(`externals [${extNames.join(', ')}]`);

  // word
  if (grammar.word?._t === 'SYM') lines.push(`word ${grammar.word._name}`);

  // supertypes
  const stNames = (grammar.supertypes ?? [])
    .filter(e => e?._t === 'SYM').map(e => e._name);
  if (stNames.length) lines.push(`supertypes [${stNames.join(', ')}]`);

  // conflicts
  const cfls = (grammar.conflicts ?? [])
    .map(group => `[${group.filter(e => e?._t === 'SYM').map(e => e._name).join(', ')}]`);
  if (cfls.length) lines.push(`conflicts [${cfls.join(', ')}]`);

  lines.push('');

  // rules
  for (const [name, pattern] of Object.entries(grammar.rules ?? {})) {
    const lexical = isLexical(pattern);
    const prefix = lexical ? 'token rule' : 'rule';
    const body = ser(pattern, precMap);
    lines.push(`${prefix} ${name}: ${body}`);
  }

  return lines.join('\n');
}

// ──────────────────────────────────────────────────────────────────────────────
// 7. Wrap DSL as a MoonBit multiline string and write .mbt file
// ──────────────────────────────────────────────────────────────────────────────

function writeMbt(dsl) {
  const body = dsl.split('\n').map(l => `  #|${l}`).join('\n');
  const mbt = `///|\npub let moonbit_grammar : String =\n${body}\n`;
  const outPath = path.join(__dirname, '..', 'grammar_generated.mbt');
  fs.writeFileSync(outPath, mbt, 'utf8');
  console.error(`[gen_grammar] Written to: ${outPath}`);
}

// ──────────────────────────────────────────────────────────────────────────────
// 8. Fetch grammar.js from GitHub (if no local path given)
// ──────────────────────────────────────────────────────────────────────────────

function fetchText(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      // Follow redirects
      if (res.statusCode === 301 || res.statusCode === 302) {
        return fetchText(res.headers.location).then(resolve).catch(reject);
      }
      if (res.statusCode !== 200) {
        return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      }
      let buf = '';
      res.on('data', d => buf += d);
      res.on('end', () => resolve(buf));
      res.on('error', reject);
    }).on('error', reject);
  });
}

// ──────────────────────────────────────────────────────────────────────────────
// 9. Entry point
// ──────────────────────────────────────────────────────────────────────────────

async function main() {
  let source;
  const inputPath = process.argv[2];

  if (inputPath) {
    source = fs.readFileSync(path.resolve(inputPath), 'utf8');
    console.error(`[gen_grammar] Using local file: ${inputPath}`);
  } else {
    const url = 'https://raw.githubusercontent.com/moonbitlang/tree-sitter-moonbit/main/grammar.js';
    console.error(`[gen_grammar] Fetching: ${url}`);
    source = await fetchText(url);
  }

  const grammar = evaluateGrammar(source);
  console.error(`[gen_grammar] Parsed ${Object.keys(grammar.rules).length} rules`);

  const dsl = generateDSL(grammar);
  writeMbt(dsl);
}

main().catch(e => {
  console.error('[gen_grammar] Error:', e.message);
  process.exit(1);
});
