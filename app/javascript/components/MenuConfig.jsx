import React from 'react';
import {
    DashboardOutlined,
    PhotoLibraryOutlined,
    AnalyticsOutlined,
    PeopleAltOutlined,
    GroupWorkOutlined,
    SettingsOutlined
} from '@mui/icons-material';

export const MENU_GROUPS = [
    {
        id: 'dashboard',
        title: 'Dashboard',
        items: [
            { id: 'Overview', label: 'Overview', icon: <DashboardOutlined fontSize="small" /> },
            { id: 'All Assets', label: 'All Assets', icon: <PhotoLibraryOutlined fontSize="small" /> },
            { id: 'Analytics', label: 'Analytics', icon: <AnalyticsOutlined fontSize="small" /> }
        ]
    },
    {
        id: 'application',
        title: 'Application',
        items: [
            { id: 'Users', label: 'Users', icon: <PeopleAltOutlined fontSize="small" /> },
            { id: 'User Groups', label: 'User Groups', icon: <GroupWorkOutlined fontSize="small" /> },
            { id: 'Settings', label: 'Settings', icon: <SettingsOutlined fontSize="small" />, isLink: true, url: '/settings' }
        ]
    }
];