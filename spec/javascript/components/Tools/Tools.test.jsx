import React from 'react';
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react';

const mockNotify = jest.fn();

const translate = (key, fallbackOrOptions) => {
  if (typeof fallbackOrOptions === 'string') return fallbackOrOptions;
  if (fallbackOrOptions && typeof fallbackOrOptions === 'object' && 'defaultValue' in fallbackOrOptions) {
    return fallbackOrOptions.defaultValue;
  }
  return key;
};

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: translate,
    i18n: { language: 'en', changeLanguage: jest.fn() },
  }),
  Trans: ({ i18nKey, defaults }) => defaults || i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('../../../../app/javascript/components/Tools/AssetConfigurations/UploadRestrictions', () => () => (
  <div>Upload Restrictions Panel</div>
));
jest.mock('../../../../app/javascript/components/Tools/AssetConfigurations/ImageProfiles', () => () => (
  <div>Image Profiles Panel</div>
));
jest.mock('../../../../app/javascript/components/Tools/AssetConfigurations/VideoProfiles', () => () => (
  <div>Video Profiles Panel</div>
));
jest.mock('../../../../app/javascript/components/Tools/AssetConfigurations/DuplicateManagerSettings', () => () => (
  <div>Duplicate Manager Settings Panel</div>
));
jest.mock('../../../../app/javascript/components/Tools/AssetConfigurations/BinPurgeSettings', () => () => (
  <div>Bin Purge Settings Panel</div>
));
jest.mock('../../../../app/javascript/components/Tools/AssetConfigurations/CollectionSettings', () => () => (
  <div>Collection Settings Panel</div>
));

import AssetConfigurationsManager from '../../../../app/javascript/components/Tools/AssetConfigurations';
import MetadataExportManager from '../../../../app/javascript/components/Tools/MetadataExport';
import MetadataImportManager from '../../../../app/javascript/components/Tools/MetadataImport';
import MetadataSchemasManager from '../../../../app/javascript/components/Tools/MetadataSchemas';
import NewSchemaDialog from '../../../../app/javascript/components/Tools/MetadataSchemas/NewSchemaDialog';
import SchemaEditorDialog from '../../../../app/javascript/components/Tools/MetadataSchemas/SchemaEditorDialog';

function apiResponse(body, ok = true) {
  return Promise.resolve({
    ok,
    json: () => Promise.resolve(body),
  });
}

function sequence(...items) {
  return { __sequence: items };
}


function createFetchMock(routes) {
  return jest.fn((url, options = {}) => {
    const method = (options.method || 'GET').toUpperCase();
    const routeKey = Object.keys(routes)
      .filter((key) => {
        const [routeMethod, ...routePathParts] = key.split(' ');
        return routeMethod === method && String(url).startsWith(routePathParts.join(' '));
      })
      .sort((a, b) => b.length - a.length)[0];

    if (!routeKey) return apiResponse({});

    const handler = routes[routeKey];
    const value = handler && handler.__sequence ? handler.__sequence.shift() : handler;

    if (typeof value === 'function') return value(url, options);
    if (value && value.__raw) return Promise.resolve(value.response);
    return apiResponse(value);
  });
}

function makeSchema(overrides = {}) {
  return {
    id: 1,
    name: 'Global Schema',
    level: 'root',
    description: 'Default metadata schema',
    folder_count: 1,
    is_builtin: false,
    mime_segment: null,
    tabs: [
      {
        id: 'tab-1',
        name: 'General',
        fields: [{ id: 'field-1', label: 'Title', field_type: 'text', required: true }],
      },
    ],
    resolved_tabs: [
      {
        id: 'tab-1',
        name: 'General',
        fields: [{ id: 'field-1', label: 'Title', field_type: 'text', required: true }],
      },
    ],
    children: [],
    ...overrides,
  };
}

describe('Tools components', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    global.fetch = undefined;
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === 'meta[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
    window.confirm = jest.fn(() => true);

    if (!global.crypto?.randomUUID) {
      Object.defineProperty(global, 'crypto', {
        configurable: true,
        value: {
          randomUUID: () => `uuid-${Math.random().toString(16).slice(2)}`,
        },
      });
    }
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('renders AssetConfigurationsManager and switches mocked panels', async () => {
    render(<AssetConfigurationsManager />);

    expect(screen.getByText('Asset Configurations')).toBeInTheDocument();
    expect(screen.getByText('Upload Restrictions Panel')).toBeInTheDocument();
    expect(screen.getByText('Admin only')).toBeInTheDocument();

    fireEvent.click(screen.getByText('Image Profiles'));
    expect(screen.getByText('Image Profiles Panel')).toBeInTheDocument();
    expect(screen.queryByText('Admin only')).not.toBeInTheDocument();

    fireEvent.click(screen.getByText('Collection Settings'));
    expect(screen.getByText('Collection Settings Panel')).toBeInTheDocument();
  });

  it('renders MetadataExportManager empty state', async () => {
    global.fetch = createFetchMock({
      'GET /api/v1/metadata_exports': { exports: [], meta: { total: 0, page: 1, per_page: 25 } },
      'GET /api/v1/folders': { folders: [] },
    });

    render(<MetadataExportManager />);

    expect(screen.getByText('Metadata Export')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /new export/i })).toBeInTheDocument();
    expect(await screen.findByText(/no exports yet/i)).toBeInTheDocument();
  });

  it('renders completed metadata exports and opens the file menu', async () => {
    const exportRecord = {
      id: 9,
      name: 'marketing_assets',
      status: 'completed',
      folder_name: 'Marketing',
      include_subfolders: true,
      property_mode: 'selective',
      selected_properties: ['dc:title', 'dc:creator'],
      total_assets: 4,
      file_count: 2,
      created_by: 'admin@example.com',
      created_at: 'Jul 1, 2026',
      expires_at: 'Jul 30, 2026',
      files: [
        { id: 1, filename: 'marketing_assets_part1.csv', byte_size: 2048, download_url: '/dl/1' },
        { id: 2, filename: 'marketing_assets_part2.csv', byte_size: 3072, download_url: '/dl/2' },
      ],
    };

    global.fetch = createFetchMock({
      'GET /api/v1/metadata_exports': () => apiResponse({ exports: [exportRecord], meta: { total: 1, page: 1, per_page: 25 } }),
      'GET /api/v1/folders': { folders: [] },
    });

    render(<MetadataExportManager />);

    expect(await screen.findByText('marketing_assets.csv')).toBeInTheDocument();
    expect(screen.getByText('Marketing')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /2 files/i }));

    expect(await screen.findByText('marketing_assets_part1.csv')).toBeInTheDocument();
    expect(screen.getByText('marketing_assets_part2.csv')).toBeInTheDocument();
  });

  it('creates a metadata export from the dialog', async () => {
    const createdExport = {
      id: 10,
      name: 'marketing_assets',
      status: 'pending',
      folder_name: '/ (Root)',
      include_subfolders: true,
      property_mode: 'all',
      selected_properties: [],
      total_assets: 0,
      file_count: 0,
      created_by: 'admin@example.com',
      created_at: 'Jul 1, 2026',
      expires_at: null,
      files: [],
    };
    let postedBody;

    global.fetch = createFetchMock({
      'GET /api/v1/metadata_exports': sequence(
        { exports: [], meta: { total: 0, page: 1, per_page: 25 } },
        { exports: [createdExport], meta: { total: 1, page: 1, per_page: 25 } }
      ),
      'GET /api/v1/folders': { folders: [{ id: 'folder-1', name: 'Marketing' }] },
      'POST /api/v1/metadata_exports': (_, options) => {
        postedBody = JSON.parse(options.body);
        return apiResponse({ id: 10, name: 'marketing_assets' });
      },
    });

    render(<MetadataExportManager />);

    await screen.findByText(/no exports yet/i);
    fireEvent.click(screen.getByRole('button', { name: /new export/i }));
    fireEvent.change(screen.getByLabelText('CSV file name'), { target: { value: 'marketing_assets' } });
    fireEvent.click(screen.getByRole('button', { name: /^export$/i }));

    await waitFor(() => {
      expect(postedBody).toEqual({
        metadata_export: {
          name: 'marketing_assets',
          folder_id: 'root',
          include_subfolders: true,
          property_mode: 'all',
          selected_properties: [],
          scheduled_at: null,
        },
      });
    });

    expect(mockNotify).toHaveBeenCalledWith(
      'Metadata export started. You will be notified when it is ready.',
      'success',
    );
    expect(await screen.findByText('marketing_assets.csv')).toBeInTheDocument();
  });

  it('renders MetadataImportManager import history', async () => {
    global.fetch = createFetchMock({
      'GET /api/v1/metadata_imports': () => apiResponse({
        imports: [{
          id: 5,
          name: 'metadata.csv',
          status: 'completed',
          batch_size: 25,
          field_separator: ',',
          asset_path_column: 'asset_path',
          launch_workflows: true,
          success_count: 12,
          failure_count: 1,
          created_by: 'admin@example.com',
          created_at: 'Jul 1, 2026',
          expires_at: 'Jul 30, 2026',
          source_file: { download_url: '/imports/input.csv' },
          result_file: { download_url: '/imports/results.csv' },
        }],
        meta: { total: 1, page: 1, per_page: 25 },
      }),
    });

    render(<MetadataImportManager />);

    expect(await screen.findByText('metadata.csv')).toBeInTheDocument();
    expect(screen.getByText('12 ok')).toBeInTheDocument();
    expect(screen.getByText('1 fail')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /input/i })).toHaveAttribute('href', '/imports/input.csv');
    expect(screen.getByRole('link', { name: /results/i })).toHaveAttribute('href', '/imports/results.csv');
  });

  it('validates file selection before creating a metadata import', async () => {
    global.fetch = createFetchMock({
      'GET /api/v1/metadata_imports': { imports: [], meta: { total: 0, page: 1, per_page: 25 } },
    });

    render(<MetadataImportManager />);

    await screen.findByText(/no imports yet/i);
    fireEvent.click(screen.getByRole('button', { name: /new import/i }));
    fireEvent.click(screen.getByRole('button', { name: /^import$/i }));

    expect(mockNotify).toHaveBeenCalledWith('Please select a CSV file.', 'warning');
  });

  it('deletes a metadata import entry', async () => {
    const importRecord = {
      id: 6,
      name: 'cleanup.csv',
      status: 'failed',
      batch_size: 10,
      field_separator: ',',
      asset_path_column: 'asset_path',
      launch_workflows: false,
      success_count: 0,
      failure_count: 3,
      error_message: 'Bad metadata',
      created_by: 'admin@example.com',
      created_at: 'Jul 1, 2026',
      expires_at: null,
      source_file: null,
      result_file: null,
    };

    global.fetch = createFetchMock({
      'GET /api/v1/metadata_imports': sequence(
        { imports: [importRecord], meta: { total: 1, page: 1, per_page: 25 } },
        { imports: [], meta: { total: 0, page: 1, per_page: 25 } }
      ),
      'DELETE /api/v1/metadata_imports/6': {},
    });

    render(<MetadataImportManager />);

    const rowText = await screen.findByText('cleanup.csv');
    const row = rowText.closest('tr');
    fireEvent.click(within(row).getByRole('button'));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/metadata_imports/6', expect.objectContaining({
        method: 'DELETE',
      }));
    });
    expect(mockNotify).toHaveBeenCalledWith('Import deleted.', 'success');
  });

  it('renders MetadataSchemasManager tree and selected schema detail', async () => {
    const rootSchema = makeSchema({
      children: [{ id: 2, name: 'Image', level: 'type', mime_segment: 'image', children: [] }],
    });
    const detailedSchema = makeSchema({
      resolved_tabs: [{ id: 'tab-1', name: 'General', fields: [{ id: 'field-1', label: 'Title', field_type: 'text', required: true }] }],
    });

    global.fetch = createFetchMock({
      'GET /api/v1/metadata_schemas/1/folders': () => apiResponse([{ id: 'folder-1', name: 'Marketing' }]),
      'GET /api/v1/metadata_schemas/1': detailedSchema,
      'GET /api/v1/metadata_schemas': () => apiResponse([rootSchema]),
    });

    render(<MetadataSchemasManager />);

    expect(await screen.findByText('Schema Library')).toBeInTheDocument();
    expect(screen.getByText(/select a schema from the tree/i)).toBeInTheDocument();

    fireEvent.click(screen.getByText('Global Schema'));

    expect(await screen.findByRole('heading', { name: 'Global Schema' })).toBeInTheDocument();
    expect(screen.getByText('Default metadata schema')).toBeInTheDocument();
    expect(await screen.findByText('Applied to Folders')).toBeInTheDocument();
    expect(screen.getByText('Marketing')).toBeInTheDocument();
  });

  it('validates and submits NewSchemaDialog payloads', async () => {
    const onCreate = jest.fn().mockResolvedValue(false);

    render(
      <NewSchemaDialog
        open
        onClose={jest.fn()}
        onCreate={onCreate}
        parentSchemas={[makeSchema({ id: 'root-1', name: 'Root Schema', children: [] })]}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: /create schema/i }));
    expect(await screen.findByText('Name is required.')).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText(/^Name/), { target: { value: 'Image Assets' } });
    fireEvent.mouseDown(screen.getByRole('combobox', { name: 'Schema Level' }));
    fireEvent.click(screen.getByRole('option', { name: /type — matches a mime type/i }));
    fireEvent.mouseDown(screen.getByRole('combobox', { name: 'Parent Schema' }));
    fireEvent.click(screen.getByRole('option', { name: 'Root Schema' }));
    fireEvent.change(await screen.findByLabelText(/^MIME Segment/), { target: { value: 'IMAGE' } });
    fireEvent.click(screen.getByRole('button', { name: /create schema/i }));

    await waitFor(() => {
      expect(onCreate).toHaveBeenCalledWith({
        name: 'Image Assets',
        description: null,
        level: 'type',
        parent_id: 'root-1',
        mime_segment: 'image',
        inherits_from_id: null,
        tabs: [],
      });
    });
  });

  it('shows Level and Inherit From next to the schema name on the same line', () => {
    render(
      <SchemaEditorDialog
        schema={makeSchema({ id: 99, tabs: [], resolved_tabs: [], level: 'root' })}
        onClose={jest.fn()}
        onSave={jest.fn()}
      />,
    );

    const nameField = screen.getByTestId('schema-editor-name');
    const levelCaption = screen.getByTestId('schema-editor-level');
    const inheritFromControl = screen.getByTestId('schema-editor-inherit-from');
    expect(levelCaption).toHaveTextContent('Level: root');
    // Name, Level, and Inherit From all live in the same flex row container.
    const row = levelCaption.parentElement;
    expect(nameField.parentElement).toBe(row);
    expect(row).toContainElement(inheritFromControl);
  });

  it('renders the schema editor as three columns: inherited fields, custom fields, and field settings', async () => {
    const schema = makeSchema({
      id: 99,
      tabs: [
        {
          id: 'tab-own', name: 'Custom Tab',
          fields: [{ id: 'field-own', label: 'Custom Title', field_type: 'text', required: false }],
        },
      ],
      resolved_tabs: [
        {
          id: 'tab-inherited', name: 'Basic', inherited: true, schema_name: 'Default',
          fields: [{ id: 'field-inherited', label: 'Inherited Title', field_type: 'text', inherited: true, map_to_property: 'dc:title' }],
        },
        {
          id: 'tab-own', name: 'Custom Tab',
          fields: [{ id: 'field-own', label: 'Custom Title', field_type: 'text', required: false }],
        },
      ],
    });

    render(
      <SchemaEditorDialog
        schema={schema}
        onClose={jest.fn()}
        onSave={jest.fn()}
      />,
    );

    const inheritedColumn = screen.getByTestId('inherited-fields-column');
    const customColumn    = screen.getByTestId('custom-fields-column');
    const editorColumn    = screen.getByTestId('field-editor-column');

    expect(inheritedColumn).toHaveTextContent('Inherited Fields');
    expect(inheritedColumn).toHaveTextContent('Inherited Title');
    expect(customColumn).toHaveTextContent('Custom Fields');
    expect(customColumn).toHaveTextContent('Custom Title');
    expect(editorColumn).toHaveTextContent(/select a field to edit its settings/i);

    // Inherited fields are not selectable — clicking one does not open the editor.
    fireEvent.click(within(inheritedColumn).getByText('Inherited Title'));
    expect(editorColumn).toHaveTextContent(/select a field to edit its settings/i);

    // Custom fields ARE selectable — clicking one opens the field editor.
    fireEvent.click(within(customColumn).getByText('Custom Title'));
    expect(editorColumn).toHaveTextContent('Field Settings');
    expect(editorColumn).not.toHaveTextContent(/select a field to edit its settings/i);
  });

  it('lets SchemaEditorDialog add fields and save normalized tabs', async () => {
    const onSave = jest.fn().mockResolvedValue(true);

    render(
      <SchemaEditorDialog
        schema={makeSchema({ id: 99, tabs: [], resolved_tabs: [] })}
        onClose={jest.fn()}
        onSave={onSave}
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: /add tab/i }));
    fireEvent.change(screen.getByPlaceholderText('Tab name'), { target: { value: 'General' } });
    fireEvent.keyDown(screen.getByPlaceholderText('Tab name'), { key: 'Enter', code: 'Enter' });
    fireEvent.click(screen.getByRole('button', { name: /add field/i }));

    fireEvent.change(screen.getByLabelText('Field Label'), { target: { value: 'Title' } });
    fireEvent.change(screen.getByLabelText('Map to Property'), { target: { value: 'dc:title' } });
    fireEvent.click(screen.getByRole('switch', { name: /Required/ }));
    fireEvent.click(screen.getByRole('button', { name: /save schema/i }));

    await waitFor(() => {
      expect(onSave).toHaveBeenCalledWith(
        99,
        expect.objectContaining({
          tabs: [
            expect.objectContaining({
              name: 'General',
              position: 0,
              fields: [
                expect.objectContaining({
                  label: 'Title',
                  map_to_property: 'dc:title',
                  field_type: 'text',
                  required: true,
                  position: 0,
                }),
              ],
            }),
          ],
        }),
      );
    });
  });

  it('lets SchemaEditorDialog rename a schema and save the new name', async () => {
    const onSave = jest.fn().mockResolvedValue(true);

    render(
      <SchemaEditorDialog
        schema={makeSchema({ id: 99, tabs: [], resolved_tabs: [] })}
        onClose={jest.fn()}
        onSave={onSave}
      />,
    );

    const nameField = screen.getByTestId('schema-editor-name').querySelector('input');
    fireEvent.change(nameField, { target: { value: 'Renamed Schema' } });
    fireEvent.click(screen.getByRole('button', { name: /save schema/i }));

    await waitFor(() => {
      expect(onSave).toHaveBeenCalledWith(
        99,
        expect.objectContaining({ name: 'Renamed Schema' }),
      );
    });
  });

  it('rejects a blank name in SchemaEditorDialog without calling onSave', async () => {
    const onSave = jest.fn();

    render(
      <SchemaEditorDialog
        schema={makeSchema({ id: 99, tabs: [], resolved_tabs: [] })}
        onClose={jest.fn()}
        onSave={onSave}
      />,
    );

    const nameField = screen.getByTestId('schema-editor-name').querySelector('input');
    fireEvent.change(nameField, { target: { value: '   ' } });
    fireEvent.click(screen.getByRole('button', { name: /save schema/i }));

    expect(await screen.findByText(/name is required/i)).toBeInTheDocument();
    expect(onSave).not.toHaveBeenCalled();
  });

  it('lets SchemaEditorDialog pick an Inherit From root schema and save it', async () => {
    const onSave = jest.fn().mockResolvedValue(true);
    const otherRoot = makeSchema({ id: 5, name: 'Default', level: 'root' });

    render(
      <SchemaEditorDialog
        schema={makeSchema({ id: 99, tabs: [], resolved_tabs: [], level: 'root' })}
        onClose={jest.fn()}
        onSave={onSave}
        rootSchemas={[otherRoot, makeSchema({ id: 99, level: 'root' })]}
      />,
    );

    fireEvent.mouseDown(screen.getByTestId('schema-editor-inherit-from').querySelector('[role="combobox"]'));
    fireEvent.click(screen.getByRole('option', { name: 'Default' }));
    fireEvent.click(screen.getByRole('button', { name: /save schema/i }));

    await waitFor(() => {
      expect(onSave).toHaveBeenCalledWith(
        99,
        expect.objectContaining({ inherits_from_id: 5 }),
      );
    });
  });

  it('hides the Inherit From dropdown for built-in root schemas (they cannot inherit from each other)', () => {
    const otherRoot = makeSchema({ id: 5, name: 'Default', level: 'root' });

    render(
      <SchemaEditorDialog
        schema={makeSchema({ id: 6, name: 'Collection', tabs: [], resolved_tabs: [], level: 'root', is_builtin: true })}
        onClose={jest.fn()}
        onSave={jest.fn()}
        rootSchemas={[otherRoot]}
      />,
    );

    expect(screen.queryByTestId('schema-editor-inherit-from')).not.toBeInTheDocument();
    expect(screen.getByTestId('builtin-no-inherit-note')).toBeInTheDocument();
  });

  it('disables editing controls in SchemaEditorDialog when canManage is false', () => {
    render(
      <SchemaEditorDialog
        schema={makeSchema({ id: 99, tabs: [], resolved_tabs: [], level: 'root' })}
        onClose={jest.fn()}
        onSave={jest.fn()}
        rootSchemas={[]}
        canManage={false}
      />,
    );

    expect(screen.getByTestId('schema-editor-name').querySelector('input')).toBeDisabled();
    expect(screen.getByRole('button', { name: /save schema/i })).toBeDisabled();
  });

  it('sends inherits_from_id when creating a root schema via NewSchemaDialog', async () => {
    const onCreate = jest.fn().mockResolvedValue(true);
    const otherRoot = makeSchema({ id: 'root-1', name: 'Root Schema', level: 'root', children: [] });

    render(
      <NewSchemaDialog
        open
        onClose={jest.fn()}
        onCreate={onCreate}
        parentSchemas={[otherRoot]}
      />,
    );

    fireEvent.change(screen.getByLabelText(/^Name/), { target: { value: 'Custom Product Schema' } });
    fireEvent.mouseDown(screen.getByTestId('new-schema-inherit-from').querySelector('[role="combobox"]'));
    fireEvent.click(screen.getByRole('option', { name: 'Root Schema' }));
    fireEvent.click(screen.getByRole('button', { name: /create schema/i }));

    await waitFor(() => {
      expect(onCreate).toHaveBeenCalledWith(
        expect.objectContaining({
          name: 'Custom Product Schema',
          level: 'root',
          inherits_from_id: 'root-1',
        }),
      );
    });
  });

  it('shows an inheritance chip and hides manage actions for read-only MetadataSchemasManager users', async () => {
    const rootSchema = makeSchema({
      inherits_from_name: 'Default',
      children: [],
    });

    global.fetch = createFetchMock({
      'GET /api/v1/metadata_schemas/1/folders': () => apiResponse([]),
      'GET /api/v1/metadata_schemas/1': rootSchema,
      'GET /api/v1/metadata_schemas': () => apiResponse([rootSchema]),
    });

    render(<MetadataSchemasManager canManageSchemas={false} />);

    expect(await screen.findByText('Schema Library')).toBeInTheDocument();
    expect(screen.queryByTestId('new-schema-button')).not.toBeInTheDocument();
    expect(await screen.findByTestId('read-only-banner')).toBeInTheDocument();

    fireEvent.click(screen.getByText('Global Schema'));

    expect(await screen.findByTestId('schema-inherits-chip')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /edit/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /duplicate/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /delete/i })).not.toBeInTheDocument();
  });

  it('shows the "Create new root schema" button for MetadataSchemasManager managers', async () => {
    const rootSchema = makeSchema({ children: [] });

    global.fetch = createFetchMock({
      'GET /api/v1/metadata_schemas/1/folders': () => apiResponse([]),
      'GET /api/v1/metadata_schemas/1': rootSchema,
      'GET /api/v1/metadata_schemas': () => apiResponse([rootSchema]),
    });

    render(<MetadataSchemasManager canManageSchemas="true" />);

    expect(await screen.findByTestId('new-schema-button')).toBeInTheDocument();
    expect(screen.queryByTestId('read-only-banner')).not.toBeInTheDocument();
  });
});
