import React from 'react';
import { render, screen, waitFor, fireEvent, within, act } from '@testing-library/react';

const mockNotify = jest.fn();

const translate = (key, options = {}) => {
  if (options?.name) return `${key}:${options.name}`;
  return key;
};

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: translate }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

import BatchPipelineTimeline from '../../../../app/javascript/components/Admin/Migrations/BatchPipelineTimeline';
import BatchReviewWorkspace from '../../../../app/javascript/components/Admin/Migrations/BatchReviewWorkspace';
import ConnectorCard from '../../../../app/javascript/components/Admin/Migrations/ConnectorCard';
import ConnectorDialog from '../../../../app/javascript/components/Admin/Migrations/ConnectorDialog';
import ConnectorsTopBar from '../../../../app/javascript/components/Admin/Migrations/ConnectorsTopBar';
import DataHealthDashboard from '../../../../app/javascript/components/Admin/Migrations/DataHealthDashboard';
import IngestionDashboard from '../../../../app/javascript/components/Admin/Migrations/IngestionDashboard';
import NewMigrationDialog from '../../../../app/javascript/components/Admin/Migrations/NewMigrationDialog';
import SystemConnectors from '../../../../app/javascript/components/Admin/Migrations/SystemConnectors';

const systemConnector = {
  id: 1,
  provider_type: 'AEM',
  name: 'AEM Source',
  endpoint: 'https://aem.example.com',
  auth_token: '',
  status: 'active',
  tdm_sanitation: true,
  assets_imported: 12,
  webhook_secret: 'super-secret',
  analysis_report: { total_found: 300, missing_tags: 8, estimated_size_gb: 4.2 },
};

const folderList = [
  { id: 'f1', name: 'Marketing', path: '/Marketing', slug: 'marketing' },
  { id: 'f2', name: 'Campaigns', path: '/Marketing/Campaigns', slug: 'campaigns' },
];

const batchList = [
  {
    id: 42,
    name: 'Review Batch',
    source_label: 'Adobe Experience Manager',
    source_type: 'aem',
    connector_name: 'AEM Source',
    status: 'review_needed',
    total_count: 10,
    processed_count: 7,
    duplicate_count: 1,
    error_count: 1,
    created_at: '2026-07-01T10:00:00Z',
    started_at: '2026-07-01T10:30:00Z',
  },
  {
    id: 43,
    name: 'Failed Batch',
    source_label: 'Cloudinary',
    source_type: 'cloudinary',
    connector_name: 'Cloudinary Source',
    status: 'failed',
    total_count: 4,
    processed_count: 2,
    duplicate_count: 0,
    error_count: 2,
    created_at: '2026-06-30T10:00:00Z',
  },
];

const reviewBatchPayload = {
  batch: {
    id: 42,
    name: 'Workspace Batch',
    source_label: 'Adobe Experience Manager',
    status: 'review_needed',
    total_count: 2,
    processed_count: 2,
    duplicate_count: 1,
    error_count: 0,
    progress_pct: 100,
  },
  items: [
    {
      id: 100,
      original_filename: 'images/hero.jpg',
      status: 'ready_for_import',
      file_size: 1048576,
      file_hash: 'abcdef1234567890',
      legacy_metadata: { title: 'Hero' },
      clean_properties: { title: 'Hero', tags: ['homepage'] },
    },
    {
      id: 101,
      original_filename: 'images/duplicate.jpg',
      status: 'flagged_duplicate',
      file_size: 2048,
      legacy_metadata: { title: 'Duplicate' },
      clean_properties: {},
    },
  ],
  meta: { total: 2, per_page: 50 },
};

const committedBatchPayload = {
  batch: {
    ...reviewBatchPayload.batch,
    status: 'committed',
  },
  items: reviewBatchPayload.items,
  meta: reviewBatchPayload.meta,
};

const committedReportPayload = {
  report: {
    committed: 9,
    duplicates_blocked: 1,
    errors: 0,
    ai_enriched: 6,
    duplicate_storage_saved_gb: 1.5,
    estimated_cost_savings_usd: 42,
    top_errors: [['bad.jpg', 'invalid metadata']],
  },
};

const ingestionStats = {
  total_batches: 12,
  active_batches: 1,
  failed_batches: 1,
  completed_batches: 10,
  total_assets_committed: 500,
  total_assets_staged: 550,
  total_duplicates_blocked: 20,
  estimated_storage_saved_gb: '12.50',
  estimated_cost_savings_usd: '50.00',
};

const dataHealthOverview = {
  scan: {
    status: 'completed',
    last_scan_at: '2026-07-01T09:00:00Z',
    progress: { processed: 10, total: 10 },
  },
  storage: {
    active_used_tb: 1.2,
    orphaned_wasted_tb: 0.04,
    duplicates_prevented_tb: 0.12,
    estimated_savings_usd_mo: 91.23,
    estimated_savings_gb: 122.4,
    total_assets_committed: 1000,
    total_assets_staged: 1200,
    total_duplicates_blocked: 44,
  },
  duplicates: { pending: 4, resolved: 8, dismissed: 1 },
  connectors: { active: 1, total: 2, idle: 1 },
  batches: { active: 1, completed: 6, failed: 1, total: 8 },
  debt_flags: [
    {
      type: 'missing_metadata',
      title: 'Missing Metadata',
      description: 'Assets require enrichment.',
      impact: 'Medium',
      count: 5,
      can_automate: true,
      actionable: true,
      action_link: '/admin/reports',
      action_label: 'Inspect',
    },
  ],
};

const dataHealthConnectors = [
  {
    id: 1,
    name: 'AEM Source',
    provider_type: 'AEM',
    status: 'active',
    assets_imported: 12,
    batches_count: 3,
    last_sync: '2026-07-01T08:00:00Z',
    health_score: 92,
    tdm_sanitation: true,
    analysis_report: { total_found: 300, missing_tags: 8, estimated_size_gb: 4.2 },
  },
];

const jsonResponse = (data, ok = true, status = ok ? 200 : 500) =>
  Promise.resolve({ ok, status, json: () => Promise.resolve(data) });

const ensureCsrf = () => {
  let meta = document.querySelector('meta[name="csrf-token"]');
  if (!meta) {
    meta = document.createElement('meta');
    meta.setAttribute('name', 'csrf-token');
    document.head.appendChild(meta);
  }
  meta.setAttribute('content', 'token');
};

const installFetchMock = (handler) => {
  global.fetch = jest.fn((url, options = {}) => {
    const response = handler(url, options);
    if (!response) {
      throw new Error(`Unhandled fetch: ${(options.method || 'GET').toUpperCase()} ${url}`);
    }
    return response;
  });
};

describe('Admin Migrations components', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    ensureCsrf();
    window.confirm = jest.fn(() => true);
  });

  afterEach(() => {
    jest.restoreAllMocks();
    jest.useRealTimers();
  });

  it('renders BatchPipelineTimeline phases', () => {
    render(<BatchPipelineTimeline status="review_needed" />);

    expect(screen.getByText('Initializing')).toBeInTheDocument();
    expect(screen.getByText('Extracting Files')).toBeInTheDocument();
    expect(screen.getByText('AI Transforming')).toBeInTheDocument();
    expect(screen.getByText('Awaiting Review')).toBeInTheDocument();
    expect(screen.getByText('Committed')).toBeInTheDocument();
  });

  it('renders ConnectorsTopBar and triggers actions', async () => {
    const onAddClick = jest.fn();
    const onRefresh = jest.fn();

    render(<ConnectorsTopBar onAddClick={onAddClick} onRefresh={onRefresh} />);

    expect(screen.getByText('System Connectors')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /refresh status/i }));
    fireEvent.click(screen.getByRole('button', { name: /add connector/i }));

    expect(onRefresh).toHaveBeenCalledTimes(1);
    expect(onAddClick).toHaveBeenCalledTimes(1);
  });

  it('renders ConnectorDialog with provider fields and actions', async () => {
    const setFormData = jest.fn();
    const onClose = jest.fn();
    const onSave = jest.fn();
    const onTest = jest.fn();

    render(
      <ConnectorDialog
        open
        onClose={onClose}
        formData={{ id: 1, provider_type: 'AEM', name: 'AEM Source', endpoint: 'https://aem.example.com', tdm_sanitation: true }}
        setFormData={setFormData}
        onSave={onSave}
        onTest={onTest}
        isSaving={false}
        isTesting={false}
        testResult={{ type: 'success', message: 'Connection healthy' }}
        isFormValid
      />
    );

    expect(screen.getByText('Configure System Connector')).toBeInTheDocument();
    expect(screen.getByText('Connection healthy')).toBeInTheDocument();
    expect(screen.getByDisplayValue('https://aem.example.com')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /test connection/i }));
    fireEvent.click(screen.getByRole('button', { name: /save configuration/i }));
    fireEvent.click(screen.getByRole('button', { name: /cancel/i }));

    expect(onTest).toHaveBeenCalledTimes(1);
    expect(onSave).toHaveBeenCalledTimes(1);
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('renders ConnectorCard and handles key actions', async () => {
    const onEdit = jest.fn();
    const onToggleStatus = jest.fn();
    const onStartMigration = jest.fn();
    const writeText = jest.fn().mockResolvedValue();
    navigator.clipboard.writeText = writeText;

    render(
      <ConnectorCard
        conn={systemConnector}
        onEdit={onEdit}
        onToggleStatus={onToggleStatus}
        onStartMigration={onStartMigration}
      />
    );

    expect(screen.getByText('AEM Source')).toBeInTheDocument();
    expect(screen.getByText(/health scan:/i)).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /configure/i }));
    fireEvent.click(screen.getByRole('button', { name: /start migration/i }));
    fireEvent.click(screen.getByRole('switch'));
    fireEvent.click(screen.getAllByRole('button')[1]);

    expect(onEdit).toHaveBeenCalledWith(systemConnector);
    expect(onStartMigration).toHaveBeenCalledWith(systemConnector);
    expect(onToggleStatus).toHaveBeenCalledWith(systemConnector);
    expect(writeText).toHaveBeenCalled();
    expect(mockNotify).toHaveBeenCalledWith(expect.stringContaining('copied to clipboard'), 'success');
  });

  it('runs NewMigrationDialog wizard and launches a migration', async () => {
    const onSuccess = jest.fn();
    let postedBody = null;

    installFetchMock((url, options) => {
      if (url === '/api/v1/system_connectors') return jsonResponse([systemConnector, { ...systemConnector, id: 2, status: 'disabled', name: 'Disabled' }]);
      if (url === '/api/v1/folders') return jsonResponse({ folders: folderList });
      if (url === '/api/v1/ingestion_batches' && options.method === 'POST') {
        postedBody = JSON.parse(options.body);
        return jsonResponse({ batch: { id: 77, name: 'July Launch' } });
      }
    });

    render(<NewMigrationDialog open onClose={jest.fn()} onSuccess={onSuccess} />);

    // Step 1 — Select Source
    expect(await screen.findByText('AEM Source')).toBeInTheDocument();
    expect(screen.queryByText('Disabled')).not.toBeInTheDocument();

    fireEvent.click(screen.getByText('AEM Source'));
    fireEvent.click(screen.getByRole('button', { name: /^next$/i }));

    // Step 2 — Select Destination (searchable folder picker)
    expect(await screen.findByText('/Marketing/Campaigns')).toBeInTheDocument();
    fireEvent.change(screen.getByPlaceholderText('ingestion.wizard.destinationSearchPlaceholder'), { target: { value: 'campaigns' } });
    await waitFor(() => expect(screen.queryByText('/Marketing')).not.toBeInTheDocument());
    fireEvent.click(screen.getByText('/Marketing/Campaigns'));
    fireEvent.click(screen.getByRole('button', { name: /^next$/i }));

    // Step 3 — Configure Batch
    expect(screen.getByDisplayValue(/migration/i)).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /^next$/i }));
    expect(screen.getByText('Migration Summary')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /ingestion\.wizard\.launch/i }));

    await waitFor(() => expect(onSuccess).toHaveBeenCalledWith({ id: 77, name: 'July Launch' }));
    expect(mockNotify).toHaveBeenCalledWith('ingestion.wizard.launchSuccess:July Launch', 'success');
    expect(postedBody.ingestion_batch.destination_folder_id).toBe('f2');
  });

  it('renders BatchReviewWorkspace and commits a review batch', async () => {
    const onBack = jest.fn();

    installFetchMock((url, options) => {
      if (url === '/api/v1/ingestion_batches/42?page=1') return jsonResponse(reviewBatchPayload);
      if (url === '/api/v1/ingestion_batches/42/commit' && options.method === 'POST') return jsonResponse({ success: true });
    });

    render(<BatchReviewWorkspace batchId={42} onBack={onBack} />);

    expect(await screen.findByText('Workspace Batch')).toBeInTheDocument();
    expect(screen.getByText('hero.jpg')).toBeInTheDocument();

    fireEvent.click(screen.getByText('duplicate.jpg'));
    expect(await screen.findByText('Deduplication Interception')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /approve & commit batch/i }));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(
      '/api/v1/ingestion_batches/42/commit',
      expect.objectContaining({ method: 'POST' })
    ));
    expect(mockNotify).toHaveBeenCalledWith(expect.stringContaining('Commit pipeline started'), 'success');
  });

  it('renders BatchReviewWorkspace committed report view', async () => {
    installFetchMock((url) => {
      if (url === '/api/v1/ingestion_batches/43?page=1') return jsonResponse(committedBatchPayload);
      if (url === '/api/v1/ingestion_batches/43/report') return jsonResponse(committedReportPayload);
    });

    render(<BatchReviewWorkspace batchId={43} onBack={jest.fn()} />);

    expect(await screen.findByText('Migration Report')).toBeInTheDocument();
    expect(screen.getByText('Duplicates Blocked')).toBeInTheDocument();
    expect(screen.getByText(/bad\.jpg: invalid metadata/i)).toBeInTheDocument();
  });

  it('renders DataHealthDashboard and handles scan, connector, and remediation actions', async () => {
    jest.useFakeTimers();

    installFetchMock((url, options) => {
      if (url === '/api/v1/data_health/overview') return jsonResponse(dataHealthOverview);
      if (url === '/api/v1/data_health/connectors') return jsonResponse(dataHealthConnectors);
      if (url === '/api/v1/duplicate_manager_settings/trigger_scan' && options.method === 'POST') {
        return jsonResponse({ message: 'Scan queued' });
      }
      if (url === '/api/v1/system_connectors/pre_flight_analysis' && options.method === 'POST') {
        return jsonResponse({ success: true });
      }
      if (url === '/api/v1/data_health/remediate' && options.method === 'POST') {
        return jsonResponse({ message: 'Remediation queued' });
      }
    });

    render(<DataHealthDashboard />);

    expect(await screen.findByText('Estimated Monthly Savings:')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /datahealth\.scan\.trigger/i }));
    await waitFor(() => expect(mockNotify).toHaveBeenCalledWith('Scan queued', 'success'));

    fireEvent.click(screen.getByRole('tab', { name: /datahealth\.tabs\.connectors/i }));
    expect(await screen.findByText('Health Score')).toBeInTheDocument();
    const connectorRow = screen.getByText('AEM Source').closest('tr');
    fireEvent.click(within(connectorRow).getAllByRole('button')[0]);
    await waitFor(() => expect(mockNotify).toHaveBeenCalledWith('dataHealth.preFlight.queued', 'success'));
    act(() => { jest.advanceTimersByTime(3000); });

    fireEvent.click(screen.getByRole('tab', { name: /datahealth\.tabs\.debt/i }));
    fireEvent.click(screen.getByRole('button', { name: /auto-remediate/i }));
    await waitFor(() => expect(mockNotify).toHaveBeenCalledWith('Remediation queued', 'success'));
  });

  it('renders IngestionDashboard, opens the wizard, and drills into batch review', async () => {
    installFetchMock((url, options) => {
      if (url === '/api/v1/ingestion_batches/stats') return jsonResponse(ingestionStats);
      if (url.startsWith('/api/v1/ingestion_batches?')) return jsonResponse({ batches: batchList, meta: { total: 2, per_page: 50 } });
      if (url === '/api/v1/system_connectors') return jsonResponse([systemConnector]);
      if (url === '/api/v1/folders') return jsonResponse({ folders: folderList });
      if (url === '/api/v1/ingestion_batches/42?page=1') return jsonResponse(reviewBatchPayload);
      if (url === '/api/v1/ingestion_batches/42/commit' && options.method === 'POST') return jsonResponse({ success: true });
    });

    render(<IngestionDashboard />);

    expect((await screen.findAllByText('Review Batch')).length).toBeGreaterThan(0);
    expect(screen.getByText('ingestion.phaseBanner.title')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /ingestion\.startmigration/i }));
    expect(await screen.findByText('ingestion.wizard.title')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /common\.close/i }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());

    fireEvent.click(screen.getAllByRole('button', { name: /audit batch|ingestion\.batch\.audit/i })[0]);
    expect(await screen.findByText('Workspace Batch')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /back/i }));
    expect((await screen.findAllByText('Review Batch')).length).toBeGreaterThan(0);
  });

  it('renders SystemConnectors and supports lifecycle actions', async () => {
    installFetchMock((url, options) => {
      if (url === '/api/v1/system_connectors') return jsonResponse([systemConnector]);
      if (url === '/api/v1/system_connectors/1' && options.method === 'PUT') return jsonResponse({ success: true });
      if (url === '/api/v1/system_connectors/test_connection' && options.method === 'POST') {
        return jsonResponse({ success: true, message: 'Connection ok' });
      }
      if (url === '/api/v1/system_connectors/1/start_migration' && options.method === 'POST') {
        return jsonResponse({ batch: { name: 'Connector Migration' } });
      }
    });

    render(<SystemConnectors />);

    expect(await screen.findByText('AEM Source')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('switch'));
    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith(
      '/api/v1/system_connectors/1',
      expect.objectContaining({ method: 'PUT' })
    ));

    fireEvent.click(screen.getByRole('button', { name: /start migration/i }));
    await waitFor(() => expect(mockNotify).toHaveBeenCalledWith(
      'Migration started: Connector Migration. Track progress in the Pipeline tab.',
      'success'
    ));

    fireEvent.click(screen.getByRole('button', { name: /configure/i }));
    expect(await screen.findByDisplayValue('https://aem.example.com')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /test connection/i }));
    expect(await screen.findByText('Connection ok')).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /save configuration/i }));
    await waitFor(() => expect(mockNotify).toHaveBeenCalledWith('Connector updated.', 'success'));
  });
});
