import React from 'react';
import {
    DashboardOutlined,
    PhotoLibraryOutlined,
    AnalyticsOutlined,
    PeopleAltOutlined,
    SettingsOutlined,
    AccountTree,
    AssignmentOutlined,
    FolderOpenOutlined,
    DeleteOutlined,
    DnsOutlined,
    EmailOutlined,
    GroupWorkOutlined,
    PersonOutlined,
    SecurityOutlined, ContentCopy,
    ManageSearchOutlined, CollectionsBookmark, AutoAwesome, Route, QueryStats, CloudSync, BackupTable, HealthAndSafety,
    BuildOutlined, SchemaOutlined, FileDownloadOutlined
} from '@mui/icons-material';

export const MENU_GROUPS = [
    {
        id: 'core',
        title: 'Core Application',
        items: [
            {
                id: 'Overview',
                label: 'Overview',
                icon: <DashboardOutlined fontSize="small" />,
                url: '/dashboard' },
            {
                id: 'Search',
                label: 'Advanced Search',
                icon: <ManageSearchOutlined fontSize="small" />,
                url: '/search' },
            {
                id: 'Assets',
                label: 'Digital Assets',
                icon: <PhotoLibraryOutlined fontSize="small" />,
                children: [
                    {
                        id: 'All Assets',
                        label: 'All Assets',
                        icon: <FolderOpenOutlined fontSize="small" />,
                        url: '/folders' },
                    {
                        id: 'Collections',
                        label: 'Collections',
                        icon: <CollectionsBookmark fontSize="small" />,
                        url: '/collections' },
                    {
                        id: 'Duplicate Manager',
                        label: 'Duplicate Manager',
                        icon: <ContentCopy fontSize="small" />,
                        url: '/duplicates' },
                    {
                        id: 'Bin',
                        label: 'Recycle Bin',
                        icon: <DeleteOutlined fontSize="small" />,
                        url: '/bin' }
                ]
            },
        ]
    },
    {
        id: 'artificial_intelligence',
        title: 'Intelligence',
        items: [
            {
                id: 'Semantic Search',
                label: 'Semantic Copilot',
                icon: <AutoAwesome />,
                url: '/ai/copilot' },
            {
                id: 'Agent Automations',
                label: 'Agent Automations',
                icon: <Route />,
                url: '/ai/agents' },
            {
                id: 'Metadata Extraction',
                label: 'Batch Processing',
                icon: <QueryStats />,
                url: '/ai/batch' }
        ]
    },
    {
        id: 'ai_governance_lab',
        title: 'AI Lab & Governance',
        items: [
            {
                id: 'Prompt Playground',
                label: 'Prompt Playground',
                icon: <AutoAwesome />,
                url: '/ai/lab/playground'
            },
            {
                id: 'Content Authenticity',
                label: 'Provenance & C2PA',
                icon: <HealthAndSafety />,
                url: '/ai/governance/provenance'
            },
            {
                id: 'Brand Synthesis',
                label: 'Style & Model Hub',
                icon: <GroupWorkOutlined />,
                url: '/ai/models/hub'
            }
        ]
    },
    {
        id: 'workflows',
        title: 'Workflows & Tasks',
        items: [
            {
                id: 'My Tasks',
                label: 'My Tasks',
                icon: <AssignmentOutlined fontSize="small" />,
                url: '/workflows/dashboard' },
            {
                id: 'Workflows',
                label: 'Active Workflows',
                icon: <AccountTree fontSize="small" />,
                url: '/workflows' }
        ]
    },
    {
        id: 'insights',
        title: 'Insights',
        items: [
            {
                id: 'Reports',
                label: 'Reports',
                icon: <AnalyticsOutlined fontSize="small" />,
                url: '/reports' }
        ]
    },
    {
        id: 'tools',
        title: 'Tools',
        items: [
            {
                id: 'Tools_Assets',
                label: 'Assets',
                icon: <BuildOutlined fontSize="small" />,
                children: [
                    {
                        id: 'MetadataSchemas',
                        label: 'Metadata Schemas',
                        icon: <SchemaOutlined fontSize="small" />,
                        url: '/tools/metadata_schemas'
                    },
                    {
                        id: 'MetadataExport',
                        label: 'Metadata Export',
                        icon: <FileDownloadOutlined fontSize="small" />,
                        url: '/tools/metadata_exports'
                    }
                ]
            }
        ]
    },
    {
        id: 'data_and_migrations',
        title: 'Data & Migrations',
        items: [
            {
                id: 'Ingestion Engine',
                label: 'Batch Ingestion',
                icon: <CloudSync />,
                url: '/admin/migrations/ingestion'
            },
            {
                id: 'Legacy Connectors',
                label: 'Migration & Legacy',
                icon: <BackupTable />,
                url: '/admin/migrations/connectors'
            },
            {
                id: 'Data Health',
                label: 'TDM & Storage Health',
                icon: <HealthAndSafety />,
                url: '/admin/migrations/health'
            }
        ]
    },
    {
        id: 'administration',
        title: 'Administration',
        items: [
            {
                id: 'Identity',
                label: 'Access & Identity',
                icon: <PeopleAltOutlined fontSize="small" />,
                children: [
                    {
                        id: 'Users',
                        label: 'Users',
                        icon: <PersonOutlined fontSize="small" />,
                        url: '/admin/users' },
                    {
                        id: 'User Groups',
                        label: 'User Groups',
                        icon: <GroupWorkOutlined fontSize="small" />,
                        url: '/admin/user_groups' },
                    {
                        id: 'Policies',
                        label: 'Security Policies',
                        icon: <SecurityOutlined fontSize="small" />,
                        url: '/admin/policies' }
                ]
            },
            {
                id: 'System',
                label: 'System Settings',
                icon: <SettingsOutlined fontSize="small" />,
                children: [
                    {
                        id: 'General',
                        label: 'General Settings',
                        icon: <SettingsOutlined fontSize="small" />,
                        url: '/settings' },
                    {
                        id: 'Email Engine',
                        label: 'Email Engine',
                        icon: <EmailOutlined fontSize="small" />,
                        url: '/admin/email_templates' },
                    {
                        id: 'System Ops',
                        label: 'System Operations',
                        icon: <DnsOutlined fontSize="small" />,
                        url: '/settings/system' },
                    {
                        id: 'Queues',
                        label: 'Sidekiq Queues',
                        icon: <DnsOutlined />,
                        url: '/admin/queues',
                        external: true
                    }
                ]
            }
        ]
    }
];