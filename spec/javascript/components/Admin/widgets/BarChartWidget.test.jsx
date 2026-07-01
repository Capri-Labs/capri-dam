import React from 'react';
import { render, screen } from '@testing-library/react';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key }),
  Trans: ({ i18nKey }) => i18nKey,
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
}));

import BarChartWidget from '../../../../../app/javascript/components/Admin/widgets/BarChartWidget';

describe('BarChartWidget', () => {
  it('renders the chart', () => {
    render(
      <BarChartWidget
        title="Asset Counts"
        data={[{ month: 'Jan', total: 4 }]}
        dataKeyX="month"
        dataBars={[{ key: 'total', name: 'Total', color: '#5e35b1' }]}
      />
    );

    expect(screen.getByText('Asset Counts')).toBeInTheDocument();
    expect(screen.getByTestId('bar-chart')).toBeInTheDocument();
  });
});
