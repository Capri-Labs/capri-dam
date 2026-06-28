import React from 'react';
import { render, screen, waitFor, act } from '@testing-library/react';
import WorkflowPanel from '../../../app/javascript/components/WorkflowPanel';

// WorkflowPanel reads the CSRF token from a meta tag and talks to the
// workflow_history endpoint. We stub both.

const HISTORY = {
  active: true,
  instances: [
    {
      instance_id: 101,
      workflow_id: 1,
      workflow_name: 'Brand Compliance',
      instance_status: 'in_progress',
      started_at: '2026-06-01T10:00:00Z',
      completed_at: null,
      cancel_reason: null,
      cancelled_by: null,
      can_force_cancel: false,
      tasks: [
        {
          id: 9001, step_name: 'Brand Review', user_name: 'me@example.com',
          status: 'pending', comment: null, completed_at: null,
          is_current_user: true, is_pending: true,
        },
      ],
    },
    {
      instance_id: 102,
      workflow_id: 2,
      workflow_name: 'Legal Sign-off',
      instance_status: 'in_progress',
      started_at: '2026-06-01T11:00:00Z',
      completed_at: null,
      cancel_reason: null,
      cancelled_by: null,
      can_force_cancel: false,
      tasks: [
        {
          id: 9002, step_name: 'Legal Review', user_name: 'legal@example.com',
          status: 'pending', comment: null, completed_at: null,
          is_current_user: false, is_pending: true,
        },
      ],
    },
  ],
};

let csrfMeta;

beforeEach(() => {
  csrfMeta = document.createElement('meta');
  csrfMeta.setAttribute('name', 'csrf-token');
  csrfMeta.setAttribute('content', 'test-token');
  document.head.appendChild(csrfMeta);
  global.fetch = jest.fn(() =>
    Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(HISTORY) })
  );
});

afterEach(() => {
  if (csrfMeta && csrfMeta.parentNode) csrfMeta.parentNode.removeChild(csrfMeta);
  jest.resetAllMocks();
});

describe('WorkflowPanel — multiple concurrent instances', () => {
  it('renders every workflow instance independently', async () => {
    await act(async () => {
      render(<WorkflowPanel assetId={42} />);
    });

    await waitFor(() => {
      expect(screen.getByText('Brand Compliance')).toBeInTheDocument();
      expect(screen.getByText('Legal Sign-off')).toBeInTheDocument();
    });

    // The header chip reflects the count of concurrent workflows.
    expect(screen.getByText('2 workflows')).toBeInTheDocument();
  });

  it('shows an Approve action only for the current user’s pending instance', async () => {
    await act(async () => {
      render(<WorkflowPanel assetId={42} />);
    });

    await waitFor(() => {
      expect(screen.getByText('Action Required: Brand Review')).toBeInTheDocument();
    });

    // Exactly one approve button: the Brand Compliance task is mine; Legal isn't.
    const approveButtons = screen.getAllByRole('button', { name: /approve/i });
    expect(approveButtons).toHaveLength(1);

    // The other instance must NOT surface an action box for me.
    expect(screen.queryByText('Action Required: Legal Review')).not.toBeInTheDocument();
  });
});


