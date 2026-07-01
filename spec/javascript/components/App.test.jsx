import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import App from '../../../app/javascript/components/App';

jest.mock('../../../app/javascript/components/Folders/AssetExplorer', () => (props) => (
  <div>Asset Explorer target:{props.initialTargetAssetId || 'none'}</div>
));
jest.mock('../../../app/javascript/components/WorkflowDashboard', () => (props) => (
  <div>
    <div>Workflow Dashboard</div>
    <button type="button" onClick={() => props.onNavigateToAsset('asset-77')}>Go to asset</button>
  </div>
));

describe('App', () => {
  it('renders without crashing and shows the explorer by default', () => {
    render(<App />);
    expect(screen.getByText('Digital Asset Manager')).toBeInTheDocument();
    expect(screen.getByText('Asset Explorer target:none')).toBeInTheDocument();
  });

  it('switches between explorer and workflow views', () => {
    render(<App />);

    fireEvent.click(screen.getByText('Workflows'));
    expect(screen.getByText('Workflow Operations')).toBeInTheDocument();
    expect(screen.getByText('Workflow Dashboard')).toBeInTheDocument();

    fireEvent.click(screen.getByText('Asset Explorer'));
    expect(screen.getByText('Digital Asset Manager')).toBeInTheDocument();
  });

  it('navigates back to the explorer when workflow asks to open an asset', () => {
    render(<App />);

    fireEvent.click(screen.getByText('Workflows'));
    fireEvent.click(screen.getByRole('button', { name: 'Go to asset' }));

    expect(screen.getByText('Asset Explorer target:asset-77')).toBeInTheDocument();
  });
});
