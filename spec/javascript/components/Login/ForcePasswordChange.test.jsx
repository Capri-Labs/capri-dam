'use strict';

import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

import ForcePasswordChange from '../../../../app/javascript/components/Login/ForcePasswordChange';

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key) => key })
}));

describe('<ForcePasswordChange />', () => {
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

  function renderComponent() {
    return render(<ForcePasswordChange email="user@example.com" tempPassword="TempPassword1" />);
  }

  it('renders the form with the temporary password disabled', () => {
    renderComponent();

    expect(screen.getByText('login.forceTitle')).toBeInTheDocument();
    expect(screen.getByLabelText('login.tempPassword')).toBeDisabled();
    expect(screen.getByLabelText('login.newPassword')).toBeInTheDocument();
    expect(screen.getByLabelText('login.confirmPassword')).toBeInTheDocument();
  });

  it('validates mismatched passwords before submitting', async () => {
    renderComponent();

    fireEvent.change(screen.getByLabelText('login.newPassword'), { target: { value: 'StrongPass1' } });
    fireEvent.change(screen.getByLabelText('login.confirmPassword'), { target: { value: 'StrongPass2' } });
    fireEvent.click(screen.getByRole('button', { name: 'login.updatePassword' }));

    expect((await screen.findAllByText('login.passwordMismatch')).length).toBeGreaterThan(0);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it.each([
    ['too short', 'Abc1234'],
    ['missing uppercase', 'lowercase1'],
    ['missing number', 'NoNumbers']
  ])('rejects weak passwords that are %s', async (_label, password) => {
    renderComponent();

    fireEvent.change(screen.getByLabelText('login.newPassword'), { target: { value: password } });
    fireEvent.change(screen.getByLabelText('login.confirmPassword'), { target: { value: password } });
    fireEvent.click(screen.getByRole('button', { name: 'login.updatePassword' }));

    expect((await screen.findAllByText('login.passwordTooWeak')).length).toBeGreaterThan(0);
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('redirects to root after a successful password update', async () => {
    global.fetch.mockResolvedValue({
      ok: true,
      json: () => Promise.resolve({ success: true, user: { email: 'user@example.com' } })
    });

    renderComponent();

    fireEvent.change(screen.getByLabelText('login.newPassword'), { target: { value: 'StrongPass1' } });
    fireEvent.change(screen.getByLabelText('login.confirmPassword'), { target: { value: 'StrongPass1' } });
    fireEvent.click(screen.getByRole('button', { name: 'login.updatePassword' }));

    await waitFor(() => expect(locationState.href).toBe('/'));

    const [, request] = global.fetch.mock.calls[0];
    expect(global.fetch).toHaveBeenCalledWith('/users/force_password_update.json', expect.any(Object));
    expect(request.headers['X-CSRF-Token']).toBe('meta-csrf-token');
    expect(JSON.parse(request.body)).toEqual({
      email: 'user@example.com',
      current_password: 'TempPassword1',
      new_password: 'StrongPass1',
      new_password_confirmation: 'StrongPass1'
    });
  });

  it('shows the loading state while submitting', async () => {
    let resolveRequest;
    global.fetch.mockImplementation(() => new Promise((resolve) => {
      resolveRequest = resolve;
    }));

    renderComponent();

    fireEvent.change(screen.getByLabelText('login.newPassword'), { target: { value: 'StrongPass1' } });
    fireEvent.change(screen.getByLabelText('login.confirmPassword'), { target: { value: 'StrongPass1' } });
    fireEvent.click(screen.getByRole('button', { name: 'login.updatePassword' }));

    await waitFor(() => {
      expect(screen.getByRole('button', { name: 'login.updatePassword' })).toBeDisabled();
      expect(screen.getByRole('button', { name: 'login.updatePassword' })).toHaveTextContent('login.updating');
    });
    expect(screen.getByLabelText('login.newPassword')).toBeDisabled();
    expect(screen.getByLabelText('login.confirmPassword')).toBeDisabled();

    resolveRequest({
      ok: true,
      json: () => Promise.resolve({ success: true, user: { email: 'user@example.com' } })
    });

    await waitFor(() => {
      expect(locationState.href).toBe('/');
    });
  });
});
