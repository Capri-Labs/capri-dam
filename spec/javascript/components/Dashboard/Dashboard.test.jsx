import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import DashboardManager from '../../../../app/javascript/components/Dashboard/DashboardManager';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
}));
jest.mock('../../../../app/javascript/utils/globalutils.js', () => ({ navigateTo: jest.fn() }));
jest.mock('recharts', () => {
  const React = require('react');
  const Mock = ({ children }) => <div>{children}</div>;
  return {
    ResponsiveContainer: Mock,
    AreaChart: Mock,
    Area: Mock,
    XAxis: Mock,
    YAxis: Mock,
    CartesianGrid: Mock,
    Tooltip: Mock,
    PieChart: Mock,
    Pie: Mock,
    Cell: Mock,
    Legend: Mock,
  };
});

const overview = {
  kpis: { total_assets: 10, total_folders: 2, total_users: 3, assets_added_7d: 4 },
  asset_growth: [{ month: 'Jan', count: 4 }],
  assets_by_type: [{ type: 'image', count: 8 }],
  storage: { total_human: '4 GB' },
  recent_assets: [{ id: 1, uuid: 'uuid-1', title: 'Spring hero', file_size: 2048, created_at: '2024-01-01T00:00:00Z', status: 'published', content_type: 'image/jpeg' }],
  workflow_summary: { total: 3, approved: 2, rejected: 1, canceled: 0 },
  ai_insights: [{ key: 'failed_analysis', type: 'warning', count: 1 }],
};

describe('DashboardManager', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders dashboard sections after loading API data', async () => {
    global.fetch = jest.fn().mockResolvedValue({ ok: true, json: async () => overview });

    render(<DashboardManager />);

    expect(await screen.findByText('dashboard.title')).toBeInTheDocument();
    expect(screen.getByText('dashboard.quick_actions.title')).toBeInTheDocument();
    expect(screen.getByText('dashboard.recent_assets.title')).toBeInTheDocument();
    expect(await screen.findByText('Spring hero')).toBeInTheDocument();
  });

  it('shows an error state and retries successfully', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValueOnce({ ok: false, status: 500, json: async () => ({}) })
      .mockResolvedValueOnce({ ok: true, json: async () => overview });

    render(<DashboardManager />);

    expect(await screen.findByText('HTTP 500')).toBeInTheDocument();
    fireEvent.click(screen.getAllByRole('button', { name: 'dashboard.refresh' })[1]);

    await waitFor(() => expect(screen.getByText('Spring hero')).toBeInTheDocument());
  });
});
