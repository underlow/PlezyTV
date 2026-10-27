#!/usr/bin/env node
// Node 22+ (global WebSocket). No device defaults: never connect implicitly.
import { spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline/promises';
import { VM, sleep } from '../../perf/vmclient.mjs';
const [mode, ...args] = process.argv.slice(2);
const opts = {};
for (let i = 0; i < args.length; i += 2) {
  if (!args[i].startsWith('--') || args[i + 1] === undefined) throw Error('Expected --option value');
  opts[args[i].slice(2)] = args[i + 1];
}
if (!['cold', 'images', 'laps'].includes(mode) || !opts.device) {
  console.error('Usage: node measure.mjs cold|images|laps --device SERIAL [--package com.underlow.plezytv] [--runs 5] [--delay 20] [--uri VM_URI]');
  process.exit(1);
}
const pkg = opts.package ?? 'com.underlow.plezytv';
if (!/^[a-zA-Z0-9_.]+$/.test(pkg)) throw Error('Invalid package');
const activity = opts.activity ?? 'com.edde746.plezy.PlezyActivity';
if (!/^[a-zA-Z0-9_.]+$/.test(activity)) throw Error('Invalid activity');
const runs = Number(opts.runs ?? 5), delay = Number(opts.delay ?? 20);
if (!Number.isInteger(runs) || runs < 1 || !Number.isFinite(delay) || delay < 0) throw Error('Invalid runs/delay');
const adb = (...a) => {
  const r = spawnSync(process.env.ADB ?? `${process.env.HOME}/Library/Android/sdk/platform-tools/adb`, ['-s', opts.device, ...a], { encoding: 'utf8', timeout: 30000 });
  if (r.status !== 0) throw Error(r.stderr || r.error?.message || 'adb failed');
  return r.stdout;
};
function memory() {
  const raw = adb('shell', 'dumpsys', 'meminfo', pkg);
  const pss = raw.match(/TOTAL PSS:\s*(\d+)/) ?? raw.match(/^\s*TOTAL\s+(\d+)/m);
  const graphics = raw.match(/^\s*Graphics:\s*(\d+)/m);
  if (!pss || !graphics) throw Error('meminfo missing TOTAL PSS or Graphics; unsupported output or app absent');
  return { pssMiB: +(+pss[1] / 1024).toFixed(2), graphicsMiB: +(+graphics[1] / 1024).toFixed(2) };
}
function launch(profile = false) {
  adb('shell', 'am', 'force-stop', pkg);
  adb('logcat', '-c');
  const output = adb('shell', 'am', 'start', '-W', ...(profile ? ['--ez', 'enable-dart-profiling', 'true'] : []), '-n', `${pkg}/${activity}`);
  if (/Error|Exception|Status:\s*(?!ok\b)\S+/i.test(output)) throw Error(`Activity launch failed: ${output.trim()}`);
}
if (mode === 'cold') {
  const results = [];
  for (let run = 1; run <= runs; run++) {
    launch();
    await sleep(delay * 1000);
    const mem = memory();
    const pid = adb('shell', 'pidof', pkg).trim();
    if (!/^\d+$/.test(pid)) throw Error('Expected one app process');
    const log = adb('logcat', '-d', '-v', 'epoch', `--pid=${pid}`);
    const marks = {};
    let ready = null, visibleRows = null;
    for (const line of log.split('\n')) {
      const time = Number(line.match(/^\s*(\d+\.\d+)/)?.[1]) * 1000;
      const phase = line.match(/Startup phase: phase=(\w+)/)?.[1];
      if (phase && !(phase in marks)) marks[phase] = time;
      const match = line.match(/TV home rows ready.*visibleRows=(\d+)/);
      if (match && ready === null) { ready = time; visibleRows = +match[1]; }
    }
    const phasesMs = Object.fromEntries(Object.entries(marks).map(([k, t]) => [k, Number.isFinite(marks.native_on_create) ? Math.round(t - marks.native_on_create) : null]));
    const result = { run, ...mem, phasesMs, bindingToHomeMs: ready !== null && marks.binding_settled !== undefined ? Math.round(ready - marks.binding_settled) : null, visibleRows };
    results.push(result); console.log(JSON.stringify(result));
  }
  const summary = {};
  const fields = ['pssMiB', 'graphicsMiB', 'bindingToHomeMs', ...new Set(['native_on_create', 'binding_settled', 'main_screen', ...results.flatMap(r => Object.keys(r.phasesMs))].map(k => `phase:${k}`))];
  for (const field of fields) {
    const values = results.map(r => field.startsWith('phase:') ? r.phasesMs[field.slice(6)] : r[field]).filter(Number.isFinite).sort((a,b) => a-b);
    const n = values.length;
    summary[field] = { samples: n, missing: runs - n, min: values[0] ?? null, median: n ? (values[Math.floor((n-1)/2)] + values[Math.floor(n/2)]) / 2 : null, max: values.at(-1) ?? null };
  }
  console.log(JSON.stringify({ summary }));
} else if (mode === 'laps') {
  const input = createInterface({ input: process.stdin, output: process.stderr });
  try {
    await input.question('Open settled Home. Press Enter to sample baseline. ');
    const before = memory();
    for (let run = 1; run <= runs; run++) {
      await input.question(`Lap ${run}/${runs}: Home → library → movie → back to library → back to Home. Press Enter when Home is restored. `);
      await sleep(delay * 1000);
      console.log(JSON.stringify({ lap: run, ...memory() }));
    }
    const after = memory();
    console.log(JSON.stringify({ before, after, deltaPssMiB: +(after.pssMiB-before.pssMiB).toFixed(2) }));
  } finally { input.close(); }
} else {
  let uri = opts.uri, port;
  if (!uri) {
    launch(true);
    for (let i = 0; i < 40 && !uri; i++) {
      uri = adb('logcat', '-d').match(/The Dart VM service is listening on (http:\/\/127\.0\.0\.1:\d+\/\S+)/)?.[1];
      if (!uri) await sleep(1000);
    }
    if (!uri) throw Error('No VM service: install a profile build first');
    const url = new URL(uri);
    port = adb('forward', 'tcp:0', `tcp:${url.port}`).trim();
    url.port = port; uri = url.toString();
    await sleep(delay * 1000);
  }
  let vm;
  try {
    vm = await VM.connect(uri);
    const isolateId = await vm.uiIsolate();
    const call = (method, params = {}) => vm.call(method, { isolateId, ...params });
    const profile = await call('getAllocationProfile', { gc: true });
    const classes = profile.members;
    async function instances(name, libraryUri) {
      const matches = classes.filter(c => c.class.name === name && (!libraryUri || c.class.library?.uri === libraryUri));
      if (matches.length !== 1) throw Error(`Expected one class ${name}, found ${matches.length}`);
      const result = await call('getInstances', { classId: matches[0].class.id, limit: 100000 });
      if (result.totalCount > result.instances.length) throw Error(`Truncated ${name} instances`);
      return result;
    }
    const images = await instances('_Image', 'dart:ui');
    const rows = await instances('TvHorizontalRowState');
    let builtRows = 0;
    for (const row of rows.instances) {
      const value = await call('evaluate', { targetId: row.id, expression: 'mounted' });
      if (value.valueAsString === 'true') builtRows++;
    }
    const caches = await instances('ImageCache');
    if (caches.totalCount !== 1) throw Error('Expected one ImageCache');
    async function evaluate(expression) {
      const result = await call('evaluate', { targetId: caches.instances[0].id, expression });
      const number = Number(result.valueAsString);
      if (!Number.isFinite(number)) throw Error(`Cannot evaluate ImageCache ${expression}`);
      return number;
    }
    const cacheEntries = await evaluate('_cache.length');
    const liveEntries = await evaluate('_liveImages.length');
    const cacheWithoutListeners = await evaluate('_cache.keys.where((key) => !_liveImages.containsKey(key)).length');
    console.log(JSON.stringify({ images: images.totalCount, cacheEntries, liveEntries, builtRows, cacheWithoutListeners, heldByWidgetsApprox: Math.max(0, images.totalCount-cacheWithoutListeners) }));
  } finally {
    vm?.close();
    if (port) adb('forward', '--remove', `tcp:${port}`);
  }
}
