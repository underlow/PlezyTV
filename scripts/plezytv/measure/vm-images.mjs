// AOT-compatible inspection: do not use evaluate (unavailable in profile).
export async function countImages(vm, isolateId) {
  const call = (method, params = {}) => vm.call(method, { isolateId, ...params });
  const object = async (objectId, params = {}) => {
    const result = await call('getObject', { objectId, ...params });
    if (result.type === 'Sentinel') throw Error('VM object expired during inspection; retry');
    return result;
  };
  const profile = await call('getAllocationProfile', { gc: true });
  async function instances(name, libraryUri) {
    const matches = profile.members.filter(c => c.class.name === name && (!libraryUri || c.class.library?.uri === libraryUri));
    if (matches.length !== 1) throw Error(`Expected one class ${name}, found ${matches.length}`);
    const result = await call('getInstances', { objectId: matches[0].class.id, limit: 100000 });
    if (result.totalCount > result.instances.length) throw Error(`Truncated ${name} instances`);
    return result;
  }
  function field(instance, name) {
    const result = instance.fields?.find(f => f.decl.name === name)?.value;
    if (!result) throw Error(`Missing VM field ${name}`);
    return result;
  }
  function integer(ref, name) {
    const value = Number(ref.valueAsString);
    if (!Number.isSafeInteger(value) || value < 0) throw Error(`Invalid VM integer ${name}`);
    return value;
  }
  async function mapKeys(ref) {
    const keys = new Set();
    let length;
    for (let offset = 0; length === undefined || offset < length;) {
      const page = await object(ref.id, { offset, count: 128 });
      if (!Number.isSafeInteger(page.length) || page.length < 0 ||
          (length !== undefined && length !== page.length)) {
        throw Error('VM map changed size during inspection; retry');
      }
      length = page.length;
      const associations = page.associations;
      if (!Array.isArray(associations) || associations.length > length - offset ||
          (associations.length === 0 && offset < length)) {
        throw Error('Incomplete VM map page');
      }
      for (const association of associations) {
        if (typeof association.key?.id !== 'string') throw Error('VM map key has no object id');
        keys.add(association.key.id);
      }
      offset += associations.length;
      if (offset === length) break;
    }
    if (keys.size !== length) throw Error('VM map keys changed during inspection; retry');
    return keys;
  }
  const images = await instances('_Image', 'dart:ui');
  const rows = await instances('TvHorizontalRowState');
  let builtRows = 0;
  for (const row of rows.instances) {
    const element = field(await object(row.id), '_element');
    if (!element.kind) throw Error('VM _element has no kind');
    if (element.kind !== 'Null') builtRows++;
  }
  const caches = await instances('ImageCache');
  if (caches.totalCount !== 1) throw Error('Expected one ImageCache');
  const cache = await object(caches.instances[0].id);
  const cachedKeys = await mapKeys(field(cache, '_cache'));
  const liveKeys = await mapKeys(field(cache, '_liveImages'));
  const cacheWithoutListeners = [...cachedKeys].filter(key => !liveKeys.has(key)).length;
  const mib = name => +(integer(field(cache, name), name) / 1024 / 1024).toFixed(2);
  return {
    images: images.totalCount,
    cacheEntries: cachedKeys.size,
    liveEntries: liveKeys.size,
    builtRows,
    cacheWithoutListeners,
    heldByWidgetsApprox: Math.max(0, images.totalCount - cacheWithoutListeners),
    currentSizeMiB: mib('_currentSizeBytes'),
    maximumSizeMiB: mib('_maximumSizeBytes'),
  };
}
