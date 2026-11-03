// Build from the locked, official v1.3.0 worker. No provider protocol rewrite.
const fs = require('node:fs'), path = require('node:path');
const esbuild = require('esbuild');
const root = path.resolve(__dirname, '..');
const input = process.argv[2] || path.join(root, 'build/upstream/MusicBridge/worker.cjs');
const output = process.argv[3] || path.join(root, 'native/worker-dual.cjs');
let code = fs.readFileSync(input, 'utf8');
function replaceOnce(a,b) { if (code.split(a).length !== 2) throw Error('Upstream boundary changed: '+a); code=code.replace(a,b); }
const start=code.indexOf('var tokenPath ='), end=code.indexOf('async function dispatch2(message2)',start);
if (start<0 || end<0) throw Error('Missing entry');
let entry = code.slice(start,end);
const unstart=entry.indexOf('var Module = require("node:module");'), unend=entry.indexOf('var neteaseEndpoints =',unstart);
if(unstart<0 || unend<0) throw Error('Missing unblock boundary');
entry=entry.slice(0,unstart)+entry.slice(unend);
const ds=entry.indexOf('async function dispatchRequest(message2)'), tail=entry.indexOf('  let responseCookies =',ds);
if(ds<0 || tail<0) throw Error('Missing dispatch boundary');
entry=entry.slice(0,ds)+'return async function(message2) {\n'+entry.slice(tail);
const adapter = path.join(root,'native/netease-features.cjs');
const favoritesAdapter = path.join(root,'native/favorites-sync.cjs');
code=code.slice(0,start)+`
console.log = console.info = console.warn = console.error = console.debug = () => {};
var extendNetEase = require(${JSON.stringify(adapter)});
var extendFavorites = require(${JSON.stringify(favoritesAdapter)});
var neteaseDispatch;
function createNeteaseDispatch() { ${entry} }
async function dispatchRequest(message2) {
  if (message2.route?.startsWith('/native/')) {
    const client=await Promise.resolve().then(() => (init_dispatch(), dispatch_exports));
    return client.dispatch(message2,dispatch2);
  }
  if (message2.route?.startsWith('/qq/')) return require_qq2().dispatch(message2);
  if (message2.route === '/login/channels') return {body:{code:200,channels:['netease']},cookies:[]};
  if (message2.route === '/login/qr/cancel') return {body:{code:200},cookies:[]};
  if (message2.route === '/login/qr/create') {
    const key=String(message2.params?.key || '');
    if (!/^[a-zA-Z0-9_-]{8,256}$/.test(key)) return {body:{code:400,message:'登录二维码无效'},cookies:[]};
    const url='https://music.163.com/login?codekey='+encodeURIComponent(key);
    return {body:{code:200,data:{qrimg:await require_lib13().toDataURL(url,{margin:4,width:256})}},cookies:[]};
  }
  neteaseDispatch ||= createNeteaseDispatch();
  return neteaseDispatch(message2);
}
`+code.slice(end);
replaceOnce('!["netease", "qq", "kugou"].includes(provider)', '!["netease", "qq"].includes(provider)');
replaceOnce('  } else if (provider === "kugou") {\n    api2 = new KugouAPI(base);\n  }', '  } else {\n    api2 = extendNetEase(base, parse);\n  }');
replaceOnce('    init_kugou();\n','');
replaceOnce('  if (operation !== "lyrics"', '  api2 = extendFavorites(api2, provider);\n  if (operation !== "lyrics"');
const ts=code.indexOf('if (process.env.RHINE_TEST_BRIDGE) {'), te=code.indexOf('readline.createInterface({',ts);
if(ts<0 || te<0) throw Error('Missing test boundary');
code=code.slice(0,ts)+code.slice(te);
code=code.replace(/= __commonJS\(\{/g,'= /* @__PURE__ */ __commonJS({').replace(/= __esm\(\{/g,'= /* @__PURE__ */ __esm({');
esbuild.buildSync({stdin:{contents:code,resolveDir:root,sourcefile:'rhine-v1.3.0-dual.cjs'},outfile:output,
  bundle:true,platform:'node',target:'node22',format:'cjs',treeShaking:true,minifySyntax:true,minifyWhitespace:true,legalComments:'eof'});
console.log(JSON.stringify({bytes:fs.statSync(output).size,output}));
