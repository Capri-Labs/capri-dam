import React, { useState, useCallback, useRef, useEffect } from 'react';
import {
    ReactFlow, Background, Controls, MiniMap,
    addEdge, applyNodeChanges, applyEdgeChanges,
    ReactFlowProvider,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import { Box } from '@mui/material';

import NodePalette        from './NodePalette';
import StartNode          from '../nodes/StartNode';
import EndNode            from '../nodes/EndNode';
import ApprovalNode       from '../nodes/ApprovalNode';
import GenericActionNode  from '../nodes/GenericActionNode';
import EmailNode          from '../nodes/EmailNode';
import InAppNotifyNode    from '../nodes/InAppNotifyNode';
import SlackNode          from '../nodes/SlackNode';
import TeamsNode          from '../nodes/TeamsNode';
import SmsNode            from '../nodes/SmsNode';
import WebhookNode        from '../nodes/WebhookNode';
import SecureWebhookNode  from '../nodes/SecureWebhookNode';
import ApiCallNode        from '../nodes/ApiCallNode';
import SetStatusNode      from '../nodes/SetStatusNode';
import AddTagsNode        from '../nodes/AddTagsNode';
import RemoveTagsNode     from '../nodes/RemoveTagsNode';
import MoveAssetNode      from '../nodes/MoveAssetNode';
import CopyAssetNode      from '../nodes/CopyAssetNode';
import ArchiveNode        from '../nodes/ArchiveNode';
import PublishNode        from '../nodes/PublishNode';
import MetadataUpdateNode from '../nodes/MetadataUpdateNode';
import AiMetadataNode     from '../nodes/AiMetadataNode';
import GenerateThumbNode  from '../nodes/GenerateThumbNode';
import CdnSyncNode        from '../nodes/CdnSyncNode';
import DelayNode          from '../nodes/DelayNode';
import ConditionNode      from '../nodes/ConditionNode';

const APPROVAL_TYPES = ['approvalNode', 'parallelApprovalNode', 'sequentialApprovalNode'];
const DEDICATED_TYPES = [
    'emailNode', 'inAppNotifyNode', 'slackNode', 'teamsNode', 'smsNode',
    'webhookNode', 'secureWebhookNode', 'apiCallNode',
    'setStatusNode', 'addTagsNode', 'removeTagsNode',
    'moveAssetNode', 'copyAssetNode', 'archiveNode', 'publishNode', 'metadataUpdateNode',
    'aiMetadataNode', 'generateThumbNode', 'cdnSyncNode',
    'delayNode', 'conditionNode',
];
const ALL_INTERACTIVE = [...APPROVAL_TYPES, ...DEDICATED_TYPES];

// Stable reference — must not be defined inside the component
const nodeTypes = {
    startNode: StartNode,
    endNode: EndNode,
    approvalNode: ApprovalNode,
    parallelApprovalNode: ApprovalNode,
    sequentialApprovalNode: ApprovalNode,
    emailNode: EmailNode,
    inAppNotifyNode: InAppNotifyNode,
    slackNode: SlackNode,
    teamsNode: TeamsNode,
    smsNode: SmsNode,
    webhookNode: WebhookNode,
    secureWebhookNode: SecureWebhookNode,
    apiCallNode: ApiCallNode,
    setStatusNode: SetStatusNode,
    addTagsNode: AddTagsNode,
    removeTagsNode: RemoveTagsNode,
    moveAssetNode: MoveAssetNode,
    copyAssetNode: CopyAssetNode,
    archiveNode: ArchiveNode,
    publishNode: PublishNode,
    metadataUpdateNode: MetadataUpdateNode,
    aiMetadataNode: AiMetadataNode,
    generateThumbNode: GenerateThumbNode,
    cdnSyncNode: CdnSyncNode,
    delayNode: DelayNode,
    conditionNode: ConditionNode,
};

export default function WorkflowCanvas({ nodes, setNodes, edges, setEdges, users = [], groups = [] }) {
    const reactFlowWrapper = useRef(null);
    const [reactFlowInstance, setReactFlowInstance] = useState(null);

    const onNodesChange = useCallback((changes) => setNodes((nds) => applyNodeChanges(changes, nds)), [setNodes]);
    const onEdgesChange = useCallback((changes) => setEdges((eds) => applyEdgeChanges(changes, eds)), [setEdges]);
    const onConnect = useCallback((params) => setEdges((eds) => addEdge({ ...params, animated: true, style: { strokeWidth: 2 } }, eds)), [setEdges]);

    /**
     * updateNodeData – merges config changes without clobbering other keys.
     * When field === 'config', value is shallowly merged into the existing config.
     */
    const updateNodeData = useCallback((nodeId, field, value) => {
        setNodes((nds) =>
            nds.map((node) => {
                if (node.id !== nodeId) return node;
                const prevStep = node.data.step || {};
                const nextStep = field === 'config'
                    ? { ...prevStep, config: { ...(prevStep.config || {}), ...value } }
                    : { ...prevStep, [field]: value };
                return { ...node, data: { ...node.data, step: nextStep } };
            })
        );
    }, [setNodes]);

    // Push shared data to interactive nodes when dependencies change
    useEffect(() => {
        setNodes((nds) => nds.map((node) => {
            if (!ALL_INTERACTIVE.includes(node.type)) return node;
            if (node.data.updateNodeData === updateNodeData &&
                node.data.users === users &&
                node.data.groups === groups) return node;
            return { ...node, data: { ...node.data, updateNodeData, users, groups } };
        }));
    }, [users, groups, updateNodeData, setNodes]);

    const onDragOver = useCallback((event) => {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
    }, []);

    const onDrop = useCallback((event) => {
        event.preventDefault();
        const type = event.dataTransfer.getData('application/reactflow');
        if (!type) return;

        const position = reactFlowInstance.screenToFlowPosition({
            x: event.clientX,
            y: event.clientY,
        });

        const newNodeId = `${type}_${Date.now()}`;
        const isApproval = APPROVAL_TYPES.includes(type);
        const newNode = {
            id: newNodeId,
            type,
            position,
            data: {
                id: newNodeId,
                updateNodeData,
                users,
                groups,
                step: {
                    id: newNodeId,
                    isNew: true,
                    title: '',
                    description: '',
                    assigneeType: 'user',
                    assigneeId: '',
                    fallback_assignee_type: 'user',
                    fallback_assignee_id: '',
                    logic: 'any',
                    deadline_days: 2,
                    nodeType: type,
                    isApproval,
                    config: {},
                }
            }
        };

        setNodes((nds) => nds.concat(newNode));
    }, [reactFlowInstance, setNodes, updateNodeData, users, groups]);

    return (
        <Box sx={{ display: 'flex', width: '100%', height: 750, border: '1px solid #e2e8f0', borderRadius: 2, overflow: 'hidden' }}>
            <NodePalette />
            <Box sx={{ flexGrow: 1, position: 'relative' }} ref={reactFlowWrapper}>
                <ReactFlowProvider>
                    <ReactFlow
                        nodes={nodes}
                        edges={edges}
                        onNodesChange={onNodesChange}
                        onEdgesChange={onEdgesChange}
                        onConnect={onConnect}
                        onInit={setReactFlowInstance}
                        onDrop={onDrop}
                        onDragOver={onDragOver}
                        nodeTypes={nodeTypes}
                        fitView
                    >
                        <Background color="#cbd5e1" gap={16} />
                        <Controls />
                        <MiniMap />
                    </ReactFlow>
                </ReactFlowProvider>
            </Box>
        </Box>
    );
}
