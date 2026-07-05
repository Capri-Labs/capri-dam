import React from 'react';
import { render, screen, waitFor, fireEvent, within, act } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

var mockReactFlowProps;
var mockAddEdge = jest.fn((params, edges) => edges.concat(params));
var mockApplyNodeChanges = jest.fn((changes, nodes) => nodes.map((node) => ({ ...node, touched: true })));
var mockApplyEdgeChanges = jest.fn((changes, edges) => edges.map((edge) => ({ ...edge, touched: true })));
const mockNotify = jest.fn();
const mockT = (key, opts) => opts?.defaultValue || key;

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: mockT,
  }),
  Trans: ({ i18nKey }) => i18nKey,
}));

jest.mock('../../../../app/javascript/context/NotificationContext', () => ({
  useNotify: () => mockNotify,
}));

jest.mock('../../../../app/javascript/utils/globalutils', () => ({
  navigateTo: jest.fn(),
}));

jest.mock('../../../../app/javascript/components/WorkflowPanel', () => {
  const React = require('react');
  return function MockWorkflowPanel({ assetId }) {
    return <div data-testid="workflow-panel">asset:{assetId}</div>;
  };
});

jest.mock('@xyflow/react', () => {
  const React = require('react');
  return {
    ReactFlowProvider: ({ children }) => <div data-testid="react-flow-provider">{children}</div>,
    ReactFlow: (props) => {
      mockReactFlowProps = props;
      return (
        <div data-testid="react-flow">
          {props.nodes.map((node) => (
            <div key={node.id}>{`${node.id}:${node.type}`}</div>
          ))}
          {props.children}
        </div>
      );
    },
    Background: () => <div data-testid="react-flow-background" />,
    Controls: () => <div data-testid="react-flow-controls" />,
    MiniMap: () => <div data-testid="react-flow-minimap" />,
    Handle: ({ type, id }) => <div data-testid={`handle-${type}${id ? `-${id}` : ''}`} />,
    Position: { Top: 'top', Bottom: 'bottom', Left: 'left', Right: 'right' },
    addEdge: (...args) => mockAddEdge(...args),
    applyNodeChanges: (...args) => mockApplyNodeChanges(...args),
    applyEdgeChanges: (...args) => mockApplyEdgeChanges(...args),
  };
});

import ApprovalActions from '../../../../app/javascript/components/Workflows/ApprovalActions';
import BottleneckReport from '../../../../app/javascript/components/Workflows/BottleneckReport';
import BulkReassignModal from '../../../../app/javascript/components/Workflows/BulkReassignModal';
import NodePalette from '../../../../app/javascript/components/Workflows/NodePalette';
import WorkflowCanvas from '../../../../app/javascript/components/Workflows/WorkflowCanvas';
import WorkflowList from '../../../../app/javascript/components/Workflows/WorkflowList';
import WorkflowContainer from '../../../../app/javascript/components/WorkflowContainer';
import WorkflowDashboard from '../../../../app/javascript/components/WorkflowDashboard';

function addCsrfToken() {
  const meta = document.createElement('meta');
  meta.setAttribute('name', 'csrf-token');
  meta.setAttribute('content', 'test-csrf');
  document.head.appendChild(meta);
  return meta;
}

describe('ApprovalActions', () => {
  let csrfMeta;

  beforeEach(() => {
    csrfMeta = addCsrfToken();
    global.fetch = jest.fn(() =>
      Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true, status: 'done' }) })
    );
  });

  afterEach(() => {
    csrfMeta.remove();
    jest.clearAllMocks();
  });

  it('submits approve and decline actions with the note', async () => {
    const onActionComplete = jest.fn();
    render(<ApprovalActions assetId={42} onActionComplete={onActionComplete} />);

    await userEvent.type(screen.getByPlaceholderText('Add a reason for approval or decline...'), 'Looks good');
    await userEvent.click(screen.getByRole('button', { name: 'Approve' }));

    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith('/assets/42/workflow_action', expect.objectContaining({
        method: 'POST',
      }));
    });
    expect(JSON.parse(global.fetch.mock.calls[0][1].body)).toEqual({
      action: 'approve',
      note: 'Looks good',
    });
    await waitFor(() => expect(onActionComplete).toHaveBeenCalledWith({ success: true, status: 'done' }));

    global.fetch.mockResolvedValueOnce({ ok: true, json: () => Promise.resolve({ success: false }) });
    onActionComplete.mockClear();

    await userEvent.click(screen.getByRole('button', { name: 'Decline' }));

    await waitFor(() => {
      expect(JSON.parse(global.fetch.mock.calls[1][1].body)).toEqual({
        action: 'decline',
        note: 'Looks good',
      });
    });
    expect(onActionComplete).not.toHaveBeenCalled();
  });
});

describe('BottleneckReport', () => {
  it('renders bottleneck counts and summary text', () => {
    render(
      <BottleneckReport
        open
        onClose={jest.fn()}
        totalActive={10}
        stats={[['Legal Review', 6], ['Brand Review', 4]]}
      />
    );

    expect(screen.getByText('Workflow Bottlenecks')).toBeInTheDocument();
    expect(screen.getByText(/Currently identifying 10 active assets/)).toBeInTheDocument();
    expect(screen.getByText('Legal Review')).toBeInTheDocument();
    expect(screen.getByText('6 assets')).toBeInTheDocument();
    expect(screen.getByText('Brand Review')).toBeInTheDocument();
  });
});

describe('BulkReassignModal', () => {
  it('allows selecting a group and confirming reassignment', async () => {
    const onConfirm = jest.fn();
    const onClose = jest.fn();

    render(
      <BulkReassignModal
        open
        onClose={onClose}
        onConfirm={onConfirm}
        selectedWorkflows={[
          { instance_id: 1, asset_name: 'Asset A', asset_thumb: '/a.png', current_step: 'Review' },
        ]}
        users={[{ id: 10, name: 'Alice', email: 'alice@example.com' }]}
        groups={[{ id: 99, name: 'Legal Team' }]}
      />
    );

    expect(screen.getByText('Affected Workflows (1)')).toBeInTheDocument();
    expect(screen.getByText('Asset A')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Group' }));
    const combo = screen.getByRole('combobox', { name: 'Search groups...' });
    await userEvent.click(combo);
    await userEvent.click(await screen.findByText('Legal Team'));
    await userEvent.type(screen.getByLabelText('Reason for re-assignment'), 'Covering leave');

    const submit = screen.getByRole('button', { name: 'Execute Re-assignment' });
    expect(submit).toBeEnabled();
    await userEvent.click(submit);

    expect(onConfirm).toHaveBeenCalledWith({
      assigneeType: 'group',
      assigneeId: 99,
      reason: 'Covering leave',
    });
    expect(onClose).toHaveBeenCalled();
  });
});

describe('NodePalette', () => {
  it('renders draggable toolbox items and supports searching', async () => {
    render(<NodePalette />);

    expect(screen.getByText('Approval')).toBeInTheDocument();
    expect(screen.getByText('Slack Message')).toBeInTheDocument();

    const draggable = screen.getByText('Approval').closest('[draggable="true"]');
    const dataTransfer = { setData: jest.fn(), effectAllowed: '' };
    fireEvent.dragStart(draggable, { dataTransfer });
    expect(dataTransfer.setData).toHaveBeenCalledWith('application/reactflow', 'approvalNode');

    await userEvent.type(screen.getByPlaceholderText('Search…'), 'slack');
    expect(screen.queryByText('Approval')).not.toBeInTheDocument();
    expect(screen.getByText('Slack Message')).toBeInTheDocument();

    await userEvent.clear(screen.getByPlaceholderText('Search…'));
    await userEvent.type(screen.getByPlaceholderText('Search…'), 'zzz');
    expect(screen.getByText('No matches for "zzz"')).toBeInTheDocument();
  });
});

describe('WorkflowCanvas', () => {
  beforeEach(() => {
    mockReactFlowProps = null;
    mockAddEdge.mockClear();
    mockApplyNodeChanges.mockClear();
    mockApplyEdgeChanges.mockClear();
  });

  it('renders React Flow and hydrates interactive nodes with shared data', () => {
    const setNodes = jest.fn();
    const setEdges = jest.fn();
    const nodes = [{ id: 'email_1', type: 'emailNode', data: { step: { id: 'email_1', config: {} } } }];
    const users = [{ id: 7, name: 'Alice' }];
    const groups = [{ id: 8, name: 'Legal' }];

    render(
      <WorkflowCanvas
        nodes={nodes}
        setNodes={setNodes}
        edges={[]}
        setEdges={setEdges}
        users={users}
        groups={groups}
      />
    );

    expect(screen.getByTestId('react-flow')).toBeInTheDocument();
    expect(screen.getByText('email_1:emailNode')).toBeInTheDocument();

    const hydrateUpdater = setNodes.mock.calls[0][0];
    const hydrated = hydrateUpdater(nodes);
    expect(hydrated[0].data.users).toBe(users);
    expect(hydrated[0].data.groups).toBe(groups);
    expect(typeof hydrated[0].data.updateNodeData).toBe('function');
  });

  it('adds dropped nodes and connects edges through React Flow callbacks', () => {
    const setNodes = jest.fn();
    const setEdges = jest.fn();

    render(
      <WorkflowCanvas
        nodes={[]}
        setNodes={setNodes}
        edges={[]}
        setEdges={setEdges}
      />
    );

    act(() => {
      mockReactFlowProps.onInit({
        screenToFlowPosition: ({ x, y }) => ({ x, y }),
      });
    });

    act(() => {
      mockReactFlowProps.onDrop({
        preventDefault: jest.fn(),
        dataTransfer: { getData: () => 'approvalNode' },
        clientX: 12,
        clientY: 24,
      });
    });

    const addNodeUpdater = setNodes.mock.calls.at(-1)[0];
    const [createdNode] = addNodeUpdater([]);
    expect(createdNode.type).toBe('approvalNode');
    expect(createdNode.data.step.isApproval).toBe(true);
    expect(createdNode.position).toEqual({ x: 12, y: 24 });

    act(() => {
      mockReactFlowProps.onConnect({ source: 'a', target: 'b' });
    });
    const edgeUpdater = setEdges.mock.calls[0][0];
    expect(edgeUpdater([])).toEqual([
      expect.objectContaining({
        source: 'a',
        target: 'b',
        animated: true,
        style: { strokeWidth: 2 },
      }),
    ]);
  });
});

describe('WorkflowList', () => {
  let csrfMeta;
  const originalConfirm = window.confirm;
  const originalAlert = window.alert;
  const originalConsoleLog = console.log;
  const originalConsoleError = console.error;

  beforeEach(() => {
    csrfMeta = addCsrfToken();
    window.confirm = jest.fn(() => true);
    window.alert = jest.fn();
    console.log = jest.fn();
    console.error = jest.fn();
    global.fetch = jest.fn(() => Promise.resolve({ ok: true, json: () => Promise.resolve({}) }));
  });

  afterEach(() => {
    csrfMeta.remove();
    window.confirm = originalConfirm;
    window.alert = originalAlert;
    console.log = originalConsoleLog;
    console.error = originalConsoleError;
    jest.clearAllMocks();
  });

  it('renders workflows, opens create, and invokes edit/delete actions', async () => {
    const onCreate = jest.fn();
    const onEdit = jest.fn();

    render(
      <WorkflowList
        workflows={[
          {
            id: 1,
            name: 'Legal Review',
            description: 'Legal approval path',
            trigger_type: 'manual',
            step_count: 3,
            status: 'active',
            last_modified_by: 'Admin',
            updated_at: '2026-07-01',
          },
        ]}
        onCreate={onCreate}
        onEdit={onEdit}
      />
    );

    expect(screen.getByText('Legal Review')).toBeInTheDocument();
    expect(screen.getByText('3 Steps')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Create New Workflow' }));
    expect(onCreate).toHaveBeenCalled();

    await userEvent.click(screen.getByLabelText('Edit Workflow'));
    expect(onEdit).toHaveBeenCalledWith(expect.objectContaining({ id: 1, name: 'Legal Review' }));

    await userEvent.click(screen.getByLabelText('Delete'));
    await waitFor(() => {
      expect(global.fetch).toHaveBeenCalledWith('/workflows/1', expect.objectContaining({ method: 'DELETE' }));
    });
  });

  it('shows an empty state when there are no workflows', () => {
    render(<WorkflowList workflows={[]} onCreate={jest.fn()} onEdit={jest.fn()} />);
    expect(screen.getByText(/No workflows created yet/)).toBeInTheDocument();
  });

  it('renders pagination controls and invokes onPageChange', async () => {
    const onPageChange = jest.fn();
    render(
      <WorkflowList
        workflows={[{ id: 1, name: 'Legal Review', status: 'active', updated_at: '2026-07-01' }]}
        pagination={{ page: 2, per_page: 25, total: 60, total_pages: 3 }}
        onPageChange={onPageChange}
        onCreate={jest.fn()}
        onEdit={jest.fn()}
      />
    );

    expect(screen.getByText('Page 2 of 3')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /Next/ }));
    expect(onPageChange).toHaveBeenCalledWith(3);

    await userEvent.click(screen.getByRole('button', { name: /Prev/ }));
    expect(onPageChange).toHaveBeenCalledWith(1);
  });

  it('does not render pagination controls when there is only one page', () => {
    render(
      <WorkflowList
        workflows={[{ id: 1, name: 'Legal Review', status: 'active', updated_at: '2026-07-01' }]}
        pagination={{ page: 1, per_page: 25, total: 1, total_pages: 1 }}
        onCreate={jest.fn()}
        onEdit={jest.fn()}
      />
    );
    expect(screen.queryByText(/Page 1 of 1/)).not.toBeInTheDocument();
  });
});

describe('WorkflowContainer', () => {
  let csrfMeta;

  beforeEach(() => {
    csrfMeta = addCsrfToken();
    global.fetch = jest.fn((url) => {
      if (String(url).includes('/admin/users.json')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ users: [] }) });
      }
      if (String(url).includes('/admin/user_groups.json')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ user_groups: [] }) });
      }
      if (String(url).includes('/api/v1/folders.json')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ folders: [] }) });
      }
      if (String(url).includes('/workflows/1.json')) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({
            id: 1,
            name: 'Existing Workflow',
            status: 'active',
            trigger_type: 'manual',
            folder_scope: 'all',
            workflow_steps: [],
          }),
        });
      }
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
    });
  });

  afterEach(() => {
    csrfMeta.remove();
    jest.clearAllMocks();
  });

  it('shows the list view first and switches to designer on create', async () => {
    render(
      <WorkflowContainer
        workflows={JSON.stringify([{ id: 1, name: 'Review Flow', status: 'active', updated_at: '2026-07-01' }])}
      />
    );

    expect(screen.getByText('Approval Workflows')).toBeInTheDocument();
    expect(screen.getByText('Review Flow')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Create New Workflow' }));

    expect(await screen.findByText('workflowDesigner.title')).toBeInTheDocument();
  });

  it('loads workflow details and opens the designer for editing', async () => {
    render(
      <WorkflowContainer
        workflows={JSON.stringify([{ id: 1, name: 'Review Flow', status: 'active', updated_at: '2026-07-01' }])}
      />
    );

    await userEvent.click(screen.getByLabelText('Edit Workflow'));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/workflows/1.json'));
    expect(await screen.findByRole('button', { name: /savechanges/i })).toBeInTheDocument();
  });

  it('fetches the next page of workflows when pagination controls are used', async () => {
    global.fetch.mockImplementation((url) => {
      if (String(url).startsWith('/workflows.json?page=2')) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({
            workflows: [{ id: 2, name: 'Second Page Flow', status: 'active', updated_at: '2026-07-02' }],
            pagination: { page: 2, per_page: 25, total: 30, total_pages: 2 },
          }),
        });
      }
      return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
    });

    render(
      <WorkflowContainer
        workflows={JSON.stringify([{ id: 1, name: 'Review Flow', status: 'active', updated_at: '2026-07-01' }])}
        workflowsPagination={JSON.stringify({ page: 1, per_page: 25, total: 30, total_pages: 2 })}
      />
    );

    expect(screen.getByText('Page 1 of 2')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /Next/ }));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledWith('/workflows.json?page=2'));
    expect(await screen.findByText('Second Page Flow')).toBeInTheDocument();
    expect(screen.getByText('Page 2 of 2')).toBeInTheDocument();
  });
});

describe('WorkflowDashboard', () => {
  let csrfMeta;

  beforeEach(() => {
    csrfMeta = addCsrfToken();
    mockNotify.mockClear();
    window.history.replaceState({}, '', '/workflows/dashboard');
    global.fetch = jest.fn((url, options = {}) => {
      if (String(url).startsWith('/api/v1/workflows/dashboard')) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({
            my_tasks: [
              {
                task_id: 1,
                asset_id: 55,
                asset_name: 'Homepage Banner',
                asset_thumb: '/banner.png',
                step_title: 'Brand Review',
                assigned_at: '2026-07-01T10:00:00Z',
              },
            ],
            active_workflows: [
              {
                instance_id: 10,
                workflow_name: 'Release Review',
                asset_id: 88,
                asset_name: 'Release Notes',
                current_step: 'Legal',
                started_at: '2026-07-01T09:00:00Z',
              },
            ],
            completed_workflows: [
              {
                instance_id: 99,
                workflow_name: 'Archive Check',
                asset_id: 77,
                asset_name: 'Legacy Asset',
                status: 'completed',
                completed_at: '2026-07-01T08:00:00Z',
              },
            ],
            pagination: {
              my_tasks: { page: 1, per_page: 10, total: 1, total_pages: 1 },
              active_workflows: { page: 1, per_page: 10, total: 1, total_pages: 1 },
              completed_workflows: { page: 1, per_page: 10, total: 1, total_pages: 1 },
            },
          }),
        });
      }

      if (url === '/api/v1/workflows/bulk_reassign') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
      }

      if (String(url).includes('/force_cancel')) {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
      }

      if (options.method === 'DELETE') {
        return Promise.resolve({ ok: true, json: () => Promise.resolve({ success: true }) });
      }

      return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
    });
  });

  afterEach(() => {
    csrfMeta.remove();
    window.history.replaceState({}, '', '/');
    jest.clearAllMocks();
  });

  it('renders dashboard metrics and opens the review drawer', async () => {
    render(<WorkflowDashboard />);

    expect(await screen.findByText('Workflow Operations Center')).toBeInTheDocument();
    expect(screen.getByText('My Pending Tasks')).toBeInTheDocument();
    expect(screen.getByText('Active Workflows')).toBeInTheDocument();
    expect(screen.getByText('Completed (recent)')).toBeInTheDocument();
    expect(await screen.findByText('Homepage Banner')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Review' }));

    expect(await screen.findByTestId('workflow-panel')).toHaveTextContent('asset:55');
  });

  it('opens the workflow panel from the asset_id query parameter', async () => {
    window.history.replaceState({}, '', '/workflows/dashboard?asset_id=321');

    render(<WorkflowDashboard />);

    expect(await screen.findByTestId('workflow-panel')).toHaveTextContent('asset:321');
  });

  it('shows pagination controls and requests the next page for My Pending Tasks', async () => {
    global.fetch = jest.fn((url) => {
      if (String(url).startsWith('/api/v1/workflows/dashboard')) {
        return Promise.resolve({
          ok: true,
          json: () => Promise.resolve({
            my_tasks: [
              {
                task_id: 1,
                asset_id: 55,
                asset_name: 'Homepage Banner',
                asset_thumb: '/banner.png',
                step_title: 'Brand Review',
                assigned_at: '2026-07-01T10:00:00Z',
              },
            ],
            active_workflows: [],
            completed_workflows: [],
            pagination: {
              my_tasks: { page: 1, per_page: 10, total: 15, total_pages: 2 },
              active_workflows: { page: 1, per_page: 10, total: 0, total_pages: 1 },
              completed_workflows: { page: 1, per_page: 10, total: 0, total_pages: 1 },
            },
          }),
        });
      }
      return Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
    });

    render(<WorkflowDashboard />);

    expect(await screen.findByText('Homepage Banner')).toBeInTheDocument();
    const nextButton = screen.getByRole('button', { name: /Next/ });
    expect(nextButton).toBeEnabled();

    await userEvent.click(nextButton);

    await waitFor(() => {
      expect(global.fetch).toHaveBeenLastCalledWith(
        expect.stringContaining('my_tasks_page=2')
      );
    });
  });
});
