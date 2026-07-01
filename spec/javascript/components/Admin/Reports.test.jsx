import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { BarChart as BarChartIcon } from '@mui/icons-material';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('recharts', () => ({
  ResponsiveContainer: ({ children }) => children,
  BarChart: ({ children }) => <div data-testid="bar-chart">{children}</div>,
  Bar: () => null,
  XAxis: () => null,
  YAxis: () => null,
  CartesianGrid: () => null,
  Tooltip: () => null,
  Legend: () => null,
  LineChart: ({ children }) => <div data-testid="line-chart">{children}</div>,
  Line: () => null,
  PieChart: ({ children }) => <div data-testid="pie-chart">{children}</div>,
  Pie: () => null,
  Cell: () => null,
  FunnelChart: ({ children }) => <div data-testid="funnel-chart">{children}</div>,
  Funnel: ({ children }) => <div>{children}</div>,
  LabelList: () => null,
  AreaChart: ({ children }) => <div data-testid="area-chart">{children}</div>,
  Area: () => null,
}));

import StatCard from '../../../../app/javascript/components/Admin/Reports/StatCard';
import AnalyticsDashboard from '../../../../app/javascript/components/Admin/Reports/AnalyticsDashboard';
import DownloadCenter from '../../../../app/javascript/components/Admin/Reports/DownloadCenter';
import ReportBuilderDrawer from '../../../../app/javascript/components/Admin/Reports/ReportBuilderDrawer';
import ReportTypesManager from '../../../../app/javascript/components/Admin/Reports/ReportTypesManager';
import ReportsHub from '../../../../app/javascript/components/Admin/Reports';
import AiCoverageChart from '../../../../app/javascript/components/Admin/Reports/charts/AiCoverageChart';
import AssetTrendChart from '../../../../app/javascript/components/Admin/Reports/charts/AssetTrendChart';
import ContentTypeDonut from '../../../../app/javascript/components/Admin/Reports/charts/ContentTypeDonut';
import StatusBreakdownChart from '../../../../app/javascript/components/Admin/Reports/charts/StatusBreakdownChart';
import TopFoldersChart from '../../../../app/javascript/components/Admin/Reports/charts/TopFoldersChart';
import WorkflowFunnelChart from '../../../../app/javascript/components/Admin/Reports/charts/WorkflowFunnelChart';

describe('Admin Reports components', () => {
  beforeEach(() => {
    document.head.innerHTML = '<meta name="csrf-token" content="token" />';
    global.fetch = jest.fn((url) => {
      if (url.startsWith('/admin/reports/analytics')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({
          stats: { total_assets: 100, new_in_range: 5, range_label: 'Last 30 Days' },
          time_series: { combined: [{ date: '2026-07-01', assets: 5, workflows: 2 }] },
          breakdowns: {
            by_content_type: [{ type: 'Image', count: 70 }],
            by_status: [{ status: 'Ready', count: 70 }],
            workflow_funnel: [{ stage: 'Draft', count: 10 }],
            top_folders: [{ name: 'Marketing', count: 12 }],
            by_user: [{ user: 'Alice', count: 4 }],
          },
          ai_insights: {
            coverage: { pct: 75, with_embedding: 75, without_embedding: 25 },
            anomalies: ['Spike detected'],
          },
        }) });
      }
      if (url.startsWith('/admin/report_snapshots.json')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ snapshots: [{ id: 1, report_name: 'Asset Audit', format: 'PDF', status: 'completed', created_at: 'Today', download_url: '/downloads/audit.pdf' }] }) });
      }
      if (url.startsWith('/admin/reports.json?active=true')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ reports: [{ id: 1, name: 'Asset Audit', report_type: 'asset_audit', description: 'Audit' }] }) });
      }
      if (url.startsWith('/admin/reports.json?')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({
          reports: [{ id: 1, name: 'Asset Audit', report_type: 'asset_audit', description: 'Audit', active: true, built_in: false, query_config: {} }],
          meta: { total: 1, total_pages: 1, page: 1 },
        }) });
      }
      if (url === '/admin/reports/asset_property_hints.json') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ hints: { system: ['status'], image_analysis: ['outdoor'], custom: ['campaign'] } }) });
      }
      if (url === '/api/v1/folders') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ folders: [{ id: 1, name: 'Marketing' }] }) });
      }
      if (url.includes('/generate.json')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
      }
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
    });
  });

  it('StatCard renders with value and label', () => {
    render(<StatCard label="Assets" value="100" icon={<BarChartIcon />} />);
    expect(screen.getByText('Assets')).toBeInTheDocument();
    expect(screen.getByText('100')).toBeInTheDocument();
  });

  it('AnalyticsDashboard renders without crashing', async () => {
    const onCreateExport = jest.fn();
    render(<AnalyticsDashboard onCreateExport={onCreateExport} />);
    expect(await screen.findByText('System Analytics')).toBeInTheDocument();
    expect(screen.getByText('Spike detected')).toBeInTheDocument();
    fireEvent.click(screen.getByText('+ Create Export'));
    expect(onCreateExport).toHaveBeenCalled();
  });

  it('DownloadCenter renders a file list', async () => {
    render(<DownloadCenter refreshTrigger={0} />);
    expect(await screen.findByText('Asset Audit')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Download' })).toHaveAttribute('href', '/downloads/audit.pdf');
  });

  it('ReportBuilderDrawer renders its form', async () => {
    render(<ReportBuilderDrawer open onClose={jest.fn()} onExportStarted={jest.fn()} preselectedReportId={1} />);
    expect(screen.getByText('reports.builder.title')).toBeInTheDocument();
    expect(await screen.findByText('reports.builder.step_format')).toBeInTheDocument();
  });

  it('ReportTypesManager renders the type list', async () => {
    render(<ReportTypesManager onOpenBuilder={jest.fn()} />);
    expect(await screen.findByText('Asset Audit')).toBeInTheDocument();
    expect(screen.getByText('asset_audit')).toBeInTheDocument();
  });

  it('Reports hub renders tabs', async () => {
    render(<ReportsHub />);
    expect(screen.getByText('reports.title')).toBeInTheDocument();
    expect(await screen.findByText('System Analytics')).toBeInTheDocument();
    fireEvent.click(screen.getByText('reports.tabs.downloads'));
    expect(await screen.findByText('Download Center')).toBeInTheDocument();
  });

  it('all charts render', () => {
    render(
      <>
        <AiCoverageChart data={{ coverage: { pct: 75, with_embedding: 75, without_embedding: 25 } }} />
        <AssetTrendChart data={[{ date: '2026-07-01', assets: 5, workflows: 2 }]} />
        <ContentTypeDonut data={[{ type: 'Image', count: 10 }]} />
        <StatusBreakdownChart data={[{ status: 'Ready', count: 10 }]} />
        <TopFoldersChart data={[{ name: 'Marketing', count: 12 }]} />
        <WorkflowFunnelChart data={[{ stage: 'Draft', count: 10 }]} />
      </>
    );

    expect(screen.getByText('75.0%')).toBeInTheDocument();
    expect(screen.getByTestId('area-chart')).toBeInTheDocument();
    expect(screen.getByTestId('pie-chart')).toBeInTheDocument();
    expect(screen.getByTestId('bar-chart')).toBeInTheDocument();
    expect(screen.getByText('Marketing')).toBeInTheDocument();
    expect(screen.getByTestId('funnel-chart')).toBeInTheDocument();
  });
});
