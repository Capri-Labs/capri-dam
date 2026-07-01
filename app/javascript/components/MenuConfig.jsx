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
    BuildOutlined, SchemaOutlined, FileDownloadOutlined, FileUploadOutlined, BlockOutlined, TuneOutlined, Inbox as InboxIcon
} from '@mui/icons-material';

/**
 * MENU_GROUPS — navigation tree for the Sidebar.
 *
 * Each group has a `titleKey` and each item has a `labelKey`.
 * These keys are resolved by react-i18next at render time:
 *
 *   import { useTranslation } from 'react-i18next';
 *   const { t } = useTranslation();
 *   t(item.labelKey, { defaultValue: item.label })
 *
 * The `label` field is kept as the English default so the sidebar still
 * works even if i18n has not been initialised (e.g. in Jest without a
 * provider).
 */
export const MENU_GROUPS = [
    {
        id: 'core',
        title: 'Core Application',
        titleKey: 'menu.group.core',
        items: [
            {
                id: 'Overview',
                label: 'Overview',
                labelKey: 'menu.item.Overview',
                icon: <DashboardOutlined fontSize="small" />,
                url: '/dashboard' },
            {
                id: 'Inbox',
                label: 'Inbox',
                labelKey: 'menu.item.Inbox',
                icon: <InboxIcon fontSize="small" />,
                url: '/inbox' },
            {
                id: 'Search',
                label: 'Advanced Search',
                labelKey: 'menu.item.Search',
                icon: <ManageSearchOutlined fontSize="small" />,
                url: '/search' },
            {
                id: 'Assets',
                label: 'Digital Assets',
                labelKey: 'menu.item.Assets',
                icon: <PhotoLibraryOutlined fontSize="small" />,
                children: [
                    {
                        id: 'All Assets',
                        label: 'All Assets',
                        labelKey: 'menu.item.All Assets',
                        icon: <FolderOpenOutlined fontSize="small" />,
                        url: '/folders' },
                    {
                        id: 'Collections',
                        label: 'Collections',
                        labelKey: 'menu.item.Collections',
                        icon: <CollectionsBookmark fontSize="small" />,
                        url: '/collections' },
                    {
                        id: 'Duplicate Manager',
                        label: 'Duplicate Manager',
                        labelKey: 'menu.item.Duplicate Manager',
                        icon: <ContentCopy fontSize="small" />,
                        url: '/duplicates' },
                    {
                        id: 'Bin',
                        label: 'Recycle Bin',
                        labelKey: 'menu.item.Bin',
                        icon: <DeleteOutlined fontSize="small" />,
                        url: '/bin' }
                ]
            },
        ]
    },
    {
        id: 'artificial_intelligence',
        title: 'Intelligence',
        titleKey: 'menu.group.intelligence',
        items: [
            {
                id: 'Semantic Search',
                label: 'Semantic Copilot',
                labelKey: 'menu.item.Semantic Search',
                icon: <AutoAwesome />,
                url: '/ai/copilot' },
            {
                id: 'Agent Automations',
                label: 'Agent Automations',
                labelKey: 'menu.item.Agent Automations',
                icon: <Route />,
                url: '/ai/agents' },
            {
                id: 'Metadata Extraction',
                label: 'Batch Processing',
                labelKey: 'menu.item.Metadata Extraction',
                icon: <QueryStats />,
                url: '/ai/batch' }
        ]
    },
    {
        id: 'ai_governance_lab',
        title: 'AI Lab & Governance',
        titleKey: 'menu.group.ai_lab',
        items: [
            {
                id: 'Prompt Playground',
                label: 'Prompt Playground',
                labelKey: 'menu.item.Prompt Playground',
                icon: <AutoAwesome />,
                url: '/ai/lab/playground'
            },
            {
                id: 'Content Authenticity',
                label: 'Provenance & C2PA',
                labelKey: 'menu.item.Content Authenticity',
                icon: <HealthAndSafety />,
                url: '/ai/governance/provenance'
            },
            {
                id: 'Brand Synthesis',
                label: 'Style & Model Hub',
                labelKey: 'menu.item.Brand Synthesis',
                icon: <GroupWorkOutlined />,
                url: '/ai/models/hub'
            }
        ]
    },
    {
        id: 'workflows',
        title: 'Workflows & Tasks',
        titleKey: 'menu.group.workflows',
        items: [
            {
                id: 'My Tasks',
                label: 'My Tasks',
                labelKey: 'menu.item.My Tasks',
                icon: <AssignmentOutlined fontSize="small" />,
                url: '/workflows/dashboard' },
            {
                id: 'Workflows',
                label: 'Active Workflows',
                labelKey: 'menu.item.Workflows',
                icon: <AccountTree fontSize="small" />,
                url: '/workflows' }
        ]
    },
    {
        id: 'insights',
        title: 'Insights',
        titleKey: 'menu.group.insights',
        items: [
            {
                id: 'Reports',
                label: 'Reports',
                labelKey: 'menu.item.Reports',
                icon: <AnalyticsOutlined fontSize="small" />,
                url: '/reports' }
        ]
    },
    {
        id: 'tools',
        title: 'Tools',
        titleKey: 'menu.group.tools',
        items: [
            {
                id: 'Tools_Assets',
                label: 'Assets',
                labelKey: 'menu.item.Tools_Assets',
                icon: <BuildOutlined fontSize="small" />,
                children: [
                    {
                        id: 'MetadataSchemas',
                        label: 'Metadata Schemas',
                        labelKey: 'menu.item.MetadataSchemas',
                        icon: <SchemaOutlined fontSize="small" />,
                        url: '/tools/metadata_schemas'
                    },
                    {
                        id: 'MetadataExport',
                        label: 'Metadata Export',
                        labelKey: 'menu.item.MetadataExport',
                        icon: <FileDownloadOutlined fontSize="small" />,
                        url: '/tools/metadata_exports'
                    },
                    {
                        id: 'MetadataImport',
                        label: 'Metadata Import',
                        labelKey: 'menu.item.MetadataImport',
                        icon: <FileUploadOutlined fontSize="small" />,
                        url: '/tools/metadata_imports'
                    },
                    {
                        id: 'AssetConfigurations',
                        label: 'Asset Configurations',
                        labelKey: 'menu.item.AssetConfigurations',
                        icon: <TuneOutlined fontSize="small" />,
                        url: '/tools/asset_configurations'
                    }
                ]
            }
        ]
    },
    {
        id: 'data_and_migrations',
        title: 'Data & Migrations',
        titleKey: 'menu.group.data_migrations',
        items: [
            {
                id: 'Ingestion Engine',
                label: 'Batch Ingestion',
                labelKey: 'menu.item.Ingestion Engine',
                icon: <CloudSync />,
                url: '/admin/migrations/ingestion'
            },
            {
                id: 'Legacy Connectors',
                label: 'Migration & Legacy',
                labelKey: 'menu.item.Legacy Connectors',
                icon: <BackupTable />,
                url: '/admin/migrations/connectors'
            },
            {
                id: 'Data Health',
                label: 'TDM & Storage Health',
                labelKey: 'menu.item.Data Health',
                icon: <HealthAndSafety />,
                url: '/admin/migrations/health'
            }
        ]
    },
    {
        id: 'administration',
        title: 'Administration',
        titleKey: 'menu.group.administration',
        items: [
            {
                id: 'Identity',
                label: 'Access & Identity',
                labelKey: 'menu.item.Identity',
                icon: <PeopleAltOutlined fontSize="small" />,
                children: [
                    {
                        id: 'Users',
                        label: 'Users',
                        labelKey: 'menu.item.Users',
                        icon: <PersonOutlined fontSize="small" />,
                        url: '/admin/users' },
                    {
                        id: 'User Groups',
                        label: 'User Groups',
                        labelKey: 'menu.item.User Groups',
                        icon: <GroupWorkOutlined fontSize="small" />,
                        url: '/admin/user_groups' },
                    {
                        id: 'Policies',
                        label: 'Security Policies',
                        labelKey: 'menu.item.Policies',
                        icon: <SecurityOutlined fontSize="small" />,
                        url: '/admin/policies' }
                ]
            },
            {
                id: 'System',
                label: 'System Settings',
                labelKey: 'menu.item.System',
                icon: <SettingsOutlined fontSize="small" />,
                children: [
                    {
                        id: 'General',
                        label: 'General Settings',
                        labelKey: 'menu.item.General',
                        icon: <SettingsOutlined fontSize="small" />,
                        url: '/settings' },
                    {
                        id: 'Email Engine',
                        label: 'Email Engine',
                        labelKey: 'menu.item.Email Engine',
                        icon: <EmailOutlined fontSize="small" />,
                        url: '/admin/email_templates' },
                    {
                        id: 'System Ops',
                        label: 'System Operations',
                        labelKey: 'menu.item.System Ops',
                        icon: <DnsOutlined fontSize="small" />,
                        url: '/settings/system' },
                    {
                        id: 'Queues',
                        label: 'Sidekiq Queues',
                        labelKey: 'menu.item.Queues',
                        icon: <DnsOutlined />,
                        url: '/admin/queues',
                        external: true
                    }
                ]
            }
        ]
    }
];