import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';

import CustomNodeManager from '../../../../../app/javascript/components/Admin/CustomNodes/CustomNodeManager';

const mockNotify = jest.fn();

jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key, opts) => (opts && opts.count !== undefined ? `${key}:${opts.count}` : key) }),
}));

jest.mock('../../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

const definition = {
  id: 'abc-123',
  key: 'acme_watermark',
  node_type: 'plugin:acme_watermark',
  name: 'Acme Watermark',
  description: 'Applies a tenant watermark.',
  category: 'custom',
  color: '#6366f1',
  status: 'enabled',
  config_schema: [{ key: 'quality', type: 'string', label: 'Quality' }],
  runtime: { endpoint_url: 'https://plugins.example.com/wm', outputs: ['approved', 'rejected'] },
  failure_count: 0,
  circuit_open: false,
};

describe('CustomNodeManager', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    jest.spyOn(document, 'querySelector').mockImplementation((selector) => (
      selector === '[name="csrf-token"]' ? { content: 'csrf-token' } : null
    ));
  });

  it('lists registered custom node definitions', async () => {
    global.fetch = jest.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve({ items: [definition] }) })
    );

    render(<CustomNodeManager />);

    expect(await screen.findByText('Acme Watermark')).toBeInTheDocument();
    expect(screen.getByText('plugin:acme_watermark')).toBeInTheDocument();
    expect(screen.getByText('https://plugins.example.com/wm')).toBeInTheDocument();
  });

  it('shows an empty state when there are no definitions', async () => {
    global.fetch = jest.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve({ items: [] }) })
    );

    render(<CustomNodeManager />);

    expect(await screen.findByText('customNodes.empty')).toBeInTheDocument();
  });

  it('opens the register dialog when Register Node is clicked', async () => {
    global.fetch = jest.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve({ items: [] }) })
    );

    render(<CustomNodeManager />);
    await screen.findByText('customNodes.empty');

    fireEvent.click(screen.getByText('customNodes.register'));

    expect(await screen.findByText('customNodes.registerTitle')).toBeInTheDocument();
    expect(screen.getByLabelText('customNodes.fieldKey')).toBeInTheDocument();
    expect(screen.getByLabelText('customNodes.fieldEndpoint')).toBeInTheDocument();
  });

  it('POSTs a new definition built from the form', async () => {
    const postSpy = jest.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve({ custom_node_definition: definition }) })
    );
    global.fetch = jest.fn((url, opts = {}) => {
      if ((opts.method || 'GET') === 'POST') return postSpy(url, opts);
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ items: [] }) });
    });

    render(<CustomNodeManager />);
    await screen.findByText('customNodes.empty');
    fireEvent.click(screen.getByText('customNodes.register'));
    await screen.findByText('customNodes.registerTitle');

    fireEvent.change(screen.getByLabelText('customNodes.fieldKey'), { target: { value: 'acme_watermark' } });
    fireEvent.change(screen.getByLabelText('customNodes.fieldName'), { target: { value: 'Acme Watermark' } });
    fireEvent.change(screen.getByLabelText('customNodes.fieldEndpoint'), { target: { value: 'https://plugins.example.com/wm' } });

    fireEvent.click(screen.getByText('customNodes.save'));

    await waitFor(() => expect(postSpy).toHaveBeenCalled());
    const [, opts] = postSpy.mock.calls[0];
    const body = JSON.parse(opts.body);
    expect(body.custom_node_definition.key).toBe('acme_watermark');
    expect(body.custom_node_definition.runtime.endpoint_url).toBe('https://plugins.example.com/wm');
    expect(opts.headers['X-CSRF-Token']).toBe('csrf-token');
  });
});
