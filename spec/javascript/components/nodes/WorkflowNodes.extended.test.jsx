import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

jest.mock('@xyflow/react', () => ({
  Handle: ({ type, id }) => <div data-testid={`handle-${type}${id ? `-${id}` : ''}`} />,
  Position: { Top: 'top', Bottom: 'bottom' },
}));

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key) => key,
  }),
}));

import NodeShell from '../../../../app/javascript/components/nodes/NodeShell';
import ConditionNode from '../../../../app/javascript/components/nodes/ConditionNode';
import DelayNode from '../../../../app/javascript/components/nodes/DelayNode';
import ApprovalNode from '../../../../app/javascript/components/nodes/ApprovalNode';
import StartNode from '../../../../app/javascript/components/nodes/StartNode';
import EndNode from '../../../../app/javascript/components/nodes/EndNode';
import GenericActionNode from '../../../../app/javascript/components/nodes/GenericActionNode';
import TeamsNode from '../../../../app/javascript/components/nodes/TeamsNode';

function buildData(stepOverrides = {}) {
  const updateNodeData = jest.fn();
  return {
    data: {
      step: {
        id: 'node-1',
        title: '',
        assigneeType: 'user',
        assigneeId: '',
        fallback_assignee_type: 'user',
        fallback_assignee_id: '',
        config: {},
        ...stepOverrides,
      },
      updateNodeData,
      users: [
        { id: 1, display_name: 'Alice Reviewer', email: 'alice@example.com' },
      ],
      groups: [
        { id: 2, name: 'Legal Team' },
      ],
    },
    updateNodeData,
    isConnectable: true,
  };
}

describe('NodeShell', () => {
  it('renders branching handles and labels', () => {
    render(
      <NodeShell label="Condition" handles="branching" branchLabels={{ true: 'YES', false: 'NO' }} isConnectable>
        <div>Body</div>
      </NodeShell>
    );

    expect(screen.getByTestId('handle-target')).toBeInTheDocument();
    expect(screen.getByTestId('handle-source-true')).toBeInTheDocument();
    expect(screen.getByTestId('handle-source-false')).toBeInTheDocument();
    expect(screen.getByText('YES')).toBeInTheDocument();
    expect(screen.getByText('NO')).toBeInTheDocument();
  });

  it('supports source-only and target-only layouts', () => {
    const { rerender } = render(
      <NodeShell label="Start" handles="source-only" isConnectable>
        <div>Start body</div>
      </NodeShell>
    );

    expect(screen.queryByTestId('handle-target')).not.toBeInTheDocument();
    expect(screen.getByTestId('handle-source')).toBeInTheDocument();

    rerender(
      <NodeShell label="End" handles="target-only" isConnectable>
        <div>End body</div>
      </NodeShell>
    );

    expect(screen.getByTestId('handle-target')).toBeInTheDocument();
    expect(screen.queryByTestId('handle-source')).not.toBeInTheDocument();
  });
});

describe('ConditionNode', () => {
  it('renders and updates branching configuration', async () => {
    const { data, updateNodeData, isConnectable } = buildData({ config: { field: 'status' } });
    render(<ConditionNode data={data} isConnectable={isConnectable} />);

    expect(screen.getByText('nodes.conditionNode')).toBeInTheDocument();
    expect(screen.getByText('nodes.condition.trueBranch')).toBeInTheDocument();
    expect(screen.getByText('nodes.condition.falseBranch')).toBeInTheDocument();

    fireEvent.change(screen.getByLabelText('nodes.condition.field'), { target: { value: 'status approval' } });
    expect(updateNodeData).toHaveBeenCalledWith('node-1', 'config', expect.objectContaining({
      field: expect.stringContaining('approval'),
    }));
  });
});

describe('DelayNode', () => {
  it('renders and clamps the duration to a minimum of 1', () => {
    const { data, updateNodeData, isConnectable } = buildData({ config: { delayValue: 2, delayUnit: 'hours' } });
    render(<DelayNode data={data} isConnectable={isConnectable} />);

    const numberInput = screen.getByRole('spinbutton');
    fireEvent.change(numberInput, { target: { value: '0' } });

    expect(updateNodeData).toHaveBeenCalledWith('node-1', 'config', expect.objectContaining({
      delayValue: 1,
      delayUnit: 'hours',
    }));
    expect(screen.getByText('nodes.delay.hint')).toBeInTheDocument();
  });
});

describe('ApprovalNode', () => {
  it('updates assignee fields and renders advanced fallback controls', async () => {
    const { data, updateNodeData, isConnectable } = buildData();
    render(<ApprovalNode data={data} isConnectable={isConnectable} />);

    fireEvent.change(screen.getByLabelText('nodes.stepTitle'), { target: { value: 'Legal' } });
    expect(updateNodeData).toHaveBeenCalledWith('node-1', 'title', 'Legal');

    const selects = screen.getAllByRole('combobox');
    fireEvent.mouseDown(selects[0]);
    await userEvent.click(await screen.findByRole('option', { name: 'nodes.approval.typeGroup' }));
    expect(updateNodeData).toHaveBeenCalledWith('node-1', 'assigneeType', 'group');
    expect(updateNodeData).toHaveBeenCalledWith('node-1', 'assigneeId', '');

    await userEvent.click(screen.getByText('nodes.approval.advancedSettings'));
    expect(screen.getByLabelText('nodes.approval.instructions')).toBeInTheDocument();
    expect(screen.getByLabelText('nodes.approval.escalateTo')).toBeInTheDocument();
  });
});

describe('StartNode and EndNode', () => {
  it('render start/end labels with their respective handles', () => {
    const { rerender } = render(<StartNode isConnectable />);
    expect(screen.getByText('START')).toBeInTheDocument();
    expect(screen.getByTestId('handle-source')).toBeInTheDocument();

    rerender(<EndNode isConnectable />);
    expect(screen.getByText('END')).toBeInTheDocument();
    expect(screen.getByTestId('handle-target')).toBeInTheDocument();
  });
});

describe('GenericActionNode', () => {
  it('renders advanced config fields and updates config data', async () => {
    const { data, updateNodeData, isConnectable } = buildData({ config: { url: '' } });
    render(<GenericActionNode type="secureWebhookNode" data={data} isConnectable={isConnectable} />);

    expect(screen.getByText('Secure Webhook')).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('nodes.webhook.url'), { target: { value: 'https://hook' } });
    expect(updateNodeData).toHaveBeenCalledWith('node-1', 'config', expect.objectContaining({
      url: 'https://hook',
    }));

    await userEvent.click(screen.getByText('nodes.configSection'));
    expect(screen.getByLabelText('nodes.secureWebhook.secret')).toBeInTheDocument();
  });
});

describe('TeamsNode', () => {
  it('renders fields and updates node config', async () => {
    const { data, updateNodeData, isConnectable } = buildData({ config: { color: 'good' } });
    render(<TeamsNode data={data} isConnectable={isConnectable} />);

    expect(screen.getByText('nodes.teamsNode')).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText('nodes.teams.title'), { target: { value: 'Card' } });
    expect(updateNodeData).toHaveBeenCalledWith('node-1', 'config', expect.objectContaining({
      teamsTitle: 'Card',
    }));

    fireEvent.mouseDown(screen.getAllByRole('combobox')[0]);
    await userEvent.click(await screen.findByRole('option', { name: 'nodes.teams.colorRed' }));
    expect(updateNodeData).toHaveBeenCalledWith('node-1', 'config', expect.objectContaining({
      color: 'attention',
    }));
  });
});
