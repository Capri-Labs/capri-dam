import React from 'react';
import { render, screen, fireEvent, act } from '@testing-library/react';
import RichTextEditor from '../../../../app/javascript/components/Shared/RichTextEditor';

let mockCapturedConfig;
const chain = {
  focus: jest.fn(() => chain),
  undo: jest.fn(() => chain),
  redo: jest.fn(() => chain),
  toggleBold: jest.fn(() => chain),
  toggleItalic: jest.fn(() => chain),
  toggleUnderline: jest.fn(() => chain),
  toggleStrike: jest.fn(() => chain),
  toggleHeading: jest.fn(() => chain),
  setTextAlign: jest.fn(() => chain),
  toggleBulletList: jest.fn(() => chain),
  toggleOrderedList: jest.fn(() => chain),
  toggleBlockquote: jest.fn(() => chain),
  toggleCode: jest.fn(() => chain),
  extendMarkRange: jest.fn(() => chain),
  unsetLink: jest.fn(() => chain),
  setLink: jest.fn(() => chain),
  setImage: jest.fn(() => chain),
  setHorizontalRule: jest.fn(() => chain),
  run: jest.fn(() => true),
};

const mockEditor = {
  chain: jest.fn(() => chain),
  can: jest.fn(() => ({ undo: () => true, redo: () => true })),
  isActive: jest.fn(() => false),
  getAttributes: jest.fn(() => ({ href: 'https://example.com' })),
  getHTML: jest.fn(() => '<p>Initial</p>'),
  commands: { setContent: jest.fn() },
};

jest.mock('@tiptap/react', () => ({
  useEditor: jest.fn((config) => {
    mockCapturedConfig = config;
    return mockEditor;
  }),
  EditorContent: () => <div data-testid="editor-content">editor area</div>,
}));
jest.mock('@tiptap/starter-kit', () => ({}));
jest.mock('@tiptap/extension-underline', () => ({}));
jest.mock('@tiptap/extension-text-align', () => ({ configure: jest.fn(() => ({})) }));
jest.mock('@tiptap/extension-link', () => ({ configure: jest.fn(() => ({})) }));
jest.mock('@tiptap/extension-image', () => ({ configure: jest.fn(() => ({})) }));

describe('RichTextEditor', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    window.prompt = jest.fn(() => 'https://example.com');
  });

  it('renders the toolbar and editor area', () => {
    render(<RichTextEditor value="<p>Initial</p>" onChange={jest.fn()} />);

    expect(screen.getByTestId('editor-content')).toBeInTheDocument();
    expect(screen.getAllByRole('button').length).toBeGreaterThan(5);
  });

  it('runs editor commands from the toolbar', () => {
    render(<RichTextEditor value="<p>Initial</p>" onChange={jest.fn()} />);

    fireEvent.click(screen.getAllByRole('button')[2]);
    expect(chain.toggleBold).toHaveBeenCalled();
    expect(chain.run).toHaveBeenCalled();
  });

  it('fires onChange when the editor updates and syncs external value changes', () => {
    const onChange = jest.fn();
    const { rerender } = render(<RichTextEditor value="<p>Initial</p>" onChange={onChange} />);

    act(() => mockCapturedConfig.onUpdate({ editor: { getHTML: () => '<p>Updated</p>' } }));
    expect(onChange).toHaveBeenCalledWith('<p>Updated</p>');

    rerender(<RichTextEditor value="<p>External</p>" onChange={onChange} />);
    expect(mockEditor.commands.setContent).toHaveBeenCalledWith('<p>External</p>');
  });
});
