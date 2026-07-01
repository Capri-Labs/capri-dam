import React from 'react';
import { render, screen, waitFor, act } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import WorkflowPanel from '../../../app/javascript/components/WorkflowPanel';

function addCsrfToken() {
  const meta = document.createElement('meta');
  meta.setAttribute('name', 'csrf-token');
  meta.setAttribute('content', 'test-token');
  document.head.appendChild(meta);
  return meta;
}

describe('WorkflowPanel — extended coverage', () => {
  let csrfMeta;
  const originalAlert = window.alert;
  const originalPrompt = window.prompt;

  beforeEach(() => {
    csrfMeta = addCsrfToken();
    window.alert = jest.fn();
    window.prompt = jest.fn();
  });

  afterEach(() => {
    csrfMeta.remove();
    window.alert = originalAlert;
    window.prompt = originalPrompt;
    jest.clearAllMocks();
  });

  it('renders empty workflow history, asset preview, and close action', async () => {
    global.fetch = jest.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve({ instances: [] }) })
    );
    const onClose = jest.fn();

    await act(async () => {
      render(<WorkflowPanel assetId={42} assetThumb="/preview.png" onClose={onClose} />);
    });

    expect(await screen.findByText('No Workflows')).toBeInTheDocument();
    expect(screen.getByAltText('Asset Preview')).toHaveAttribute('src', '/preview.png');

    await userEvent.click(screen.getByRole('button'));
    expect(onClose).toHaveBeenCalled();
  });

  it('shows an error banner when history loading fails', async () => {
    global.fetch = jest.fn(() =>
      Promise.resolve({ ok: false, json: () => Promise.resolve({}) })
    );

    await act(async () => {
      render(<WorkflowPanel assetId={7} />);
    });

    expect(await screen.findByText('Could not load workflow details. Please try again.')).toBeInTheDocument();
  });

  it('renders cancelled and empty-task warnings', async () => {
    global.fetch = jest.fn(() =>
      Promise.resolve({
        ok: true,
        json: () =>
          Promise.resolve({
            instances: [
              {
                instance_id: 1,
                workflow_name: 'Cancelled Flow',
                instance_status: 'canceled',
                cancel_reason: 'Duplicate asset',
                cancelled_by: 'Admin User',
                can_force_cancel: false,
                tasks: [],
              },
              {
                instance_id: 2,
                workflow_name: 'Broken Flow',
                instance_status: 'in_progress',
                cancel_reason: null,
                cancelled_by: null,
                can_force_cancel: false,
                tasks: [],
              },
            ],
          }),
      })
    );

    await act(async () => {
      render(<WorkflowPanel assetId={8} />);
    });

    expect(await screen.findByText(/Cancelled by Admin User: Duplicate asset/)).toBeInTheDocument();
    expect(screen.getByText(/generated no tasks/)).toBeInTheDocument();
  });

  it('submits a rejection and force-cancels an instance', async () => {
    const onWorkflowUpdate = jest.fn();
    const historyPayload = {
      instances: [
        {
          instance_id: 11,
          workflow_name: 'Brand Review',
          instance_status: 'in_progress',
          cancel_reason: null,
          cancelled_by: null,
          can_force_cancel: true,
          tasks: [
            {
              id: 222,
              step_name: 'Brand Gate',
              user_name: 'me@example.com',
              status: 'pending',
              comment: null,
              completed_at: null,
              is_current_user: true,
              is_pending: true,
            },
          ],
        },
      ],
    };

    global.fetch = jest.fn((url) => {
      if (url === '/api/v1/assets/9/workflow_history') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve(historyPayload) });
      }
      if (url === '/api/v1/workflow_tasks/222/submit') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
      }
      if (url === '/api/v1/workflow_instances/11/force_cancel') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
      }
      return Promise.resolve({ ok: true, json: () => Promise.resolve(historyPayload) });
    });
    window.prompt = jest.fn(() => 'No longer needed');

    await act(async () => {
      render(<WorkflowPanel assetId={9} onWorkflowUpdate={onWorkflowUpdate} />);
    });

    expect(await screen.findByText('Action Required: Brand Gate')).toBeInTheDocument();

    await userEvent.type(screen.getByPlaceholderText('Add your review notes (required for rejection)…'), 'Needs changes');
    await userEvent.click(screen.getByRole('button', { name: 'Decline' }));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/workflow_tasks/222/submit', expect.objectContaining({
        method: 'POST',
      }));
    });
    expect(JSON.parse(global.fetch.mock.calls.find(([url]) => url.includes('/submit'))[1].body)).toEqual({
      decision: 'rejected',
      comment: 'Needs changes',
    });

    await userEvent.click(screen.getByLabelText('Force-cancel this workflow (admin)'));
    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith('/api/v1/workflow_instances/11/force_cancel', expect.objectContaining({
        method: 'POST',
      }));
    });
    expect(onWorkflowUpdate).toHaveBeenCalled();
  });
});
