import React from 'react';
import { render, screen } from '@testing-library/react';

jest.mock('../../../app/javascript/components/Settings', () => () => <div>Settings</div>);
jest.mock('../../../app/javascript/components/system_accounts/SystemAccountShow', () => () => <div>SystemAccountShow</div>);
jest.mock('../../../app/javascript/components/system_accounts/SystemAccountNew', () => () => <div>SystemAccountNew</div>);
jest.mock('../../../app/javascript/components/Admin/UserGroupsManager', () => () => <div>UserGroupsManager</div>);
jest.mock('../../../app/javascript/components/Admin/UsersManager', () => () => <div>UsersManager</div>);
jest.mock('../../../app/javascript/components/Admin/EmailEngineManager', () => () => <div>EmailEngineManager</div>);
jest.mock('../../../app/javascript/components/App', () => () => <div>App</div>);
jest.mock('../../../app/javascript/components/Folders/AssetExplorer', () => () => <div>AssetExplorer</div>);
jest.mock('../../../app/javascript/components/WorkflowDashboard', () => () => <div>WorkflowDashboard</div>);
jest.mock('../../../app/javascript/components/WorkflowContainer', () => () => <div>WorkflowContainer</div>);
jest.mock('../../../app/javascript/components/Admin/ReportsManager', () => () => <div>ReportsManager</div>);
jest.mock('../../../app/javascript/components/Dashboard/DashboardManager', () => () => <div>DashboardManager</div>);
jest.mock('../../../app/javascript/components/Folders/FoldersManager', () => () => <div>FoldersManager</div>);
jest.mock('../../../app/javascript/components/Bin/BinManager', () => () => <div>BinManager</div>);
jest.mock('../../../app/javascript/components/Duplicates/DuplicateManager', () => () => <div>DuplicateManager</div>);
jest.mock('../../../app/javascript/components/Search/SearchScreen', () => () => <div>SearchScreen</div>);
jest.mock('../../../app/javascript/components/Collections/index', () => () => <div>CollectionsWorkspace</div>);
jest.mock('../../../app/javascript/components/Admin/Migrations/IngestionDashboard', () => () => <div>IngestionDashboard</div>);
jest.mock('../../../app/javascript/components/Admin/Migrations/SystemConnectors', () => () => <div>SystemConnectors</div>);
jest.mock('../../../app/javascript/components/Admin/Migrations/DataHealthDashboard', () => () => <div>DataHealthDashboard</div>);
jest.mock('../../../app/javascript/components/Admin/Intelligence/SemanticCopilot', () => () => <div>SemanticCopilot</div>);
jest.mock('../../../app/javascript/components/Admin/Intelligence/AgentWorkflows', () => () => <div>AgentWorkflows</div>);
jest.mock('../../../app/javascript/components/Admin/Intelligence/BatchProcessing', () => () => <div>BatchProcessing</div>);
jest.mock('../../../app/javascript/components/Admin/Intelligence/ProvenanceC2PA', () => () => <div>ProvenanceC2PA</div>);
jest.mock('../../../app/javascript/components/Admin/Intelligence/StyleModelHub', () => () => <div>StyleModelHub</div>);
jest.mock('../../../app/javascript/components/Admin/Intelligence/PromptPlayground', () => () => <div>PromptPlayground</div>);
jest.mock('../../../app/javascript/components/Tools/MetadataSchemas', () => () => <div>MetadataSchemasManager</div>);
jest.mock('../../../app/javascript/components/Tools/MetadataExport', () => () => <div>MetadataExportManager</div>);
jest.mock('../../../app/javascript/components/Tools/MetadataImport', () => () => <div>MetadataImportManager</div>);
jest.mock('../../../app/javascript/components/Tools/AssetConfigurations', () => () => <div>AssetConfigurationsManager</div>);
jest.mock('../../../app/javascript/components/Profile/ProfilePage', () => () => <div>ProfilePage</div>);
jest.mock('../../../app/javascript/components/Inbox/InboxPage', () => () => <div>InboxPage</div>);
jest.mock('../../../app/javascript/components/Admin/Quarantine/QuarantineManager', () => () => <div>QuarantineManager</div>);

import { COMPONENT_REGISTRY } from '../../../app/javascript/components/Registry';

describe('COMPONENT_REGISTRY', () => {
  it('contains all expected registry entries', () => {
    expect(Object.keys(COMPONENT_REGISTRY)).toEqual(expect.arrayContaining([
      'dashboard',
      'folders',
      'system_account_show',
      'system_account_new',
      'asset_explorer',
      'settings',
      'user_groups',
      'users',
      'email_engine',
      'app',
      'workflows_container',
      'workflow_dashboard',
      'reports',
      'bin',
      'duplicates',
      'SearchScreen',
      'collectionsView',
      'ingestion-dashboard-screen',
      'ingestion-connectors-screen',
      'ingestion-data-health-screen',
      'semantic-copilot-screen',
      'ai-automations-screen',
      'ai-batch-processing-screen',
      'ai-provenance-c2pa-screen',
      'ai-style-model-hub-screen',
      'ai-lab-playground-screen',
      'metadata-schemas-screen',
      'metadata-exports-screen',
      'metadata-imports-screen',
      'asset-configurations-screen',
      'profile',
      'inbox',
      'quarantine-manager-screen',
    ]));
  });

  it('renders components for every registered key', () => {
    const expectedText = {
      dashboard: 'DashboardManager',
      folders: 'FoldersManager',
      system_account_show: 'SystemAccountShow',
      system_account_new: 'SystemAccountNew',
      asset_explorer: 'AssetExplorer',
      settings: 'Settings',
      user_groups: 'UserGroupsManager',
      users: 'UsersManager',
      email_engine: 'EmailEngineManager',
      app: 'App',
      workflows_container: 'WorkflowContainer',
      workflow_dashboard: 'WorkflowDashboard',
      reports: 'ReportsManager',
      bin: 'BinManager',
      duplicates: 'DuplicateManager',
      SearchScreen: 'SearchScreen',
      collectionsView: 'CollectionsWorkspace',
      'ingestion-dashboard-screen': 'IngestionDashboard',
      'ingestion-connectors-screen': 'SystemConnectors',
      'ingestion-data-health-screen': 'DataHealthDashboard',
      'semantic-copilot-screen': 'SemanticCopilot',
      'ai-automations-screen': 'AgentWorkflows',
      'ai-batch-processing-screen': 'BatchProcessing',
      'ai-provenance-c2pa-screen': 'ProvenanceC2PA',
      'ai-style-model-hub-screen': 'StyleModelHub',
      'ai-lab-playground-screen': 'PromptPlayground',
      'metadata-schemas-screen': 'MetadataSchemasManager',
      'metadata-exports-screen': 'MetadataExportManager',
      'metadata-imports-screen': 'MetadataImportManager',
      'asset-configurations-screen': 'AssetConfigurationsManager',
      profile: 'ProfilePage',
      inbox: 'InboxPage',
      'quarantine-manager-screen': 'QuarantineManager',
    };

    Object.entries(COMPONENT_REGISTRY).forEach(([key, Component]) => {
      const { unmount } = render(<Component />);
      expect(screen.getByText(expectedText[key])).toBeInTheDocument();
      unmount();
    });
  });
});
