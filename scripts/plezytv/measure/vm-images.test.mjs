import { test } from 'node:test';
import assert from 'node:assert/strict';
import { countImages } from './vm-images.mjs';

function fixture() {
  const pages = [];
  const cacheKeys = Array.from({ length: 232 }, (_, i) => `key/${i}`);
  const liveKeys = Array.from({ length: 259 }, (_, i) => `key/${i + 20}`);
  const field = (name, value) => ({ decl: { name }, value });
  const fields = [
    field('_cache', { id: 'cacheMap' }), field('_liveImages', { id: 'liveMap' }),
    field('_currentSizeBytes', { valueAsString: '66822720' }),
    field('_maximumSizeBytes', { valueAsString: '67108864' }),
  ];
  const vm = {
    async call(method, params) {
      assert.equal(params.isolateId, 'main');
      if (method === 'getAllocationProfile') return { members: [
        { class: { id: 'images', name: '_Image', library: { uri: 'dart:ui' } } },
        { class: { id: 'rows', name: 'TvHorizontalRowState' } },
        { class: { id: 'cache', name: 'ImageCache' } },
      ] };
      if (method === 'getInstances') {
        assert.equal('classId' in params, false);
        const ids = { images: Array.from({ length: 260 }, (_, i) => `image/${i}`),
          rows: Array.from({ length: 23 }, (_, i) => `row/${i}`), cache: ['cacheObject'] }[params.objectId];
        assert.ok(ids, 'getInstances requires class objectId');
        return { totalCount: ids.length, instances: ids.map(id => ({ id })) };
      }
      assert.equal(method, 'getObject', 'AOT inspection must not evaluate');
      if (params.objectId.startsWith('row/')) return { fields: [field('_element', {
        kind: params.objectId === 'row/22' ? 'Null' : 'PlainInstance',
      })] };
      if (params.objectId === 'cacheObject') return { fields };
      const keys = { cacheMap: cacheKeys, liveMap: liveKeys }[params.objectId];
      assert.ok(keys);
      pages.push([params.objectId, params.offset, params.count]);
      return { length: keys.length, associations: keys.slice(params.offset, params.offset + params.count).map(id => ({ key: { id } })) };
    },
  };
  return { vm, pages };
}

test('profile inspection uses objectId, paged map keys and non-null element', async () => {
  const { vm, pages } = fixture();
  assert.deepEqual(await countImages(vm, 'main'), {
    images: 260, cacheEntries: 232, liveEntries: 259, builtRows: 22,
    cacheWithoutListeners: 20, heldByWidgetsApprox: 240,
    currentSizeMiB: 63.73, maximumSizeMiB: 64,
  });
  assert.deepEqual(pages.map(p => p.slice(0, 2)), [
    ['cacheMap', 0], ['cacheMap', 128],
    ['liveMap', 0], ['liveMap', 128], ['liveMap', 256],
  ]);
});

test('an incomplete map page fails rather than undercounting', async () => {
  const { vm } = fixture();
  const original = vm.call.bind(vm);
  vm.call = async (method, params) => params.objectId === 'cacheMap'
    ? { length: 232, associations: [] } : original(method, params);
  await assert.rejects(countImages(vm, 'main'), /Incomplete VM map page/);
});
