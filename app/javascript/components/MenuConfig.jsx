import React from 'react';
import {
    DashboardOutlined,
    PhotoLibraryOutlined,
    AnalyticsOutlined,
    PeopleAltOutlined,
    GroupWorkOutlined,
    SettingsOutlined,
    AccountTree,
    DnsOutlined, EmailOutlined, AssignmentOutlined
} from '@mui/icons-material';

export const MENU_GROUPS = [
    {
        id: 'dashboard',
        title: 'Dashboard',
        items: [
            { id: 'Overview', label: 'Overview', icon: <DashboardOutlined fontSize="small" /> },
            { id: 'All Assets', label: 'All Assets', icon: <PhotoLibraryOutlined fontSize="small" /> },
            { id: 'Workflows', label: 'Workflows', icon: <AccountTree fontSize="small" />, url: '/workflows' },
            { id: 'My Tasks', label: 'My Tasks', icon: <AssignmentOutlined fontSize="small" />, url: '/workflows/dashboard' },
            { id: 'Analytics', label: 'Analytics', icon: <AnalyticsOutlined fontSize="small" /> }
        ]
    },
    {
        id: 'application',
        title: 'Application',
        items: [
            {
                id: 'Users',
                label: 'Users',
                icon: <PeopleAltOutlined fontSize="small" />,
                url: '/admin/users',
            },
            {
                id: 'User Groups',
                label: 'User Groups',
                icon: <GroupWorkOutlined fontSize="small" />,
                url: '/admin/user_groups'
            },
            {
                // Add the new Email Engine routing
                id: 'Email Engine',
                label: 'Email Engine',
                url: '/admin/email_templates',
                icon: <EmailOutlined fontSize="small" />
            }
        ]
    },
    {
        id: 'settings',
        title: 'Settings',
        items: [
            {
                id: 'General',
                label: 'General',
                icon: <SettingsOutlined fontSize="small" />,
                isLink: true,
                url: '/settings'
            },
            {
                id: 'System',
                label: 'System Operations',
                icon: <DnsOutlined fontSize="small" />, // MUI icon for server/infra
                isLink: true,
                url: '/settings/system'
            }
        ]
    }
];