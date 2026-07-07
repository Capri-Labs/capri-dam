import React, { useState } from 'react';
import { Box, Typography, Tab, Tabs, CssBaseline } from '@mui/material';
import {Dns, Email, BugReport, ToggleOn, SmartToy, CloudQueue, History} from '@mui/icons-material';

// Import our new sub-components
import ObservabilityTab from './ObservabilityTab';
import SmtpSettingsTab from './SmtpSettingsTab';
import OperationalLoggingTab from './OperationalLoggingTab';
import AiGatewayTab from './AiGatewayTab';
import FeatureFlagsTab from './FeatureFlagsTab';
import StorageOperationsTab from './StorageOperationsTab';
import AuditLogTab from './AuditLogTab';

export default function SystemStatus({ incomingConfigs }) {
    const [currentTab, setCurrentTab] = useState(0);
    const [activeView] = useState('System');

    return (
        <Box sx={{ display: 'flex', bgcolor: '#f4f7fb', minHeight: '100vh' }}>
            <CssBaseline />

            <Box component="main" sx={{ flexGrow: 1, p: 4 }}>
                <Box sx={{ width: '100%', p: 1, mb: 2 }}>
                    <Typography variant="h4" sx={{ fontWeight: 700, color: '#121926' }}>System Operations</Typography>
                    <Typography variant="body2" color="textSecondary">Manage email routing credentials, monitor system runtime vitals, and configure logging.</Typography>
                </Box>

                <Tabs value={currentTab} onChange={(e, val) => setCurrentTab(val)} sx={{ mb: 4 }}>
                    <Tab label="System Observability" icon={<Dns />} iconPosition="start" />
                    <Tab label="SMTP & Email Settings" icon={<Email />} iconPosition="start" />
                    <Tab label="Operational Logging" icon={<BugReport />} iconPosition="start" />
                    <Tab label="AI Gateway Controls" icon={<SmartToy />} iconPosition="start" />
                    <Tab label="Feature Flags" icon={<ToggleOn />} iconPosition="start" />
                    <Tab label="Storage & Edge" icon={<CloudQueue />} iconPosition="start" />
                    <Tab label="Audit Trail" icon={<History />} iconPosition="start" />
                </Tabs>

                {/* Render only the active tab component */}
                {currentTab === 0 && <ObservabilityTab />}
                {currentTab === 1 && <SmtpSettingsTab incomingConfigs={incomingConfigs} />}
                {currentTab === 2 && <OperationalLoggingTab/>}
                {currentTab === 3 && <AiGatewayTab />}
                {currentTab === 4 && <FeatureFlagsTab />}
                {currentTab === 5 && <StorageOperationsTab />}
                {currentTab === 6 && <AuditLogTab />}
            </Box>
        </Box>
    );
}