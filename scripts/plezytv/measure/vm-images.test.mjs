import { test } from 'node:test';
import assert from 'node:assert/strict';
import { countImages } from './vm-images.mjs';

function fixture() {
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
      const length = { cacheMap: 232, liveMap: 259 }[params.objectId];
      assert.notEqual(length, undefined);
      // No associations: listener counts must not depend on key identity.
      return { length };
    },
  };
  return { vm };
}

test('heldByWidgets uses live map length without inspecting key identities', async () => {
  const { vm } = fixture();
  assert.deepEqual(await countImages(vm, 'main'), {
    images: 260, cacheEntries: 232, liveEntries: 259, builtRows: 22,
    heldByWidgets: 259,
    currentSizeMiB: 63.73, maximumSizeMiB: 64,
  });
});

test('invalid map length fails rather than reporting a listener count', async () => {
  const { vm } = fixture();
  const original = vm.call.bind(vm);
  vm.call = async (method, params) => params.objectId === 'cacheMap'
    ? { length: -1 } : original(method, params);
  await assert.rejects(countImages(vm, 'main'), /Invalid VM map length/);
});
