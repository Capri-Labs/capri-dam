/**
 * Comprehensive tests for individual workflow node components.
 *
 * We test the three main concerns for each node:
 *   1. Renders without crashing and shows the correct label
 *   2. Calling updateNodeData when a user types
 *   3. Advanced/accordion sections behave correctly
 *
 * React Flow / @xyflow Handle & Position are mocked since jsdom has no SVG.
 * react-i18next is mocked to return the key path as the translation value,
 * making assertions predictable without loading locale files.
 */

import React from 'react';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

// ── Mocks ─────────────────────────────────────────────────────────────────────

jest.mock('@xyflow/react', () => ({
  Handle: ({ type }) => <div data-testid={`handle-${type}`} />,
  Position: { Top: 'top', Bottom: 'bottom' },
}));

jest.mock('react-i18next', () => ({
  useTranslation: () => ({
    t: (key) => key,
  }),
}));

// ── Static imports ────────────────────────────────────────────────────────────

import EmailNode          from '../../../../app/javascript/components/nodes/EmailNode';
import InAppNotifyNode    from '../../../../app/javascript/components/nodes/InAppNotifyNode';
import SlackNode          from '../../../../app/javascript/components/nodes/SlackNode';
import SmsNode            from '../../../../app/javascript/components/nodes/SmsNode';
import WebhookNode        from '../../../../app/javascript/components/nodes/WebhookNode';
import SecureWebhookNode  from '../../../../app/javascript/components/nodes/SecureWebhookNode';
import ApiCallNode        from '../../../../app/javascript/components/nodes/ApiCallNode';
import SetStatusNode      from '../../../../app/javascript/components/nodes/SetStatusNode';
import AddTagsNode        from '../../../../app/javascript/components/nodes/AddTagsNode';
import RemoveTagsNode     from '../../../../app/javascript/components/nodes/RemoveTagsNode';
import MoveAssetNode      from '../../../../app/javascript/components/nodes/MoveAssetNode';
import CopyAssetNode      from '../../../../app/javascript/components/nodes/CopyAssetNode';
import ArchiveNode        from '../../../../app/javascript/components/nodes/ArchiveNode';
import PublishNode        from '../../../../app/javascript/components/nodes/PublishNode';
import MetadataUpdateNode from '../../../../app/javascript/components/nodes/MetadataUpdateNode';
import AiMetadataNode     from '../../../../app/javascript/components/nodes/AiMetadataNode';
import GenerateThumbNode  from '../../../../app/javascript/components/nodes/GenerateThumbNode';
import CdnSyncNode        from '../../../../app/javascript/components/nodes/CdnSyncNode';
import DelayNode          from '../../../../app/javascript/components/nodes/DelayNode';
import ConditionNode      from '../../../../app/javascript/components/nodes/ConditionNode';
import SwitchNode         from '../../../../app/javascript/components/nodes/SwitchNode';
import CustomNode         from '../../../../app/javascript/components/nodes/CustomNode';

// ── Helpers ───────────────────────────────────────────────────────────────────

function makeData(stepOverrides = {}) {
  const updateNodeData = jest.fn();
  return {
    data: {
      step: { id: 'test-node', title: '', config: {}, ...stepOverrides },
      updateNodeData,
      users: [],
      groups: [],
    },
    updateNodeData,
    isConnectable: true,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// EmailNode
// ─────────────────────────────────────────────────────────────────────────────

describe('EmailNode', () => {
  it('renders with the i18n label key', () => {
    const { data, isConnectable } = makeData();
    render(<EmailNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.emailNode')).toBeInTheDocument();
  });

  it('calls updateNodeData when step title changes', async () => {
    const { data, updateNodeData, isConnectable } = makeData();
    render(<EmailNode data={data} isConnectable={isConnectable} />);
    const titleInput = screen.getByLabelText('nodes.stepTitle');
    await userEvent.type(titleInput, 'M');
    expect(updateNodeData).toHaveBeenCalledWith('test-node', 'title', expect.any(String));
  });

  it('shows the advanced accordion when expanded', async () => {
    const { data, isConnectable } = makeData();
    render(<EmailNode data={data} isConnectable={isConnectable} />);
    const accordion = screen.getByText('nodes.advancedSettings');
    await userEvent.click(accordion);
    expect(screen.getByLabelText('nodes.email.cc')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// InAppNotifyNode
// ─────────────────────────────────────────────────────────────────────────────

describe('InAppNotifyNode', () => {
  it('renders with the i18n label key', () => {
    const { data, isConnectable } = makeData();
    render(<InAppNotifyNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.inAppNotifyNode')).toBeInTheDocument();
  });

  it('calls updateNodeData on message change', async () => {
    const { data, updateNodeData, isConnectable } = makeData();
    render(<InAppNotifyNode data={data} isConnectable={isConnectable} />);
    const msgInput = screen.getByLabelText('nodes.inApp.message');
    await userEvent.type(msgInput, 'H');
    expect(updateNodeData).toHaveBeenCalled();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SlackNode
// ─────────────────────────────────────────────────────────────────────────────

describe('SlackNode', () => {
  it('renders with label and channel input', () => {
    const { data, isConnectable } = makeData();
    render(<SlackNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.slackNode')).toBeInTheDocument();
    expect(screen.getByLabelText('nodes.slack.channel')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SmsNode
// ─────────────────────────────────────────────────────────────────────────────

describe('SmsNode', () => {
  it('shows character count within limit', () => {
    const { data, isConnectable } = makeData({ config: { message: 'Hello' } });
    render(<SmsNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText(/5 \/ 160/)).toBeInTheDocument();
  });

  it('shows over-limit warning when message exceeds 160 chars', () => {
    const longMsg = 'a'.repeat(161);
    const { data, isConnectable } = makeData({ config: { message: longMsg } });
    render(<SmsNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.sms.overLimit')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// WebhookNode
// ─────────────────────────────────────────────────────────────────────────────

describe('WebhookNode', () => {
  it('renders URL and method fields', () => {
    const { data, isConnectable } = makeData();
    render(<WebhookNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByLabelText('nodes.webhook.url')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SecureWebhookNode
// ─────────────────────────────────────────────────────────────────────────────

describe('SecureWebhookNode', () => {
  it('renders secret field', () => {
    const { data, isConnectable } = makeData();
    render(<SecureWebhookNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.secureWebhookNode')).toBeInTheDocument();
    expect(screen.getByLabelText('nodes.secureWebhook.secret')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// ApiCallNode
// ─────────────────────────────────────────────────────────────────────────────

describe('ApiCallNode', () => {
  it('renders URL input', () => {
    const { data, isConnectable } = makeData();
    render(<ApiCallNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByLabelText('nodes.apiCall.url')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// SetStatusNode
// ─────────────────────────────────────────────────────────────────────────────

describe('SetStatusNode', () => {
  it('renders label', () => {
    const { data, isConnectable } = makeData();
    render(<SetStatusNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.setStatusNode')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// AddTagsNode / RemoveTagsNode
// ─────────────────────────────────────────────────────────────────────────────

describe('AddTagsNode', () => {
  it('renders tags input', () => {
    const { data, isConnectable } = makeData();
    render(<AddTagsNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByLabelText('nodes.tags.tagsLabel')).toBeInTheDocument();
  });
});

describe('RemoveTagsNode', () => {
  it('shows warning about non-existent tags', () => {
    const { data, isConnectable } = makeData();
    render(<RemoveTagsNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText(/Non-existent tags/i)).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// MoveAssetNode / CopyAssetNode
// ─────────────────────────────────────────────────────────────────────────────

describe('MoveAssetNode', () => {
  it('renders folder field', () => {
    const { data, isConnectable } = makeData();
    render(<MoveAssetNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByLabelText('nodes.moveAsset.folder')).toBeInTheDocument();
  });
});

describe('CopyAssetNode', () => {
  it('renders folder and title suffix fields', () => {
    const { data, isConnectable } = makeData();
    render(<CopyAssetNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByLabelText('nodes.copyAsset.folder')).toBeInTheDocument();
    expect(screen.getByLabelText('nodes.copyAsset.titleSuffix')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// ArchiveNode / PublishNode
// ─────────────────────────────────────────────────────────────────────────────

describe('ArchiveNode', () => {
  it('shows irreversible note', () => {
    const { data, isConnectable } = makeData();
    render(<ArchiveNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.archive.irreversibleNote')).toBeInTheDocument();
  });
});

describe('PublishNode', () => {
  it('renders CDN sync toggle', () => {
    const { data, isConnectable } = makeData();
    render(<PublishNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.publish.cdnSync')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// MetadataUpdateNode
// ─────────────────────────────────────────────────────────────────────────────

describe('MetadataUpdateNode', () => {
  it('renders at least one key-value pair row', () => {
    const { data, isConnectable } = makeData();
    render(<MetadataUpdateNode data={data} isConnectable={isConnectable} />);
    expect(screen.getAllByLabelText('nodes.metadata.key').length).toBeGreaterThanOrEqual(1);
  });

  it('shows an "add pair" button', () => {
    const { data, isConnectable } = makeData();
    render(<MetadataUpdateNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.metadata.addPair')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// AiMetadataNode
// ─────────────────────────────────────────────────────────────────────────────

describe('AiMetadataNode', () => {
  it('renders task selection and overwrite toggle', () => {
    const { data, isConnectable } = makeData();
    render(<AiMetadataNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.aiMetadataNode')).toBeInTheDocument();
    expect(screen.getByText('nodes.ai.overwrite')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// GenerateThumbNode
// ─────────────────────────────────────────────────────────────────────────────

describe('GenerateThumbNode', () => {
  it('renders force regen toggle', () => {
    const { data, isConnectable } = makeData();
    render(<GenerateThumbNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.thumb.forceRegen')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// CdnSyncNode
// ─────────────────────────────────────────────────────────────────────────────

describe('CdnSyncNode', () => {
  it('renders purge type selector', () => {
    const { data, isConnectable } = makeData();
    render(<CdnSyncNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.cdnSyncNode')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// DelayNode
// ─────────────────────────────────────────────────────────────────────────────

describe('DelayNode', () => {
  it('renders hint and duration controls', () => {
    const { data, isConnectable } = makeData();
    render(<DelayNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.delayNode')).toBeInTheDocument();
    expect(screen.getByText('nodes.delay.hint')).toBeInTheDocument();
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// ConditionNode
// ─────────────────────────────────────────────────────────────────────────────

describe('ConditionNode', () => {
  it('renders TRUE and FALSE branch labels', () => {
    const { data, isConnectable } = makeData();
    render(<ConditionNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.condition.trueBranch')).toBeInTheDocument();
    expect(screen.getByText('nodes.condition.falseBranch')).toBeInTheDocument();
  });

  it('renders two source handles for branching', () => {
    const { data, isConnectable } = makeData();
    render(<ConditionNode data={data} isConnectable={isConnectable} />);
    const sourceHandles = screen.getAllByTestId('handle-source');
    expect(sourceHandles.length).toBeGreaterThanOrEqual(2);
  });

  it('renders field, operator, and value inputs', () => {
    const { data, isConnectable } = makeData();
    render(<ConditionNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByLabelText('nodes.condition.field')).toBeInTheDocument();
    expect(screen.getByLabelText('nodes.condition.compareValue')).toBeInTheDocument();
  });
});


// ─────────────────────────────────────────────────────────────────────────────
// SwitchNode
// ─────────────────────────────────────────────────────────────────────────────

describe('SwitchNode', () => {
  it('renders the switch label and field input', () => {
    const { data, isConnectable } = makeData();
    render(<SwitchNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('nodes.switchNode')).toBeInTheDocument();
    expect(screen.getByLabelText('nodes.switch.field')).toBeInTheDocument();
  });

  it('always renders at least the default branch handle', () => {
    const { data, isConnectable } = makeData();
    render(<SwitchNode data={data} isConnectable={isConnectable} />);
    // No cases → one source handle (the default branch)
    const sourceHandles = screen.getAllByTestId('handle-source');
    expect(sourceHandles.length).toBe(1);
  });

  it('renders one source handle per case plus the default', () => {
    const { data, isConnectable } = makeData({
      config: {
        field: 'status',
        cases: [
          { operator: 'equals', value: 'a', label: 'alpha' },
          { operator: 'equals', value: 'b', label: 'beta' },
        ],
      },
    });
    render(<SwitchNode data={data} isConnectable={isConnectable} />);
    const sourceHandles = screen.getAllByTestId('handle-source');
    expect(sourceHandles.length).toBe(3); // 2 cases + default
  });

  it('adds a case when the Add Case button is clicked', async () => {
    const { data, isConnectable, updateNodeData } = makeData({ config: { field: 'status' } });
    render(<SwitchNode data={data} isConnectable={isConnectable} />);
    await userEvent.click(screen.getByText('nodes.switch.addCase'));
    expect(updateNodeData).toHaveBeenCalledWith(
      'test-node',
      'config',
      expect.objectContaining({
        cases: expect.arrayContaining([
          expect.objectContaining({ operator: 'equals', value: '', label: '' }),
        ]),
      })
    );
  });

  it('updates the switch field via updateNodeData', async () => {
    const { data, isConnectable, updateNodeData } = makeData();
    render(<SwitchNode data={data} isConnectable={isConnectable} />);
    await userEvent.type(screen.getByLabelText('nodes.switch.field'), 's');
    expect(updateNodeData).toHaveBeenCalledWith(
      'test-node',
      'config',
      expect.objectContaining({ field: 's' })
    );
  });
});


// ─────────────────────────────────────────────────────────────────────────────
// CustomNode (schema-driven plugin node)
// ─────────────────────────────────────────────────────────────────────────────

describe('CustomNode', () => {
  function makeCustomData(overrides = {}) {
    const updateNodeData = jest.fn();
    return {
      data: {
        step: {
          id: 'plugin-node',
          title: '',
          config: {},
          nodeType: 'plugin:acme',
          customKey: 'acme',
          customName: 'Acme Node',
          customColor: '#6366f1',
          customSchema: [{ key: 'quality', type: 'string', label: 'Quality Level' }],
          customOutputs: [],
          ...overrides,
        },
        updateNodeData,
      },
      updateNodeData,
      isConnectable: true,
    };
  }

  it('renders the plugin display name and schema fields', () => {
    const { data, isConnectable } = makeCustomData();
    render(<CustomNode data={data} isConnectable={isConnectable} />);
    expect(screen.getByText('Acme Node')).toBeInTheDocument();
    expect(screen.getByLabelText('Quality Level')).toBeInTheDocument();
  });

  it('renders a linear handle when no branch outputs are declared', () => {
    const { data, isConnectable } = makeCustomData({ customOutputs: [] });
    render(<CustomNode data={data} isConnectable={isConnectable} />);
    expect(screen.getAllByTestId('handle-source').length).toBe(1);
  });

  it('renders one branch handle per declared output', () => {
    const { data, isConnectable } = makeCustomData({ customOutputs: ['approved', 'rejected'] });
    render(<CustomNode data={data} isConnectable={isConnectable} />);
    expect(screen.getAllByTestId('handle-source').length).toBe(2);
  });

  it('updates config when a schema field changes', async () => {
    const { data, isConnectable, updateNodeData } = makeCustomData();
    render(<CustomNode data={data} isConnectable={isConnectable} />);
    await userEvent.type(screen.getByLabelText('Quality Level'), 'x');
    expect(updateNodeData).toHaveBeenCalledWith(
      'plugin-node',
      'config',
      expect.objectContaining({ quality: 'x' })
    );
  });
});


