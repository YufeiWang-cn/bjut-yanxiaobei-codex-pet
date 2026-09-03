'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { privateFile, secretLike, localTargets } = require('../scripts/Audit-Source.cjs');
test('release audit excludes credential and runtime state filenames', () => {
  for (const name of ['auth.json','bridge-state.json','ui-settings.json','mac-settings.json','.env','.env.local','autostart-enabled.flag','private.pem','private.key']) assert.equal(privateFile(name),true,name);
});
test('release audit also excludes SQLite sidecars, caches and archives', () => {
  for (const name of ['state.sqlite-wal','state.sqlite-shm','state.db-wal','notes.log','old.zip','build.dmg','module.pyc','Thumbs.db','.DS_Store']) assert.equal(privateFile(name),true,name);
});
test('release audit preserves all supported source and asset filenames', () => {
  for (const name of ['README.md','pet.json','.npmrc','package-lock.json','spritesheet.webp','00.png','failed.gif','Start.command','Start.vbs']) assert.equal(privateFile(name),false,name);
});
test('credential pattern findings do not depend on real credentials', () => {
  for (const prefix of ['ghp_','github_pat_','sk-proj-']) assert.equal(secretLike(prefix+'a'.repeat(40)),true);
  assert.equal(secretLike('-----BEGIN '+'PRIVATE KEY-----'),true);
  assert.equal(secretLike('auth.json contains account data; do not upload it.'),false);
});
test('local link checks include Markdown links and HTML assets', () => {
  assert.deepEqual(localTargets('[guide](docs/BEGINNER.md) ![pet](docs/images/hero.png) <img src="image.png"> <link href="style.css">'),['docs/BEGINNER.md','docs/images/hero.png','image.png','style.css']);
});
test('local link checks skip external links, fragments and code samples', () => {
  assert.deepEqual(localTargets('[web](https://example.com) [part](#part) `[code](missing.md)`\n```md\n[example](also-missing.md)\n```\n'),[]);
});
