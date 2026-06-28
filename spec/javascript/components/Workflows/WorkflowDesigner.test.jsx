/**
 * Tests for the redesigned Visual Workflow Designer.
 *
 * Focus areas:
 *   1. Renders the redesigned chrome (sticky header, sections) without the
 *      removed "System-Wide Escalation" block.
 *   2. Validates the blueprint name before saving.
 *   3. Persists per-step fallback_assignee fields in the save payload
 *      (the bug this refactor fixes).
 *   4. Uses the correct REST verb/URL for create vs. edit.
 *
 * @xyflow/react and the heavy WorkflowCanvas are mocked so the test stays a
 * focused unit test of the designer shell rather than the canvas internals.
 */

import React from 'react';
import { render, screen, waitFor, act } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

// react-i18next: return the key path so assertions are deterministic.
jest.mock('react-i18next', () => ({
  useTranslation: () => ({ t: (key, opts) => (opts?.count != null ? `${key}:${opts.count}` : key) }),
}));

// Notification context: capture notify() calls.
const mockNotify = jest.fn();
jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

// Mock the canvas: expose a button that injects an approval node carrying a
// step-level fallback so we can assert the save payload includes it.
jest.mock('../../../../app/javascript/components/Workflows/WorkflowCanvas', () => {
  const React = require('react');
  return function MockCanvas({ setNodes }) {
    return (
      <button
        type="button"
        data-testid="inject-approval"
        onClick={() =>
          setNodes((nds) => [
            ...nds,
            {
              id: 'approval_new',
              type: 'approvalNode',
              position: { x: 0, y: 0 },
              data: {
                step: {
                  id: 'approval_new',
                  isNew: true,
                  title: 'Legal Review',
                  assigneeType: 'user',
                  assigneeId: 7,
                  fallback_assignee_type: 'group',
                  fallback_assignee_id: 99,
                  logic: 'any',
                  deadline_days: 3,
                  config: {},
                },
              },
            },
          ])
        }
      >
        inject
      </button>
    );
  };
});

import WorkflowDesigner from '../../../../app/javascript/components/Workflows/WorkflowDesigner';

// ── Shared fetch stub ───────────────────────────────────────────────────────

let csrfMeta;

beforeEach(() => {
  mockNotify.mockClear();

  csrfMeta = document.createElement('meta');
  csrfMeta.setAttribute('name', 'csrf-token');
  csrfMeta.setAttribute('content', 'test-csrf');
  document.head.appendChild(csrfMeta);

  global.fetch = jest.fn((url, opts) => {
    // Dictionary endpoints
    if (typeof url === 'string' && url.includes('/admin/users.json')) {
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ users: [] }) });
    }
    if (typeof url === 'string' && url.includes('/admin/user_groups.json')) {
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ user_groups: [] }) });
    }
    if (typeof url === 'string' && url.includes('/api/v1/folders.json')) {
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ folders: [] }) });
    }
    // Save endpoint
    return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
  });
});

afterEach(() => {
  if (csrfMeta && csrfMeta.parentNode) csrfMeta.parentNode.removeChild(csrfMeta);
  jest.resetAllMocks();
});

// ────────────────────────────────────────────────────────────────────────────

describe('WorkflowDesigner — redesigned shell', () => {
  it('renders the title and the new section headers', async () => {
    await act(async () => {
      render(<WorkflowDesigner onSave={jest.fn()} onCancel={jest.fn()} />);
    });

    expect(screen.getByText('workflowDesigner.title')).toBeInTheDocument();
    expect(screen.getByText('workflowDesigner.blueprintSection')).toBeInTheDocument();
    expect(screen.getByText('workflowDesigner.triggerScopeSection')).toBeInTheDocument();
  });

  it('does NOT render the removed "System-Wide Escalation" block', async () => {
    await act(async () => {
      render(<WorkflowDesigner onSave={jest.fn()} onCancel={jest.fn()} />);
    });

    // None of the old escalation keys/labels should appear
    expect(screen.queryByText('workflowDesigner.systemEscalation')).not.toBeInTheDocument();
    expect(screen.queryByText(/System-Wide Escalation/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/Fallback User/i)).not.toBeInTheDocument();
  });

  it('blocks saving and notifies when the blueprint name is blank', async () => {
    const onSave = jest.fn();
    await act(async () => {
      render(<WorkflowDesigner onSave={onSave} onCancel={jest.fn()} />);
    });

    const saveBtn = screen.getByRole('button', { name: /publishBlueprint/i });
    await act(async () => {
      await userEvent.click(saveBtn);
    });

    expect(mockNotify).toHaveBeenCalledWith('workflowDesigner.validationNoName', 'error');
    expect(onSave).not.toHaveBeenCalled();
  });
});

describe('WorkflowDesigner — save payload', () => {
  it('persists per-step fallback_assignee fields', async () => {
    const onSave = jest.fn();

    await act(async () => {
      render(<WorkflowDesigner onSave={onSave} onCancel={jest.fn()} />);
    });

    // 1. Provide a name
    const nameInput = screen.getByLabelText(/workflowDesigner.blueprintName/i);
    await act(async () => {
      await userEvent.type(nameInput, 'Brand Compliance');
    });

    // 2. Inject an approval node with a step-level fallback via the mock canvas
    await act(async () => {
      await userEvent.click(screen.getByTestId('inject-approval'));
    });

    // 3. Save
    const saveBtn = screen.getByRole('button', { name: /publishBlueprint/i });
    await act(async () => {
      await userEvent.click(saveBtn);
    });

    // Find the POST /workflows call
    const saveCall = global.fetch.mock.calls.find(
      ([url, opts]) => url === '/workflows' && opts?.method === 'POST'
    );
    expect(saveCall).toBeTruthy();

    const body = JSON.parse(saveCall[1].body);
    const step = body.workflow.workflow_steps_attributes[0];

    expect(step.fallback_assignee_type).toBe('group');
    expect(step.fallback_assignee_id).toBe(99);
    expect(step.assignee_type).toBe('user');
    expect(step.assignee_id).toBe(7);

    await waitFor(() => expect(onSave).toHaveBeenCalled());
  });

  it('uses PUT and the id-scoped URL when editing an existing workflow', async () => {
    const onSave = jest.fn();
    const initialData = {
      id: 55,
      name: 'Existing WF',
      status: 'active',
      trigger_type: 'manual',
      folder_scope: 'all',
      workflow_steps: [],
    };

    await act(async () => {
      render(<WorkflowDesigner initialData={initialData} onSave={onSave} onCancel={jest.fn()} />);
    });

    const saveBtn = screen.getByRole('button', { name: /saveChanges/i });
    await act(async () => {
      await userEvent.click(saveBtn);
    });

    const putCall = global.fetch.mock.calls.find(
      ([url, opts]) => url === '/workflows/55' && opts?.method === 'PUT'
    );
    expect(putCall).toBeTruthy();
    await waitFor(() => expect(onSave).toHaveBeenCalled());
  });
});


