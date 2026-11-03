// SPDX-License-Identifier: MIT
// Build the locked Rhine worker, then apply the app's dual-account adapter.
const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'vendor/rhine/MusicBridge');
const build = path.join(root, 'build', 'bridge-' + Date.now());
fs.mkdirSync(build, {recursive:true});
let bundler = fs.readFileSync(path.join(root, 'vendor/rhine/scripts/bundle-bridge.cjs'), 'utf8');
// A fresh path is mandatory; the upstream script's cleanup is intentionally disabled.
bundler = bundler.replace("const root = path.resolve(__dirname, '..');", 'const root = '+JSON.stringify(root)+';');
bundler = bundler.replace('        fs.rmSync(directory, { recursive: true, force: true });',
    "        if (fs.existsSync(directory)) throw new Error('Use a fresh output path: ' + directory);");
const generated = path.join(build, 'bundle-upstream.cjs');
fs.writeFileSync(generated, bundler);
cp.execFileSync(process.execPath, [generated,source,path.join(build,'upstream')], {cwd:root,stdio:'inherit'});
cp.execFileSync(process.execPath, [path.join(__dirname,'adapt-dual-worker.cjs'),
    path.join(build,'upstream/MusicBridge/worker.cjs'),path.join(root,'native/worker-dual.cjs')], {cwd:root,stdio:'inherit'});
fs.copyFileSync(path.join(build,'upstream/MusicBridge/xhr-sync-worker.js'),path.join(root,'native/xhr-sync-worker.js'));
console.log('Built native/worker-dual.cjs and native/xhr-sync-worker.js from the locked sources.');
