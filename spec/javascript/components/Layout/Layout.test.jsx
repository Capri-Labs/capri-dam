import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import Header from '../../../../app/javascript/components/Layout/Header';
import Footer from '../../../../app/javascript/components/Layout/Footer';
import ImpersonateUserDialog from '../../../../app/javascript/components/Layout/ImpersonateUserDialog';
import ImpersonationBanner from '../../../../app/javascript/components/Layout/ImpersonationBanner';
import { apiFetch } from '../../../../app/javascript/utils/adminUtils.js';

jest.mock('../../../../app/javascript/components/NotificationBell.jsx', () => () => <div>NotificationBell</div>);
jest.mock('../../../../app/javascript/components/Search/GlobalSearchBar.jsx', () => () => <div>GlobalSearchBar</div>);
jest.mock('../../../../app/javascript/components/Admin/UserSearch.jsx', () => (props) => (
  <button type="button" onClick={() => props.onSelect({ id: 9, display_name: 'Taylor Admin', email: 'taylor@example.com', admin: true })}>
    Select user
  </button>
));
jest.mock('../../../../app/javascript/utils/adminUtils.js', () => ({ apiFetch: jest.fn() }));

const originalLocation = window.location;

describe('Layout components', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    delete window.location;
    window.location = { href: '/' };
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === '[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
  });

  afterEach(() => {
    jest.restoreAllMocks();
    window.location = originalLocation;
  });

  it('renders Header with signed-in navigation and user menu', async () => {
    render(
      <Header
        isSignedIn
        userName="Alex Johnson"
        isAdmin="true"
        impersonating="false"
      />,
    );

    expect(screen.getByText('GlobalSearchBar')).toBeInTheDocument();
    expect(screen.getByText('NotificationBell')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Create New…' })).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Account settings' }));

    expect(await screen.findByText('My Profile')).toBeInTheDocument();
    expect(screen.getByText('System Settings')).toBeInTheDocument();
    expect(screen.getByText('Impersonate User')).toBeInTheDocument();
  });

  it('opens the create menu in Header', async () => {
    render(<Header isSignedIn userName="Alex Johnson" impersonating="false" />);

    fireEvent.click(screen.getByRole('button', { name: 'Create New…' }));

    expect(await screen.findByText('Upload Asset')).toBeInTheDocument();
    expect(screen.getByText('Start Workflow')).toBeInTheDocument();
  });

  it('renders Footer content', () => {
    render(<Footer />);
    expect(screen.getByText('Intelligent Asset Engine')).toBeInTheDocument();
    expect(screen.getByText('API Documentation')).toBeInTheDocument();
    expect(screen.getByText(/Capri DAM/)).toBeInTheDocument();
  });

  it('renders ImpersonateUserDialog and starts impersonation after selecting a user', async () => {
    apiFetch.mockResolvedValue({ success: true });

    render(<ImpersonateUserDialog open onClose={jest.fn()} />);

    expect(screen.getByText('Impersonate User')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Start Impersonation' })).toBeDisabled();

    fireEvent.click(screen.getByRole('button', { name: 'Select user' }));
    fireEvent.click(screen.getByRole('button', { name: 'Start Impersonation' }));

    await waitFor(() => expect(apiFetch).toHaveBeenCalledWith('/impersonation/start/9', { method: 'POST' }));
  });

  it('closes ImpersonateUserDialog with the cancel button', () => {
    const onClose = jest.fn();
    render(<ImpersonateUserDialog open onClose={onClose} />);
    fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(onClose).toHaveBeenCalled();
  });

  it('renders ImpersonationBanner text and triggers ending state', async () => {
    apiFetch.mockReturnValue(new Promise(() => {}));

    render(
      <ImpersonationBanner
        impersonatedUser={{ display_name: 'Chris User', email: 'chris@example.com' }}
        trueUserName="Admin One"
      />,
    );

    expect(screen.getByText(/IMPERSONATION ACTIVE/i)).toBeInTheDocument();
    expect(screen.getByText(/Chris User/)).toBeInTheDocument();
    expect(screen.getByText(/Admin One/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'End Impersonation' }));

    await waitFor(() => expect(apiFetch).toHaveBeenCalledWith('/impersonation/stop', { method: 'DELETE' }));
    expect(screen.getByRole('button', { name: 'Ending…' })).toBeDisabled();
  });
});
