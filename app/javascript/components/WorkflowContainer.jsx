import React, { useState } from 'react';
import { Box, CssBaseline, Toolbar } from '@mui/material';
import Sidebar from './Sidebar';
import WorkflowList from './Workflows/WorkflowList';
import WorkflowDesigner from './Workflows/WorkflowDesigner';
import {navigateTo} from "../utils/globalutils";

export default function WorkflowContainer(props) {
    const [workflowAction, setWorkflowAction] = useState('list'); // 'list', 'create', 'edit'
    const [editingWorkflow, setEditingWorkflow] = useState(null);
    const [activeView, setActiveView] = useState('Workflows');

    const renderWorkflowView = () => {
        if (workflowAction === 'create' || workflowAction === 'edit') {
            return (
                <WorkflowDesigner
                    initialData={editingWorkflow}
                    onCancel={() => { setWorkflowAction('list'); setEditingWorkflow(null); }}
                />
            );
        }

        return (
            <WorkflowList
                workflows={props.workflows ? JSON.parse(props.workflows) : []}
                onCreate={() => setWorkflowAction('create')}
                onEdit={(wf) => {
                    fetch(`/workflows/${wf.id}.json`)
                        .then(res => {
                            if (!res.ok) throw new Error("Network response was not ok");
                            return res.json();
                        })
                        .then(detailedWf => {
                            setEditingWorkflow(detailedWf);
                            setWorkflowAction('edit');
                        })
                        .catch(err => {
                            console.error("Failed to fetch workflow details", err);
                            alert("Could not load workflow details. Check console.");
                        });
                }}
                onDelete={(id) => {/* call delete API */}}
            />
        );
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            {/* Keep the Sidebar so navigation feels seamless.
                Hardcode activeView to 'Workflows' so the sidebar highlights the correct menu item.
            */}
            <Sidebar activeView={activeView} onNavigate={(v) => v === 'Workflows' ? null : navigateTo('/dashboard')} />

            <Box component="main" sx={{ flexGrow: 1 }}>
                {renderWorkflowView()}
            </Box>
        </Box>
    );
}