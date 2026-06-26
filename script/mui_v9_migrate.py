#!/usr/bin/env python3
"""
MUI v9 migration script for Capri DAM.

Fixes:
1. <Grid item xs={N} md={M}> → <Grid size={{ xs: N, md: M }}>  (removes `item` prop)
2. primaryTypographyProps={{...}} → slotProps={{ primary: {...} }}
3. secondaryTypographyProps={{...}} → slotProps={{ secondary: {...} }}
4. justifyContent={{ xs: '...', md: '...' }} (responsive obj as direct Grid prop)
   → sx={{ justifyContent: { xs: '...', md: '...' } }}
"""
import re
import glob
import sys

# ── Grid item → size conversion ──────────────────────────────────────────────

BREAKPOINTS = ['xs', 'sm', 'md', 'lg', 'xl']

def convert_grid_item(m):
    """
    Converts a single matched Grid item tag to Grid2 API.
    Input example:  <Grid item xs={12} sm={6} md={4} lg={3} key={i}>
    Output example: <Grid size={{ xs: 12, sm: 6, md: 4, lg: 3 }} key={i}>
    """
    original = m.group(0)
    tag = original

    # Extract breakpoint values before we mutate the string
    bp_vals = {}
    for bp in BREAKPOINTS:
        bp_m = re.search(rf'\b{bp}={{([^}}]+)}}', tag)
        if bp_m:
            bp_vals[bp] = bp_m.group(1).strip()

    # Remove `item` keyword (as a prop, preceded by whitespace)
    tag = re.sub(r'(?<=\s)item(?=[\s/])', '', tag)

    # Remove breakpoint props
    for bp in BREAKPOINTS:
        tag = re.sub(rf'\s+{bp}={{[^}}]+}}', '', tag)

    # Build size prop value
    if not bp_vals:
        # No breakpoints found — just remove `item`
        return tag

    if len(bp_vals) == 1 and 'xs' in bp_vals:
        # Single breakpoint: use shorthand  size={N}
        size_str = f'size={{{bp_vals["xs"]}}}'
    else:
        # Multiple breakpoints: use object  size={{ xs: N, md: M }}
        pairs = ', '.join(f'{k}: {v}' for k, v in bp_vals.items())
        size_str = f'size={{{{ {pairs} }}}}'

    # Insert size prop right after `<Grid`
    tag = re.sub(r'<Grid\b', f'<Grid {size_str}', tag, count=1)
    # Clean up double spaces that can appear
    tag = re.sub(r'  +', ' ', tag)

    return tag


# Pattern: <Grid item ...> on a single line (handles props inline)
GRID_ITEM_RE = re.compile(
    r'<Grid\s+(?:[^>]*?\s)?item(?:\s+[^>]*)?>',
    re.MULTILINE,
)

def fix_grid_items(src):
    return GRID_ITEM_RE.sub(convert_grid_item, src)


# ── justifyContent responsive object → sx ────────────────────────────────────
# Matches:  justifyContent={{ xs: '...', md: '...' }}
# on a <Grid ... > tag (not inside sx={{ }})
# Strategy: find the pattern in the full file and rewrite the attribute.

RESPONSIVE_JC_RE = re.compile(
    r'justifyContent=\{(\{[^}]+\})\}(?=\s+(?:[a-zA-Z]|>|/))',
)

def fix_responsive_justifycontent(src):
    """
    Converts justifyContent={{ xs: '...', md: '...' }} (responsive object)
    passed as a direct Grid prop into sx={{ justifyContent: { ... } }}.

    Simple string values like justifyContent="space-between" are left alone.
    """
    def replace_jc(m):
        inner = m.group(1)  # The  { xs: 'flex-start', md: 'flex-end' }  part
        # Verify it contains responsive keys (xs, sm, md, lg, xl)
        if not re.search(r'\b(?:xs|sm|md|lg|xl)\s*:', inner):
            return m.group(0)  # Not responsive — leave it
        return f'sx={{{{ justifyContent: {inner} }}}}'

    return RESPONSIVE_JC_RE.sub(replace_jc, src)


# ── primaryTypographyProps → slotProps.primary ────────────────────────────────

PRIMARY_RE = re.compile(
    r'primaryTypographyProps=(\{(?:[^{}]|\{[^{}]*\})*\})',
)

def fix_primary_typography_props(src):
    def replace_primary(m):
        inner = m.group(1)  # e.g. {{ variant: 'body2', fontWeight: 600 }}
        # inner already has outer braces from the JSX expression {}
        # Remove one layer:  {  { ... }  } → { ... }
        unwrapped = inner.strip()
        if unwrapped.startswith('{') and unwrapped.endswith('}'):
            obj = unwrapped[1:-1].strip()
        else:
            obj = unwrapped
        return f'slotProps={{{{ primary: {{{obj}}} }}}}'
    return PRIMARY_RE.sub(replace_primary, src)


SECONDARY_RE = re.compile(
    r'secondaryTypographyProps=(\{(?:[^{}]|\{[^{}]*\})*\})',
)

def fix_secondary_typography_props(src):
    def replace_secondary(m):
        inner = m.group(1)
        unwrapped = inner.strip()
        if unwrapped.startswith('{') and unwrapped.endswith('}'):
            obj = unwrapped[1:-1].strip()
        else:
            obj = unwrapped
        return f'slotProps={{{{ secondary: {{{obj}}} }}}}'
    return SECONDARY_RE.sub(replace_secondary, src)


# ── Merge duplicate slotProps (when a component already has slotProps) ────────

def merge_slot_props(src):
    """
    When a ListItemText ends up with two separate slotProps={{ ... }} attributes
    (one from primary, one from secondary), merge them into one.
    This handles the edge case where both primaryTypographyProps and
    secondaryTypographyProps appear on the same element.
    """
    # Simple pattern: two adjacent slotProps on same element
    DOUBLE_SLOT_RE = re.compile(
        r'slotProps=\{\{([^}]*)\}\}\s+slotProps=\{\{([^}]*)\}\}',
    )
    def merge(m):
        a = m.group(1).strip().rstrip(',')
        b = m.group(2).strip().rstrip(',')
        merged = f'{a}, {b}'
        return f'slotProps={{{{ {merged} }}}}'
    return DOUBLE_SLOT_RE.sub(merge, src)


# ── Main ──────────────────────────────────────────────────────────────────────

def transform_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        original = f.read()

    src = original
    src = fix_grid_items(src)
    src = fix_responsive_justifycontent(src)
    src = fix_primary_typography_props(src)
    src = fix_secondary_typography_props(src)
    src = merge_slot_props(src)

    if src != original:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(src)
        return True
    return False


if __name__ == '__main__':
    jsx_files = glob.glob('app/javascript/**/*.jsx', recursive=True)
    changed = 0
    for path in sorted(jsx_files):
        if transform_file(path):
            print(f'  Fixed: {path}')
            changed += 1
    print(f'\nDone — {changed} file(s) updated.')

