/**
 * Unit tests for SearchScreen buildQueryString / parseFiltersFromURL.
 *
 * These functions are not exported, so we re-declare them here as pure
 * functions to avoid mounting the full component (which needs a server).
 * If the implementation changes, keep these in sync.
 */

const STATIC_FILTER_KEYS = new Set([
  'mime_group', 'modified_within', 'file_size_group',
  'publish_status', 'approved_status', 'orientation', 'style',
  'video_format', 'video_codec',
  'video_height_min', 'video_height_max',
  'video_width_min', 'video_width_max',
  'video_bitrate_min', 'video_bitrate_max',
  'audio_codec', 'audio_bitrate_min', 'audio_bitrate_max',
]);

const RESERVED_URL_PARAMS = new Set(['q', 'mode', 'page', 'per_page', 'sort_by', 'sort_dir']);

function buildQueryString(query, filters, page, perPage, sortBy, sortDir, mode) {
  const params = new URLSearchParams();
  if (query) params.set('q', query);
  if (mode && mode !== 'all') params.set('mode', mode);
  STATIC_FILTER_KEYS.forEach((key) => {
    if (filters[key]) params.set(key, filters[key]);
  });
  Object.entries(filters).forEach(([key, value]) => {
    if (!STATIC_FILTER_KEYS.has(key) && value) params.set(key, value);
  });
  params.set('page', page);
  params.set('per_page', perPage);
  if (sortBy !== 'relevance') params.set('sort_by', sortBy);
  if (sortDir !== 'desc') params.set('sort_dir', sortDir);
  return params.toString();
}

function parseFiltersFromURL(params) {
  const filters = {};
  STATIC_FILTER_KEYS.forEach((key) => { filters[key] = params.get(key) || ''; });
  params.forEach((value, key) => {
    if (!STATIC_FILTER_KEYS.has(key) && !RESERVED_URL_PARAMS.has(key)) {
      filters[key] = value;
    }
  });
  return filters;
}

// ─── buildQueryString ────────────────────────────────────────────────────────

describe('buildQueryString', () => {
  const emptyFilters = () => {
    const f = {};
    STATIC_FILTER_KEYS.forEach((k) => { f[k] = ''; });
    return f;
  };

  it('includes q when provided', () => {
    const qs = buildQueryString('logo', emptyFilters(), 1, 10, 'relevance', 'desc');
    expect(new URLSearchParams(qs).get('q')).toBe('logo');
  });

  it('omits q when empty', () => {
    const qs = buildQueryString('', emptyFilters(), 1, 10, 'relevance', 'desc');
    expect(new URLSearchParams(qs).has('q')).toBe(false);
  });

  it('includes static filter key when set', () => {
    const qs = buildQueryString('', { ...emptyFilters(), mime_group: 'images' }, 1, 10, 'relevance', 'desc');
    expect(new URLSearchParams(qs).get('mime_group')).toBe('images');
  });

  it('omits static filter key when empty string', () => {
    const qs = buildQueryString('', emptyFilters(), 1, 10, 'relevance', 'desc');
    expect(new URLSearchParams(qs).has('mime_group')).toBe(false);
  });

  it('passes dynamic metadata filter (flat key)', () => {
    const filters = { ...emptyFilters(), applied_schema_name: 'PNG' };
    const qs = buildQueryString('', filters, 1, 10, 'relevance', 'desc');
    expect(new URLSearchParams(qs).get('applied_schema_name')).toBe('PNG');
  });

  it('passes dynamic nested metadata filter (dot-separated key)', () => {
    const filters = { ...emptyFilters(), 'editor_state.filter': 'Vivid' };
    const qs = buildQueryString('', filters, 1, 10, 'relevance', 'desc');
    const parsed = new URLSearchParams(qs);
    expect(parsed.get('editor_state.filter')).toBe('Vivid');
  });

  it('does not include dynamic filter when value is empty string', () => {
    const filters = { ...emptyFilters(), 'editor_state.filter': '' };
    const qs = buildQueryString('', filters, 1, 10, 'relevance', 'desc');
    expect(new URLSearchParams(qs).has('editor_state.filter')).toBe(false);
  });

  it('omits sort_by when relevance', () => {
    const qs = buildQueryString('', emptyFilters(), 1, 10, 'relevance', 'desc');
    expect(new URLSearchParams(qs).has('sort_by')).toBe(false);
  });

  it('includes sort_by when not relevance', () => {
    const qs = buildQueryString('', emptyFilters(), 1, 10, 'name', 'asc');
    const p = new URLSearchParams(qs);
    expect(p.get('sort_by')).toBe('name');
    expect(p.get('sort_dir')).toBe('asc');
  });

  it('always includes page and per_page', () => {
    const qs = buildQueryString('', emptyFilters(), 3, 20, 'relevance', 'desc');
    const p = new URLSearchParams(qs);
    expect(p.get('page')).toBe('3');
    expect(p.get('per_page')).toBe('20');
  });

  it('includes mode when set to a non-default value', () => {
    const qs = buildQueryString('sunset', emptyFilters(), 1, 10, 'relevance', 'desc', 'visual');
    expect(new URLSearchParams(qs).get('mode')).toBe('visual');
  });

  it('omits mode when "all" or unset', () => {
    const qsAll = buildQueryString('logo', emptyFilters(), 1, 10, 'relevance', 'desc', 'all');
    const qsUnset = buildQueryString('logo', emptyFilters(), 1, 10, 'relevance', 'desc');
    expect(new URLSearchParams(qsAll).has('mode')).toBe(false);
    expect(new URLSearchParams(qsUnset).has('mode')).toBe(false);
  });
});

// ─── parseFiltersFromURL ─────────────────────────────────────────────────────

describe('parseFiltersFromURL', () => {
  it('initialises all static keys to empty string when params are empty', () => {
    const filters = parseFiltersFromURL(new URLSearchParams());
    STATIC_FILTER_KEYS.forEach((key) => {
      expect(filters[key]).toBe('');
    });
  });

  it('reads a static filter key from URL', () => {
    const filters = parseFiltersFromURL(new URLSearchParams('mime_group=images'));
    expect(filters.mime_group).toBe('images');
  });

  it('parses a flat dynamic filter key from URL', () => {
    const filters = parseFiltersFromURL(new URLSearchParams('applied_schema_name=PNG'));
    expect(filters.applied_schema_name).toBe('PNG');
  });

  it('parses a dot-separated dynamic filter key from URL', () => {
    const params = new URLSearchParams();
    params.set('editor_state.filter', 'Vivid');
    const filters = parseFiltersFromURL(params);
    expect(filters['editor_state.filter']).toBe('Vivid');
  });

  it('does not include reserved params as filter keys', () => {
    const filters = parseFiltersFromURL(new URLSearchParams('q=logo&page=2&sort_by=name&mode=visual'));
    expect(filters.q).toBeUndefined();
    expect(filters.page).toBeUndefined();
    expect(filters.sort_by).toBeUndefined();
    expect(filters.mode).toBeUndefined();
  });

  // Round-trip: build → parse → rebuild should produce same result
  it('round-trips static + dynamic filters through URL', () => {
    const emptyStatic = {};
    STATIC_FILTER_KEYS.forEach((k) => { emptyStatic[k] = ''; });
    const original = {
      ...emptyStatic,
      mime_group: 'images',
      'editor_state.filter': 'Vivid',
      applied_schema_name: 'PNG',
    };
    const qs = buildQueryString('logo', original, 2, 10, 'name', 'asc');
    const parsed = parseFiltersFromURL(new URLSearchParams(qs));
    expect(parsed.mime_group).toBe('images');
    expect(parsed['editor_state.filter']).toBe('Vivid');
    expect(parsed.applied_schema_name).toBe('PNG');
    expect(parsed.q).toBeUndefined(); // reserved
    expect(parsed.page).toBeUndefined(); // reserved
  });
});
