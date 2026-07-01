import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

const mockApiFetch = jest.fn();
const mockNotify = jest.fn();
const mockChangeLanguage = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key, opts) => opts?.defaultValue || key,
    i18n: { language: 'en' },
  }),
}));

jest.mock('../../../../app/javascript/utils/adminUtils', () => ({
  apiFetch: (...args) => mockApiFetch(...args),
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('../../../../app/javascript/i18n/index', () => ({
  changeLanguage: (...args) => mockChangeLanguage(...args),
}));

import ProfilePage from '../../../../app/javascript/components/Profile/ProfilePage';

const baseProps = {
  userFirstName: 'Ashok',
  userLastName: 'Pelluru',
  userEmail: 'ashok@example.com',
  userDepartment: 'Engineering',
  userAvatarUrl: '/avatar.png',
  preferences: JSON.stringify({ language: 'en', theme: 'system' }),
  auditLogs: JSON.stringify([]),
  ssoManaged: false,
  ssoProvider: 'Keycloak',
  isAdmin: 'true',
};

describe('ProfilePage', () => {
  beforeEach(() => {
    mockApiFetch.mockReset();
    mockNotify.mockReset();
    mockChangeLanguage.mockReset();
    mockApiFetch.mockResolvedValue({ success: true, tokens: [], activity: [] });
  });

  it('renders the profile form with user information', () => {
    render(<ProfilePage {...baseProps} />);

    expect(screen.getByText('Ashok Pelluru')).toBeInTheDocument();
    expect(screen.getByText('ashok@example.com')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Ashok')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Pelluru')).toBeInTheDocument();
    expect(screen.getByDisplayValue('Engineering')).toBeInTheDocument();
    expect(screen.getByText('Admin')).toBeInTheDocument();
  });

  it('switches sections and shows read-only SSO fields when managed', async () => {
    render(<ProfilePage {...baseProps} ssoManaged="true" />);

    expect(screen.getByText(/Your account is synced via/)).toBeInTheDocument();
    expect(screen.getByLabelText('First Name')).toBeDisabled();
    expect(screen.getByLabelText('Email Address')).toBeDisabled();

    await userEvent.click(screen.getByRole('tab', { name: 'profile.tabs.localization' }));
    expect(screen.getByRole('button', { name: 'profile.localization.savePreferences' })).toBeInTheDocument();

    await userEvent.click(screen.getByRole('tab', { name: 'profile.tabs.security' }));
    expect(screen.getByText(/Your password is managed by/)).toBeInTheDocument();
  });

  it('saves profile changes through the profile API', async () => {
    mockApiFetch.mockResolvedValueOnce({ success: true });
    render(<ProfilePage {...baseProps} />);

    await userEvent.clear(screen.getByLabelText('Department'));
    await userEvent.type(screen.getByLabelText('Department'), 'Platform');
    await userEvent.click(screen.getByRole('button', { name: 'Save Changes' }));

    await waitFor(() => {
      expect(mockApiFetch).toHaveBeenCalledWith('/profile', expect.objectContaining({
        method: 'PATCH',
      }));
    });
    expect(JSON.parse(mockApiFetch.mock.calls[0][1].body)).toEqual({
      user: expect.objectContaining({
        department: 'Platform',
        email: 'ashok@example.com',
      }),
    });
    expect(mockNotify).toHaveBeenCalledWith('Profile updated.', 'success');
  });
});
