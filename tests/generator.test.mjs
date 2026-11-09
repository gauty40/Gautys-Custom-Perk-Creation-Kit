import fs from 'node:fs';import assert from 'node:assert/strict';import {createRequire} from 'node:module';import {fileURLToPath} from 'node:url';import path from 'node:path';import {buildProject,parsePerk,catalog,PATHS,text,authorScript,zipFiles,unzipFiles} from '../assets/generator.mjs';
const here=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(here,'..'),require=createRequire(import.meta.url),lua=require('../assets/vendor/luaparse.cjs');
const manifest=JSON.parse(fs.readFileSync(root+'/baselines/manifest.json'));const baseline=new Map(manifest.files.map(f=>[f.path,new Uint8Array(fs.readFileSync(root+'/'+f.url))]));const template=text(baseline.get('kronos/custom_scripts/perk_template.gsc.template'));
let source=template.replaceAll('template_perk','web_test').replace('def["code"] = 85;','def["code"] = 89;');const script={filename:'perk_web_test.gsc',source};
let result=buildProject(baseline,{scripts:[script]});assert.equal(result.perks.length,catalog(text(baseline.get(PATHS.lua))).length+1);lua.parse(text(result.files.get(PATHS.lua)),{luaVersion:'5.1'});assert(text(result.files.get(PATHS.manager)).includes('self.cp_web_test_major = 2'));assert(text(result.files.get(PATHS.store)).includes('off_web_test'));
let reapply=buildProject(result.files,{scripts:[script]});assert.equal(catalog(text(reapply.files.get(PATHS.lua))).filter(p=>p.id==='web_test').length,1);lua.parse(text(reapply.files.get(PATHS.lua)),{luaVersion:'5.1'});
let removed=buildProject(reapply.files,{remove:['web_test']});assert(!catalog(text(removed.files.get(PATHS.lua))).some(p=>p.id==='web_test'));assert(!text(removed.files.get(PATHS.store)).includes('web_test'));lua.parse(text(removed.files.get(PATHS.lua)),{luaVersion:'5.1'});
let majorOnly=source.replaceAll('web_test','web_major').replace('= 89;','= 90;').replace(/^\/\/ @augment minor.*\r?\n/gm,'');let plain=source.replaceAll('web_test','web_plain').replace('= 89;','= 91;').replace(/^\/\/ @augment.*\r?\n/gm,'');let multi=buildProject(baseline,{scripts:[script,{source:majorOnly,filename:'perk_web_major.gsc'},{source:plain,filename:'perk_web_plain.gsc'}]});lua.parse(text(multi.files.get(PATHS.lua)),{luaVersion:'5.1'});assert(text(multi.files.get(PATHS.store)).includes('off_web_plain'));assert(text(multi.files.get(PATHS.manager)).includes('// @coop_sync web_major 13000'));
assert.throws(()=>buildProject(baseline,{scripts:[{source:source.replace('= 89;','= 71;'),filename:'collision.gsc'}]}),/already used/);assert.throws(()=>buildProject(baseline,{scripts:[script,script]}),/Duplicate/);
const packed=zipFiles(multi.files),unpacked=await unzipFiles(packed.buffer);assert.equal(unpacked.size,multi.files.size);for(const[k,v]of multi.files)assert.deepEqual(new Uint8Array(Buffer.from(typeof v==='string'?v:v)),unpacked.get(k));
fs.mkdirSync(root+'/tests/generated',{recursive:true});for(const name of Object.values(PATHS)){fs.writeFileSync(root+'/tests/generated/'+path.basename(name),text(multi.files.get(name)));}fs.writeFileSync(root+'/tests/generated/perk_web_test.gsc',source);
console.log('PASS: add, reapply, remove, multi-perk, major-only/plain, reserved sync ranges, collision checks, Lua syntax and ZIP round trip.');

for(const existing of catalog(text(baseline.get(PATHS.lua)))){
 const removed=buildProject(baseline,{remove:[existing.id]});lua.parse(text(removed.files.get(PATHS.lua)),{luaVersion:'5.1'});
 const source=[...baseline].find(([key,value])=>key.endsWith('.gsc')&&key.includes('/perk_')&&(()=>{try{return parsePerk(text(value),key).id===existing.id;}catch{return false;}})());
 if(source){const updated=buildProject(baseline,{scripts:[{filename:source[0].split('/').pop(),source:text(source[1])}]});lua.parse(text(updated.files.get(PATHS.lua)),{luaVersion:'5.1'});}
}
const empty=buildProject(baseline,{remove:catalog(text(baseline.get(PATHS.lua))).map(p=>p.id)});lua.parse(text(empty.files.get(PATHS.lua)),{luaVersion:'5.1'});fs.writeFileSync(root+'/tests/generated/empty_manager.gsc',text(empty.files.get(PATHS.manager)));console.log('PASS: remove/reapply every bundled perk and remove all perks.');
const authored=authorScript(template,{id:'author_test',code:93,name:'Author Test',creator:'Someone',description:'A working example',price:2500});assert.equal(parsePerk(authored).code,93);assert.equal(parsePerk(authored).creator,'Someone');
for(const existing of catalog(text(baseline.get(PATHS.lua)))){
 const source=[...baseline].find(([key,value])=>key.endsWith('.gsc')&&key.includes('/perk_')&&(()=>{try{return parsePerk(text(value),key).id===existing.id;}catch{return false;}})());
 if(!source)continue;
 const before=text(baseline.get(PATHS.lua));const oldOffset=new RegExp('key = "'+existing.id+'",[\\s\\S]*?minorLootOffset = (\\d+)').exec(before);const oldRow=new RegExp('key = "'+existing.id+'",[\\s\\S]*?lootBase = (\\d+)').exec(before);
 const updated=buildProject(baseline,{scripts:[{filename:source[0].split('/').pop(),source:text(source[1])}]});
 const after=text(updated.files.get(PATHS.lua));const newRow=new RegExp('key = "'+existing.id+'",[\\s\\S]*?minorLootOffset = (\\d+), lootBase = (\\d+)').exec(after);
 if(oldRow&&newRow){const row=before.slice(before.indexOf('key = "'+existing.id+'",'));const until=row.indexOf('},');const localOffset=/minorLootOffset = (\d+)/.exec(row.slice(0,until));assert.equal(+newRow[1],localOffset?+localOffset[1]:5);assert.equal(+newRow[2],+oldRow[1]);}
}
console.log('PASS: author form metadata and existing perk loot-ID/offset preservation.');
