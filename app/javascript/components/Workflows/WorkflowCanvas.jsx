import React, { useState, useCallback, useRef, useEffect } from 'react';
import ReactFlow, {
    Background, Controls, MiniMap, addEdge, applyNodeChanges, applyEdgeChanges, ReactFlowProvider
} from 'reactflow';
import 'reactflow/dist/style.css';
import { Box } from '@mui/material';

import NodePalette from './NodePalette';
import StartNode from '../nodes/StartNode';
import EndNode from '../nodes/EndNode';
import ApprovalNode from '../nodes/ApprovalNode';
import GenericActionNode from '../nodes/GenericActionNode';

// Approval-family node types reuse the ApprovalNode renderer.
const APPROVAL_TYPES = ['approvalNode', 'parallelApprovalNode', 'sequentialApprovalNode'];

// All other action/integration/flow nodes use the GenericActionNode renderer.
const GENERIC_TYPES = [
    'emailNode', 'inAppNotifyNode', 'slackNode', 'teamsNode', 'smsNode',
    'webhookNode', 'secureWebhookNode', 'apiCallNode',
    'setStatusNode', 'addTagsNode', 'removeTagsNode', 'moveAssetNode', 'copyAssetNode',
    'archiveNode', 'publishNode', 'metadataUpdateNode',
    'aiMetadataNode', 'generateThumbNode', 'cdnSyncNode',
    'delayNode', 'conditionNode',
];

const nodeTypes = {
    startNode: StartNode,
    endNode: EndNode,
    approvalNode: ApprovalNode,
    parallelApprovalNode: ApprovalNode,
    sequentialApprovalNode: ApprovalNode,
    // Generic action nodes — bind `type` through so the renderer can look up metadata
    ...GENERIC_TYPES.reduce((acc, t) => {
        acc[t] = (props) => <GenericActionNode {...props} type={t} />;
        return acc;
    }, {}),
};

export default function WorkflowCanvas({ nodes, setNodes, edges, setEdges, users = [], groups = [] }) {
    const reactFlowWrapper = useRef(null);
    const [reactFlowInstance, setReactFlowInstance] = useState(null);

    const onNodesChange = useCallback((changes) => setNodes((nds) => applyNodeChanges(changes, nds)), [setNodes]);
    const onEdgesChange = useCallback((changes) => setEdges((eds) => applyEdgeChanges(changes, eds)), [setEdges]);
    const onConnect = useCallback((params) => setEdges((eds) => addEdge({ ...params, animated: true, style: { strokeWidth: 2 } }, eds)), [setEdges]);

    // Allows the child ApprovalNode to update its specific state without wiping out other nodes.
    const updateNodeData = useCallback((nodeId, field, value) => {
        setNodes((nds) =>
            nds.map((node) => {
                if (node.id === nodeId) {
                    return {
                        ...node,
                        data: {
                            ...node.data,
                            step: { ...node.data.step, [field]: value }
                        }
                    };
                }
                return node;
            })
        );
    }, [setNodes]);

    // Safety Net: Push users, groups, and the update function down to ALL
    // interactive nodes (approval + generic action) when they change.
    useEffect(() => {
        setNodes((nds) => nds.map(node => {
            const interactive = APPROVAL_TYPES.includes(node.type) || GENERIC_TYPES.includes(node.type);
            if (interactive && (!node.data.updateNodeData || node.data.users !== users || node.data.groups !== groups)) {
                return {
                    ...node,
                    data: { ...node.data, updateNodeData, users, groups }
                };
            }
            return node;
        }));
    }, [users, groups, updateNodeData, setNodes]);

    // HTML5 Drag Over Handler
    const onDragOver = useCallback((event) => {
        event.preventDefault();
        event.dataTransfer.dropEffect = 'move';
    }, []);

    // HTML5 Drop Handler
    const onDrop = useCallback(
        (event) => {
            event.preventDefault();

            const type = event.dataTransfer.getData('application/reactflow');
            if (typeof type === 'undefined' || !type) return;

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
                        // approval-specific defaults
                        assigneeType: 'user',
                        assigneeId: '',
                        fallback_assignee_type: 'user',
                        fallback_assignee_id: '',
                        logic: 'any',
                        deadline_days: 2,
                        // node taxonomy + generic action config
                        nodeType: type,
                        isApproval,
                        config: {},
                    }
                }
            };

            setNodes((nds) => nds.concat(newNode));
        },
        [reactFlowInstance, setNodes, updateNodeData, users, groups]
    );

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
