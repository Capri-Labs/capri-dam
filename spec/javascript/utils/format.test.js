import { humanFileSize, csrfToken, parseCsvHeader } from '../../../app/javascript/utils/format';

describe('humanFileSize', () => {
  it('formats bytes into human-readable units', () => {
    expect(humanFileSize(0)).toBe('0 B');
    expect(humanFileSize(512)).toBe('512 B');
    expect(humanFileSize(1024)).toBe('1.0 KB');
    expect(humanFileSize(1536)).toBe('1.5 KB');
    expect(humanFileSize(1048576)).toBe('1.0 MB');
    expect(humanFileSize(5 * 1024 * 1024 * 1024)).toBe('5.0 GB');
  });

  it('returns an empty string for nullish / NaN input', () => {
    expect(humanFileSize(null)).toBe('');
    expect(humanFileSize(undefined)).toBe('');
    expect(humanFileSize(NaN)).toBe('');
  });
});

describe('csrfToken', () => {
  afterEach(() => {
    document.head.innerHTML = '';
  });

  it('reads the token from the meta tag', () => {
    const meta = document.createElement('meta');
    meta.name = 'csrf-token';
    meta.content = 'abc123';
    document.head.appendChild(meta);
    expect(csrfToken()).toBe('abc123');
  });

  it('returns undefined when the meta tag is absent', () => {
    expect(csrfToken()).toBeUndefined();
  });
});

describe('parseCsvHeader', () => {
  it('splits, trims and de-quotes header columns', () => {
    expect(parseCsvHeader('asset_path, "copyright" , tags')).toEqual([
      'asset_path',
      'copyright',
      'tags'
    ]);
  });

  it('honours a custom separator', () => {
    expect(parseCsvHeader('a;b;c', ';')).toEqual(['a', 'b', 'c']);
  });

  it('returns an empty array for empty input', () => {
    expect(parseCsvHeader('')).toEqual([]);
    expect(parseCsvHeader(undefined)).toEqual([]);
  });
});

