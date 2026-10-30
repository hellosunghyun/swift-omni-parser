// Development-only: Node's bundled Acorn parses loop bodies before adding checks.
// Run: node --expose-internals prepare.cjs upstream-index.js output-renderer.js
const fs = require('fs');
const crypto = require('crypto');
const acorn = require('internal/deps/acorn/acorn/dist/acorn');
const source = fs.readFileSync(process.argv[2], 'utf8');
const expected = '543bb78b70617569f28905e7b2e0c174330f87bfa3cdf38fa828ba093813ecc9';
if (crypto.createHash('sha256').update(source).digest('hex') !== expected) throw Error('Unexpected source');
const edits = [], kinds = new Set(['ForStatement','ForInStatement','ForOfStatement','WhileStatement','DoWhileStatement']);
let loops = 0, escapedFonts = 0, boundedArrays = 0, unsupportedLogs = 0, unsupportedStubs = 0, textCoordinates = 0, textOutRange;
function visit(node) {
  if (!node || typeof node !== 'object') return;
  if(node.type==='MethodDefinition' && node.key.name==='processTextOut')
    textOutRange=[node.start,node.end];
  if(node.type==='CallExpression' && node.callee.property?.name==='readShortFromData'
    && textOutRange && node.start>textOutRange[0] && node.end<textOutRange[1]){
    const argument=node.arguments[1];
    edits.push([argument.start,'(']); edits.push([argument.end,'+(textLength%2))']); textCoordinates++;
  }
  if(node.type==='AssignmentExpression' && node.left.type==='MemberExpression'
    && node.left.object.type==='ThisExpression' && ['_nodes','_defs'].includes(node.left.property.name)
    && node.right.type==='ArrayExpression'){
    edits.push([node.right.start,'__omniNodes(']); edits.push([node.right.end,')']); boundedArrays++;
  }
  if(node.type==='MemberExpression' && node.object?.name==='f' && node.property?.name==='family'){
    edits.push([node.start,'_SvgContext._esc(']); edits.push([node.end,')']); escapedFonts++;
  }
  if(node.type==='CallExpression' && node.callee.name==='__wmfEmfRendererLog'
    && typeof node.arguments[0]?.value==='string'
    && /unknown|unimplemented/i.test(node.arguments[0].value)){
    edits.push([node.start,'(__omniUnsupported=true,']); edits.push([node.end,')']); unsupportedLogs++;
  }
  if(node.type==='MethodDefinition' && node.key.name?.startsWith('process')){
    const body=node.value.body;
    const ignored=['processEmfHeader','processEmfPlusComment','processWmfcComment'];
    const logOnly=body.body.length>0 && body.body.every(x=>x.type==='ExpressionStatement'
      && x.expression.type==='CallExpression' && x.expression.callee.name==='__wmfEmfRendererLog');
    if(logOnly && !ignored.includes(node.key.name)){
      edits.push([body.start+1,'__omniUnsupported=true;']); unsupportedStubs++;
    }
  }
  if (kinds.has(node.type)) {
    loops++;
    const b = node.body;
    if (b.type === 'BlockStatement') edits.push([b.start + 1, '__omniBudget();']);
    else { edits.push([b.start, '{__omniBudget();']); edits.push([b.end, '}']); }
  }
  for (const [key,value] of Object.entries(node)) {
    if (key === 'parent') continue;
    if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') visit(value);
  }
}
visit(acorn.parse(source,{ecmaVersion:'latest'}));
let output = source;
for (const [position,text] of edits.sort((a,b)=>b[0]-a[0])) output=output.slice(0,position)+text+output.slice(position);
let verified = 0;
function verify(node) {
  if (!node || typeof node !== 'object') return;
  if (kinds.has(node.type)) {
    const first=node.body.body?.[0];
    if (first?.expression?.callee?.name !== '__omniBudget') throw Error('Unguarded loop');
    verified++;
  }
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(verify);
    else if (value && typeof value==='object') verify(value);
  }
}
verify(acorn.parse(output,{ecmaVersion:'latest'}));
if (verified !== loops || escapedFonts!==1 || boundedArrays!==2 || textCoordinates!==2) throw Error('Patch coverage changed');
fs.writeFileSync(process.argv[3], output);
console.log(JSON.stringify({loops,verified,originalSHA256:expected,unsupportedLogs,unsupportedStubs,textCoordinates,modifiedSHA256:crypto.createHash('sha256').update(output).digest('hex')}));
