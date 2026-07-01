'use strict';

import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

import Login from '../../../../app/javascript/components/Login/Login';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key })
}));

describe('<Login />', () => {
  let getElementByIdSpy;
  let querySelectorSpy;
  let locationSpy;
  let locationState;

  beforeEach(() => {
    const originalGetElementById = document.getElementById.bind(document);
    const originalQuerySelector = document.querySelector.bind(document);

    global.fetch = jest.fn();
    locationState = { href: '/users/sign_in' };

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

    locationSpy = jest.spyOn(window, 'location', 'get').mockReturnValue(locationState);
  });

  afterEach(() => {
    getElementByIdSpy.mockRestore();
    querySelectorSpy.mockRestore();
    locationSpy.mockRestore();
    jest.restoreAllMocks();
  });

  it('renders the login form, SSO button, and forgot password link', () => {
    render(<Login />);

    expect(screen.getByLabelText('login.emailLabel')).toBeInTheDocument();
    expect(screen.getByLabelText('login.passwordLabel')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'login.ssoButton' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'login.forgotPassword' })).toBeInTheDocument();
  });

  it('redirects to root after a successful login', async () => {
    global.fetch.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ success: true, user: { email: 'user@example.com' } })
    });

    render(<Login />);

    fireEvent.change(screen.getByLabelText('login.emailLabel'), { target: { value: 'user@example.com' } });
    fireEvent.change(screen.getByLabelText('login.passwordLabel'), { target: { value: 'Password123!' } });
    fireEvent.click(screen.getByRole('button', { name: 'login.signIn' }));

    await waitFor(() => expect(locationState.href).toBe('/'));

    const [, request] = global.fetch.mock.calls[0];
    expect(global.fetch).toHaveBeenCalledWith('/users/sign_in.json', expect.any(Object));
    expect(request.headers['X-CSRF-Token']).toBe('root-csrf-token');
    expect(JSON.parse(request.body)).toEqual({
      user: {
        email: 'user@example.com',
        password: 'Password123!'
      }
    });
  });

  it('switches to the force password change view when required', async () => {
    global.fetch.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ success: true, force_password_change: true, email: 'user@example.com' })
    });

    render(<Login />);

    fireEvent.change(screen.getByLabelText('login.emailLabel'), { target: { value: 'user@example.com' } });
    fireEvent.change(screen.getByLabelText('login.passwordLabel'), { target: { value: 'TempPassword1' } });
    fireEvent.click(screen.getByRole('button', { name: 'login.signIn' }));

    expect(await screen.findByText('login.forceTitle')).toBeInTheDocument();
    expect(screen.getByLabelText('login.tempPassword')).toBeDisabled();
    expect(screen.getByLabelText('login.newPassword')).toBeInTheDocument();
  });

  it('shows an error message when login fails', async () => {
    global.fetch.mockResolvedValue({
      ok: false,
      json: () => Promise.resolve({ success: false, error: 'Invalid email or password' })
    });

    render(<Login />);

    fireEvent.change(screen.getByLabelText('login.emailLabel'), { target: { value: 'user@example.com' } });
    fireEvent.change(screen.getByLabelText('login.passwordLabel'), { target: { value: 'wrong-password' } });
    fireEvent.click(screen.getByRole('button', { name: 'login.signIn' }));

    expect(await screen.findByText('login.invalidCredentials')).toBeInTheDocument();
  });

  it('shows the loading state while submitting', async () => {
    let resolveRequest;
    global.fetch.mockImplementation(() => new Promise((resolve) => {
      resolveRequest = resolve;
    }));

    render(<Login />);

    fireEvent.change(screen.getByLabelText('login.emailLabel'), { target: { value: 'user@example.com' } });
    fireEvent.change(screen.getByLabelText('login.passwordLabel'), { target: { value: 'Password123!' } });
    fireEvent.click(screen.getByRole('button', { name: 'login.signIn' }));

    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'login.signIn' })).toBeDisabled();
      expect(screen.getByRole('button', { name: 'login.signIn' })).toHaveTextContent('login.signingIn');
    });
    expect(screen.getByLabelText('login.emailLabel')).toBeDisabled();
    expect(screen.getByLabelText('login.passwordLabel')).toBeDisabled();

    resolveRequest({
      ok: false,
      json: () => Promise.resolve({ success: false, error: 'Invalid email or password' })
    });

    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'login.signIn' })).toBeEnabled();
    });
  });
});
