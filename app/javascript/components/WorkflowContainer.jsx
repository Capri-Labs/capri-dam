import React, { useState } from 'react';
import { Box, CssBaseline, Toolbar } from '@mui/material';
import Sidebar from './Sidebar';
import WorkflowList from './Workflows/WorkflowList';
import WorkflowDesigner from './Workflows/WorkflowDesigner';
import {navigateTo} from "../utils/globalutils";

const DEFAULT_PAGINATION = { page: 1, per_page: 25, total: 0, total_pages: 1 };

function parseInitialPagination(raw) {
    if (!raw) return DEFAULT_PAGINATION;
    try {
        return { ...DEFAULT_PAGINATION, ...JSON.parse(raw) };
    } catch {
        return DEFAULT_PAGINATION;
    }
}

export default function WorkflowContainer(props) {
    const [workflowAction, setWorkflowAction] = useState('list'); // 'list', 'create', 'edit'
    const [editingWorkflow, setEditingWorkflow] = useState(null);
    const [activeView, setActiveView] = useState('Workflows');
    const [workflows, setWorkflows] = useState(props.workflows ? JSON.parse(props.workflows) : []);
    const [pagination, setPagination] = useState(parseInitialPagination(props.workflowsPagination));
    const [loading, setLoading] = useState(false);

    const fetchWorkflows = (page) => {
        setLoading(true);
        fetch(`/workflows.json?page=${page}`)
            .then(res => res.json())
            .then(data => {
                setWorkflows(data.workflows || []);
                setPagination(data.pagination || DEFAULT_PAGINATION);
            })
            .catch(err => console.error('Failed to fetch workflows', err))
            .finally(() => setLoading(false));
    };

    const handlePageChange = (page) => {
        fetchWorkflows(page);
    };

    const refreshCurrentPage = () => fetchWorkflows(pagination.page);

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
                workflows={workflows}
                pagination={pagination}
                loading={loading}
                onPageChange={handlePageChange}
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
                onDelete={(id) => { refreshCurrentPage(); }}
            />
        );
    };

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />
            {/* Keep the Sidebar so navigation feels seamless.
                Hardcode activeView to 'Workflows' so the sidebar highlights the correct menu item.
            */}

            <Box component="main" sx={{ flexGrow: 1 }}>
                {renderWorkflowView()}
            </Box>
        </Box>
    );
}