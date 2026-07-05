import React, { useEffect, useCallback } from 'react';
import { useEditor, EditorContent } from '@tiptap/react';
import { Extension } from '@tiptap/core';
import StarterKit from '@tiptap/starter-kit';
import Underline from '@tiptap/extension-underline';
import TextAlign from '@tiptap/extension-text-align';
import Link from '@tiptap/extension-link';
import Image from '@tiptap/extension-image';
import { Table } from '@tiptap/extension-table';
import TableRow from '@tiptap/extension-table-row';
import TableHeader from '@tiptap/extension-table-header';
import TableCell from '@tiptap/extension-table-cell';

import { Box, ToggleButton, ToggleButtonGroup, Divider, IconButton, Tooltip } from '@mui/material';
import {
    FormatBold, FormatItalic, FormatUnderlined, FormatStrikethrough, Code,
    FormatAlignLeft, FormatAlignCenter, FormatAlignRight, FormatAlignJustify,
    FormatListBulleted, FormatListNumbered, FormatQuote, HorizontalRule,
    Link as LinkIcon, LinkOff, Image as ImageIcon, Undo, Redo, Title,
    TableChart, BorderAll
} from '@mui/icons-material';

// Node types that appear throughout the DAM's pre-built email design
// library (see EmailTemplateDesignLibrary), all of which rely on inline
// `style="..."` attributes (colors, padding, backgrounds, button styling)
// for cross-client rendering. Tiptap's node specs do not preserve arbitrary
// attributes by default, so without this extension every inline style is
// silently stripped the moment a design is loaded into the editor -- the
// layout survives (thanks to the Table extensions above) but renders
// unstyled/black-and-white, which is what "preview was broken" reports.
const STYLE_PRESERVING_TYPES = [
    'paragraph', 'heading', 'table', 'tableRow', 'tableCell', 'tableHeader',
    'listItem', 'bulletList', 'orderedList', 'blockquote', 'image', 'link',
];

const PreserveInlineStyle = Extension.create({
    name: 'preserveInlineStyle',
    addGlobalAttributes() {
        return [
            {
                types: STYLE_PRESERVING_TYPES,
                attributes: {
                    style: {
                        default: null,
                        parseHTML: element => element.getAttribute('style'),
                        renderHTML: attributes => (attributes.style ? { style: attributes.style } : {}),
                    },
                },
            },
        ];
    },
});

const MenuBar = ({ editor }) => {
    if (!editor) return null;

    // Handlers for Links and Images
    const setLink = useCallback(() => {
        const previousUrl = editor.getAttributes('link').href;
        const url = window.prompt('Enter the URL', previousUrl);
        if (url === null) return; // cancelled
        if (url === '') {
            editor.chain().focus().extendMarkRange('link').unsetLink().run();
            return;
        }
        editor.chain().focus().extendMarkRange('link').setLink({ href: url }).run();
    }, [editor]);

    const addImage = useCallback(() => {
        const url = window.prompt('Enter image URL (Later, this will connect to the DAM Asset Browser):');
        if (url) {
            editor.chain().focus().setImage({ src: url }).run();
        }
    }, [editor]);

    return (
        <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 1, p: 1, borderBottom: '1px solid #e3e8ef', bgcolor: '#f8f9fa' }}>

            {/* History Group */}
            <ToggleButtonGroup size="small">
                <Tooltip title="Undo"><ToggleButton value="undo" onClick={() => editor.chain().focus().undo().run()} disabled={!editor.can().undo()}><Undo fontSize="small" /></ToggleButton></Tooltip>
                <Tooltip title="Redo"><ToggleButton value="redo" onClick={() => editor.chain().focus().redo().run()} disabled={!editor.can().redo()}><Redo fontSize="small" /></ToggleButton></Tooltip>
            </ToggleButtonGroup>

            <Divider orientation="vertical" flexItem />

            {/* Formatting Group */}
            <ToggleButtonGroup size="small">
                <Tooltip title="Bold"><ToggleButton value="bold" selected={editor.isActive('bold')} onClick={() => editor.chain().focus().toggleBold().run()}><FormatBold fontSize="small" /></ToggleButton></Tooltip>
                <Tooltip title="Italic"><ToggleButton value="italic" selected={editor.isActive('italic')} onClick={() => editor.chain().focus().toggleItalic().run()}><FormatItalic fontSize="small" /></ToggleButton></Tooltip>
                <Tooltip title="Underline"><ToggleButton value="underline" selected={editor.isActive('underline')} onClick={() => editor.chain().focus().toggleUnderline().run()}><FormatUnderlined fontSize="small" /></ToggleButton></Tooltip>
                <Tooltip title="Strikethrough"><ToggleButton value="strike" selected={editor.isActive('strike')} onClick={() => editor.chain().focus().toggleStrike().run()}><FormatStrikethrough fontSize="small" /></ToggleButton></Tooltip>
                <Tooltip title="Heading 2"><ToggleButton value="h2" selected={editor.isActive('heading', { level: 2 })} onClick={() => editor.chain().focus().toggleHeading({ level: 2 }).run()}><Title fontSize="small" /></ToggleButton></Tooltip>
            </ToggleButtonGroup>

            <Divider orientation="vertical" flexItem />

            {/* Alignment Group */}
            <ToggleButtonGroup size="small">
                <Tooltip title="Align Left"><ToggleButton value="left" selected={editor.isActive({ textAlign: 'left' })} onClick={() => editor.chain().focus().setTextAlign('left').run()}><FormatAlignLeft fontSize="small" /></ToggleButton></Tooltip>
                <Tooltip title="Align Center"><ToggleButton value="center" selected={editor.isActive({ textAlign: 'center' })} onClick={() => editor.chain().focus().setTextAlign('center').run()}><FormatAlignCenter fontSize="small" /></ToggleButton></Tooltip>
                <Tooltip title="Align Right"><ToggleButton value="right" selected={editor.isActive({ textAlign: 'right' })} onClick={() => editor.chain().focus().setTextAlign('right').run()}><FormatAlignRight fontSize="small" /></ToggleButton></Tooltip>
            </ToggleButtonGroup>

            <Divider orientation="vertical" flexItem />

            {/* Lists & Blocks Group */}
            <ToggleButtonGroup size="small">
                <Tooltip title="Bullet List"><ToggleButton value="bullet" selected={editor.isActive('bulletList')} onClick={() => editor.chain().focus().toggleBulletList().run()}><FormatListBulleted fontSize="small" /></ToggleButton></Tooltip>
                <Tooltip title="Numbered List"><ToggleButton value="ordered" selected={editor.isActive('orderedList')} onClick={() => editor.chain().focus().toggleOrderedList().run()}><FormatListNumbered fontSize="small" /></ToggleButton></Tooltip>
                <Tooltip title="Quote"><ToggleButton value="quote" selected={editor.isActive('blockquote')} onClick={() => editor.chain().focus().toggleBlockquote().run()}><FormatQuote fontSize="small" /></ToggleButton></Tooltip>
                <Tooltip title="Code Snippet"><ToggleButton value="code" selected={editor.isActive('code')} onClick={() => editor.chain().focus().toggleCode().run()}><Code fontSize="small" /></ToggleButton></Tooltip>
            </ToggleButtonGroup>

            <Divider orientation="vertical" flexItem />

            {/* Inserts Group */}
            <Box sx={{ display: 'flex', gap: 0.5 }}>
                <Tooltip title="Insert Link">
                    <IconButton size="small" onClick={setLink} color={editor.isActive('link') ? 'primary' : 'default'}><LinkIcon fontSize="small" /></IconButton>
                </Tooltip>
                <Tooltip title="Remove Link">
                    <IconButton size="small" onClick={() => editor.chain().focus().unsetLink().run()} disabled={!editor.isActive('link')}><LinkOff fontSize="small" /></IconButton>
                </Tooltip>
                <Tooltip title="Insert Image">
                    <IconButton size="small" onClick={addImage}><ImageIcon fontSize="small" /></IconButton>
                </Tooltip>
                <Tooltip title="Horizontal Line">
                    <IconButton size="small" onClick={() => editor.chain().focus().setHorizontalRule().run()}><HorizontalRule fontSize="small" /></IconButton>
                </Tooltip>
                <Tooltip title="Insert Table">
                    <IconButton size="small" onClick={() => editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run()}><TableChart fontSize="small" /></IconButton>
                </Tooltip>
                <Tooltip title="Delete Table">
                    <IconButton size="small" onClick={() => editor.chain().focus().deleteTable().run()} disabled={!editor.isActive('table')}><BorderAll fontSize="small" /></IconButton>
                </Tooltip>
            </Box>
        </Box>
    );
};

export default function RichTextEditor({ value, onChange }) {
    const editor = useEditor({
        extensions: [
            StarterKit,
            Underline,
            Image.configure({
                inline: true,
                allowBase64: true,
            }),
            Link.configure({
                openOnClick: false, // Prevents admins from accidentally clicking away while editing
            }),
            TextAlign.configure({
                types: ['heading', 'paragraph'], // Allows aligning text and headers
            }),
            // Email designs are table-based layouts (the only markup that
            // renders consistently across email clients). Without these
            // nodes, ProseMirror's schema has no rule for <table>/<tr>/<td>
            // and silently flattens them into plain paragraphs, corrupting
            // the layout the moment a template design is loaded or edited.
            Table.configure({ resizable: true }),
            TableRow,
            TableHeader,
            TableCell,
            PreserveInlineStyle,
        ],
        content: value,
        onUpdate: ({ editor }) => {
            onChange(editor.getHTML());
        },
    });

    useEffect(() => {
        if (editor && value !== editor.getHTML()) {
            editor.commands.setContent(value);
        }
    }, [value, editor]);

    return (
        <Box sx={{
            border: '1px solid #c4c4c4',
            borderRadius: 1,
            overflow: 'hidden',
            display: 'flex',
            flexDirection: 'column',
            '&:hover': { borderColor: '#212121' },
            '&:focus-within': { borderColor: 'primary.main', borderWidth: '2px', m: '-1px' },

            // ProseMirror Content Styling
            '& .ProseMirror': {
                p: 2,
                minHeight: '250px',
                outline: 'none',
                fontFamily: 'Roboto, Helvetica, Arial, sans-serif',
                fontSize: '1rem',
                lineHeight: 1.5,
                flexGrow: 1,

                // Style resets to ensure the editor looks exactly like the final email
                '& p': { mt: 0, mb: 1.5 },
                '& ul, & ol': { mt: 0, mb: 1.5, pl: 3 },
                '& h2': { mt: 2, mb: 1, fontSize: '1.5rem', fontWeight: 700 },
                '& a': { color: 'primary.main', textDecoration: 'underline', cursor: 'pointer' },
                '& blockquote': { borderLeft: '4px solid #e3e8ef', pl: 2, ml: 0, color: 'text.secondary', fontStyle: 'italic' },
                '& img': { maxWidth: '100%', height: 'auto', borderRadius: 1 },
                '& hr': { border: 'none', borderTop: '1px solid #e3e8ef', my: 2 },
                // Keeps the DAM-provided design library's table layouts
                // (buttons, header bands, columns) visible while editing
                // instead of collapsing to unstyled borderless grids.
                '& table': { borderCollapse: 'collapse', width: '100%', my: 1 },
                '& td, & th': { border: '1px dashed #c4c4c4', p: 1, verticalAlign: 'top' },
            }
        }}>
            <MenuBar editor={editor} />
            <EditorContent editor={editor} style={{ display: 'flex', flexDirection: 'column', flexGrow: 1 }} />
        </Box>
    );
}