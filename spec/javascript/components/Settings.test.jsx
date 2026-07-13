import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import Settings from '../../../app/javascript/components/Settings';

jest.mock('../../../app/javascript/components/Admin/SystemStatus/index.jsx', () => (props) => (
  <div>SystemStatus activeProvider={props.activeProvider} allConfigs={props.allConfigs}</div>
));
jest.mock('../../../app/javascript/components/Sidebar.jsx', () => () => <div>Sidebar</div>);
jest.mock('../../../app/javascript/utils/globalutils.js', () => ({ navigateTo: jest.fn() }));

describe('Settings', () => {
  const props = {
    userIsAdmin: 'true',
    systemApps: JSON.stringify([{ id: 1, name: 'Marketing API', uid: 'abcdef123456' }]),
    allConfigs: JSON.stringify({ local: {}, aws: { access_key: 'key', secret_key: 'secret', region: 'us-east-1', bucket: 'bucket' } }),
    activeProvider: 'local',
  };

  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === '[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
    window.confirm = jest.fn(() => true);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  it('renders System Administration with service accounts on the General view', () => {
    render(<Settings {...props} />);

    expect(screen.getByText('System Administration')).toBeInTheDocument();
    expect(screen.getByText('System Service Accounts')).toBeInTheDocument();
    expect(screen.getByText('Marketing API')).toBeInTheDocument();
  });

  it('shows a redirect notice pointing admins to System Settings for storage config', () => {
    render(<Settings {...props} />);

    expect(screen.getByText(/Storage Backend Configuration has moved to/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Go to System Settings' })).toBeInTheDocument();
  });

  it('navigates to /settings/system when the redirect button is clicked', () => {
    const { navigateTo } = require('../../../app/javascript/utils/globalutils.js');
    render(<Settings {...props} />);

    fireEvent.click(screen.getByRole('button', { name: 'Go to System Settings' }));
    expect(navigateTo).toHaveBeenCalledWith('/settings/system');
  });

  it('revokes a system service account from the General view', () => {
    render(<Settings {...props} />);

    fireEvent.click(screen.getByRole('button', { name: 'Revoke' }));
    expect(window.confirm).toHaveBeenCalled();
  });

  it('renders nothing for non-admins on the General view', () => {
    render(<Settings {...props} userIsAdmin="false" />);
    expect(screen.queryByText('System Administration')).not.toBeInTheDocument();
    expect(screen.queryByText(/Storage Backend Configuration has moved to/)).not.toBeInTheDocument();
  });

  it('renders SystemStatus with storage props when currentSubView is System', () => {
    const { container } = render(<Settings {...props} currentSubView="System" />);

    expect(container.textContent).toContain('SystemStatus');
    expect(container.textContent).toContain(props.activeProvider);
    expect(container.textContent).toContain(props.allConfigs);
  });
});
