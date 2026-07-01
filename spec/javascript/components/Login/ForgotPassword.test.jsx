'use strict';

import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

import ForgotPassword from '../../../../app/javascript/components/Login/ForgotPassword';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key })
}));

describe('<ForgotPassword />', () => {
  let getElementByIdSpy;
  let querySelectorSpy;

  beforeEach(() => {
    const originalGetElementById = document.getElementById.bind(document);
    const originalQuerySelector = document.querySelector.bind(document);

    global.fetch = jest.fn();

    getElementByIdSpy = jest.spyOn(document, 'getElementById').mockImplementation((id) => {
      if (id === 'root') {
        return {
          dataset: {
            csrfToken: 'root-csrf-token',
            ssoPath: '/users/auth/keycloak_openid'
          }
        };
      }

      return originalGetElementById(id);
    });

    querySelectorSpy = jest.spyOn(document, 'querySelector').mockImplementation((selector) => {
      if (selector === '[name="csrf-token"]') {
        return { content: 'meta-csrf-token' };
      }

      return originalQuerySelector(selector);
    });
  });

  afterEach(() => {
    getElementByIdSpy.mockRestore();
    querySelectorSpy.mockRestore();
    jest.restoreAllMocks();
  });

  it('renders with the initial email pre-filled', async () => {
    render(<ForgotPassword open onClose={jest.fn()} initialEmail="user@example.com" />);

    expect(await screen.findByText('login.forgotTitle')).toBeInTheDocument();
    expect(screen.getByLabelText('login.emailLabel')).toHaveValue('user@example.com');
  });

  it('shows a success message after requesting a password reset', async () => {
    global.fetch.mockResolvedValue({ ok: true });

    render(<ForgotPassword open onClose={jest.fn()} initialEmail="user@example.com" />);

    fireEvent.click(screen.getByRole('button', { name: 'login.sendResetLink' }));

    expect(await screen.findByText('login.forgotSuccess')).toBeInTheDocument();
    expect(global.fetch).toHaveBeenCalledWith('/users/password.json', expect.any(Object));
  });

  it('shows an error message when the request fails', async () => {
    global.fetch.mockResolvedValue({ ok: false });

    render(<ForgotPassword open onClose={jest.fn()} initialEmail="user@example.com" />);

    fireEvent.click(screen.getByRole('button', { name: 'login.sendResetLink' }));

    expect(await screen.findByText('login.forgotFailed')).toBeInTheDocument();
  });

  it('shows the loading state while submitting', async () => {
    let resolveRequest;
    global.fetch.mockImplementation(() => new Promise((resolve) => {
      resolveRequest = resolve;
    }));

    render(<ForgotPassword open onClose={jest.fn()} initialEmail="user@example.com" />);

    fireEvent.click(screen.getByRole('button', { name: 'login.sendResetLink' }));

    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'login.sendResetLink' })).toBeDisabled();
      expect(screen.getByRole('button', { name: 'login.sendResetLink' })).toHaveTextContent('common.loading');
    });
    expect(screen.getByLabelText('login.emailLabel')).toBeDisabled();

    resolveRequest({ ok: true });

    await waitFor(() => {
      expect(screen.queryByText('common.loading')).not.toBeInTheDocument();
    });
  });
});
