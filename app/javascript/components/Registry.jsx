import Settings from './Settings';
import SystemAccountShow from "./system_accounts/SystemAccountShow";
import SystemAccountNew from "./system_accounts/SystemAccountNew";
import UserGroupsManager from './Admin/UserGroupsManager';
import UsersManager from './Admin/UsersManager';
import EmailEngineManager from './Admin/EmailEngineManager';
import App from './App';
import AssetExplorer from "./Folders/AssetExplorer";
import WorkflowDashboard from "./WorkflowDashboard";
import WorkflowContainer from "./WorkflowContainer";
import ReportsManager from "./Admin/ReportsManager";
import DashboardManager from "./Dashboard/DashboardManager";
import FoldersManager from "./Folders/FoldersManager";
import BinManager from "./Bin/BinManager";
import DuplicateManager from "./Duplicates/DuplicateManager";
import SearchScreen from "./Search/SearchScreen";
import CollectionsWorkspace from './Collections/index';
import IngestionDashboard from "./Admin/Migrations/IngestionDashboard";
import SystemConnectors from "./Admin/Migrations/SystemConnectors";
import DataHealthDashboard from "./Admin/Migrations/DataHealthDashboard";
import SemanticCopilot from "./Admin/Intelligence/SemanticCopilot";
import AgentWorkflows from "./Admin/Intelligence/AgentWorkflows";
import BatchProcessing from "./Admin/Intelligence/BatchProcessing";
import ProvenanceC2PA from "./Admin/Intelligence/ProvenanceC2PA";
import StyleModelHub from "./Admin/Intelligence/StyleModelHub";
import PromptPlayground from "./Admin/Intelligence/PromptPlayground";
import MetadataSchemasManager from "./Tools/MetadataSchemas";
import MetadataExportManager from "./Tools/MetadataExport";
import MetadataImportManager from "./Tools/MetadataImport";
import AssetConfigurationsManager from "./Tools/AssetConfigurations";
import ProfilePage from "./Profile/ProfilePage";
import InboxPage from "./Inbox/InboxPage";
import QuarantineManager from "./Admin/Quarantine/QuarantineManager";
import CustomNodeManager from "./Admin/CustomNodes/CustomNodeManager";

export const COMPONENT_REGISTRY = {
    'dashboard': DashboardManager,
    'folders': FoldersManager,
    'system_account_show': SystemAccountShow,
    'system_account_new': SystemAccountNew,
    'asset_explorer': AssetExplorer,
    'settings': Settings,
    'user_groups': UserGroupsManager,
    'users': UsersManager,
    'email_engine': EmailEngineManager,
    'app': App,
    'workflows_container': WorkflowContainer,
    'workflow_dashboard': WorkflowDashboard,
    'reports': ReportsManager,
    'bin': BinManager,
    'duplicates': DuplicateManager,
    'SearchScreen': SearchScreen,
    'collectionsView': CollectionsWorkspace,
    'ingestion-dashboard-screen': IngestionDashboard,
    'ingestion-connectors-screen': SystemConnectors,
    'ingestion-data-health-screen': DataHealthDashboard,
    'semantic-copilot-screen': SemanticCopilot,
    'ai-automations-screen': AgentWorkflows,
    'ai-batch-processing-screen': BatchProcessing,
    'ai-provenance-c2pa-screen': ProvenanceC2PA,
    'ai-style-model-hub-screen': StyleModelHub,
    'ai-lab-playground-screen': PromptPlayground,
    'metadata-schemas-screen': MetadataSchemasManager,
    'metadata-exports-screen': MetadataExportManager,
    'metadata-imports-screen': MetadataImportManager,
    'asset-configurations-screen': AssetConfigurationsManager,
    'profile': ProfilePage,
    'inbox': InboxPage,
    'quarantine-manager-screen': QuarantineManager,
    'custom-nodes-screen': CustomNodeManager,
};
