import React, { useState, useEffect, useCallback } from 'react';
import { useTranslation } from 'react-i18next';
import {
  Box, Grid, Paper, Typography, Skeleton, Chip, IconButton,
  Button, Tooltip, Alert, AlertTitle, LinearProgress,
  Divider,
} from '@mui/material';
import {
  ImageOutlined, FolderOutlined, PeopleOutlined, TrendingUpOutlined,
  PlayArrowOutlined, StorageOutlined, RefreshOutlined, UploadOutlined,
  SearchOutlined, AutoAwesomeOutlined, WarningAmberOutlined,
  CheckCircleOutlineOutlined, InfoOutlined, OpenInNewOutlined,
  CalendarTodayOutlined, AnalyticsOutlined,
} from '@mui/icons-material';
import {
  AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip as RechartsTooltip,
  ResponsiveContainer, PieChart, Pie, Cell, Legend,
} from 'recharts';
import { navigateTo } from '../../utils/globalutils';

const COLORS = ['#5e35b1', '#00bcd4', '#ff7043', '#43a047', '#ef5350', '#64748b', '#ffa726', '#26c6da'];

const CONTENT_TYPE_ICONS = {
  image: <ImageOutlined sx={{ fontSize: 16 }} />,
  video: <PlayArrowOutlined sx={{ fontSize: 16 }} />,
  audio: <PlayArrowOutlined sx={{ fontSize: 16 }} />,
};

function formatBytes(bytes) {
  if (!bytes) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const exp = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  return `${(bytes / Math.pow(1024, exp)).toFixed(1)} ${units[exp]}`;
}

function KpiCard({ label, value, icon, color, subtitle, onClick, loading }) {
  return (
    <Paper
      elevation={0}
      onClick={onClick}
      sx={{
        p: 2.5,
        border: '1px solid',
        borderColor: 'divider',
        borderRadius: 3,
        cursor: onClick ? 'pointer' : 'default',
        transition: 'box-shadow 0.2s',
        '&:hover': onClick ? { boxShadow: 3 } : {},
        borderLeft: `4px solid ${color}`,
      }}
    >
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <Box>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 0.5 }}>
            {label}
          </Typography>
          {loading ? (
            <Skeleton width={60} height={36} />
          ) : (
            <Typography variant="h4" sx={{ fontWeight: 700, color }}>
              {value}
            </Typography>
          )}
          {subtitle && (
            <Typography variant="caption" color="text.secondary">
              {subtitle}
            </Typography>
          )}
        </Box>
        <Box
          sx={{
            p: 1,
            borderRadius: 2,
            bgcolor: `${color}18`,
            color,
            display: 'flex',
            alignItems: 'center',
          }}
        >
          {icon}
        </Box>
      </Box>
    </Paper>
  );
}

function SectionTitle({ children }) {
  return (
    <Typography variant="h6" sx={{ fontWeight: 700, mb: 2, color: 'text.primary' }}>
      {children}
    </Typography>
  );
}

export default function DashboardManager() {
  const { t } = useTranslation();
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [lastUpdated, setLastUpdated] = useState(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch('/api/v1/dashboard/overview', {
        headers: { Accept: 'application/json' },
        credentials: 'same-origin',
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = await res.json();
      setData(json);
      setLastUpdated(new Date());
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const kpis = data?.kpis || {};
  const assetGrowth = data?.asset_growth || [];
  const assetsByType = data?.assets_by_type || [];
  const storage = data?.storage || {};
  const recentAssets = data?.recent_assets || [];
  const workflowSummary = data?.workflow_summary || {};
  const aiInsights = data?.ai_insights || [];

  return (
    <Box sx={{ bgcolor: '#f8fafc', minHeight: '100vh', p: 0 }}>
      <Box
        sx={{
          background: 'linear-gradient(135deg, #5e35b1 0%, #1565c0 100%)',
          color: 'white',
          px: 4,
          py: 3,
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
        }}
      >
        <Box>
          <Typography variant="h4" sx={{ fontWeight: 800, letterSpacing: -0.5 }}>
            {t('dashboard.title')}
          </Typography>
          <Typography variant="body2" sx={{ opacity: 0.8, mt: 0.5 }}>
            {t('dashboard.subtitle')}
          </Typography>
        </Box>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
          {lastUpdated && (
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.5, opacity: 0.75 }}>
              <CalendarTodayOutlined sx={{ fontSize: 14 }} />
              <Typography variant="caption">
                {t('dashboard.last_updated')}: {lastUpdated.toLocaleTimeString()}
              </Typography>
            </Box>
          )}
          <Tooltip title={t('dashboard.refresh')}>
            <IconButton
              onClick={fetchData}
              disabled={loading}
              sx={{ color: 'white', border: '1px solid rgba(255,255,255,0.3)' }}
            >
              <RefreshOutlined />
            </IconButton>
          </Tooltip>
        </Box>
      </Box>

      <Box sx={{ p: { xs: 2, md: 4 } }}>
        {error && (
          <Alert
            severity="error"
            sx={{ mb: 3 }}
            action={(
              <Button color="inherit" size="small" onClick={fetchData}>
                {t('dashboard.refresh')}
              </Button>
            )}
          >
            {error}
          </Alert>
        )}

        <Grid container spacing={2} sx={{ mb: 4 }}>
          {[
            {
              label: t('dashboard.kpis.total_assets'),
              value: loading ? null : kpis.total_assets ?? 0,
              icon: <ImageOutlined />,
              color: '#5e35b1',
              onClick: () => navigateTo('/assets'),
            },
            {
              label: t('dashboard.kpis.folders'),
              value: loading ? null : kpis.total_folders ?? 0,
              icon: <FolderOutlined />,
              color: '#00bcd4',
              onClick: () => navigateTo('/folders'),
            },
            {
              label: t('dashboard.kpis.users'),
              value: loading ? null : kpis.total_users ?? 0,
              icon: <PeopleOutlined />,
              color: '#43a047',
            },
            {
              label: t('dashboard.kpis.added_this_week'),
              value: loading ? null : kpis.assets_added_7d ?? 0,
              icon: <TrendingUpOutlined />,
              color: '#ff7043',
            },
            {
              label: t('dashboard.kpis.workflow_tasks'),
              value: loading ? null : workflowSummary.total ?? 0,
              icon: <PlayArrowOutlined />,
              color: '#ef5350',
              onClick: () => navigateTo('/workflows'),
            },
            {
              label: t('dashboard.kpis.storage_used'),
              value: loading ? null : (storage.total_human ?? '0 B'),
              icon: <StorageOutlined />,
              color: '#64748b',
            },
          ].map((kpi) => (
            <Grid size={{ xs: 12, sm: 6, md: 4, lg: 2 }} key={kpi.label}>
              <KpiCard {...kpi} loading={loading} />
            </Grid>
          ))}
        </Grid>

        <Grid container spacing={3} sx={{ mb: 4 }}>
          <Grid size={{ xs: 12, md: 7 }}>
            <Paper elevation={0} sx={{ p: 3, border: '1px solid', borderColor: 'divider', borderRadius: 3, height: '100%' }}>
              <SectionTitle>{t('dashboard.charts.asset_growth')}</SectionTitle>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                {t('dashboard.charts.asset_growth_subtitle')}
              </Typography>
              {loading ? (
                <Skeleton variant="rectangular" height={220} sx={{ borderRadius: 2 }} />
              ) : (
                <ResponsiveContainer width="100%" height={220}>
                  <AreaChart data={assetGrowth}>
                    <defs>
                      <linearGradient id="colorAssets" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="5%" stopColor="#5e35b1" stopOpacity={0.3} />
                        <stop offset="95%" stopColor="#5e35b1" stopOpacity={0} />
                      </linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="#f0f0f0" />
                    <XAxis dataKey="month" tick={{ fontSize: 12 }} />
                    <YAxis tick={{ fontSize: 12 }} />
                    <RechartsTooltip />
                    <Area
                      type="monotone"
                      dataKey="count"
                      stroke="#5e35b1"
                      strokeWidth={2}
                      fill="url(#colorAssets)"
                    />
                  </AreaChart>
                </ResponsiveContainer>
              )}
            </Paper>
          </Grid>

          <Grid size={{ xs: 12, md: 5 }}>
            <Paper elevation={0} sx={{ p: 3, border: '1px solid', borderColor: 'divider', borderRadius: 3, height: '100%' }}>
              <SectionTitle>{t('dashboard.charts.by_type')}</SectionTitle>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                {t('dashboard.charts.by_type_subtitle')}
              </Typography>
              {loading ? (
                <Skeleton variant="rectangular" height={220} sx={{ borderRadius: 2 }} />
              ) : assetsByType.length === 0 ? (
                <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: 220 }}>
                  <Typography color="text.secondary">{t('dashboard.recent_assets.empty')}</Typography>
                </Box>
              ) : (
                <ResponsiveContainer width="100%" height={220}>
                  <PieChart>
                    <Pie
                      data={assetsByType}
                      cx="50%"
                      cy="50%"
                      innerRadius={55}
                      outerRadius={85}
                      dataKey="count"
                      nameKey="type"
                    >
                      {assetsByType.map((entry, index) => (
                        <Cell key={entry.type} fill={COLORS[index % COLORS.length]} />
                      ))}
                    </Pie>
                    <Legend />
                    <RechartsTooltip />
                  </PieChart>
                </ResponsiveContainer>
              )}
            </Paper>
          </Grid>
        </Grid>

        <Grid container spacing={3} sx={{ mb: 4 }}>
          <Grid size={{ xs: 12, md: 8 }}>
            <Paper elevation={0} sx={{ p: 3, border: '1px solid', borderColor: 'divider', borderRadius: 3 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
                <AutoAwesomeOutlined sx={{ color: '#5e35b1' }} />
                <SectionTitle>{t('dashboard.insights.title')}</SectionTitle>
              </Box>
              {loading ? (
                [1, 2].map((item) => <Skeleton key={item} height={60} sx={{ mb: 1, borderRadius: 2 }} />)
              ) : aiInsights.length === 0 ? (
                <Alert icon={<CheckCircleOutlineOutlined />} severity="success">
                  {t('dashboard.insights.no_insights')}
                </Alert>
              ) : (
                aiInsights.map((insight) => {
                  const icons = {
                    warning: <WarningAmberOutlined />,
                    info: <InfoOutlined />,
                    success: <CheckCircleOutlineOutlined />,
                  };
                  const actions = {
                    failed_analysis: { label: t('dashboard.insights.failed_analysis_action'), path: '/search' },
                    no_schema: { label: t('dashboard.insights.no_schema_action'), path: '/assets' },
                  };
                  const actionDef = actions[insight.key];
                  return (
                    <Alert
                      key={insight.key}
                      severity={insight.type}
                      icon={icons[insight.type]}
                      sx={{ mb: 1.5, borderRadius: 2 }}
                      action={actionDef ? (
                        <Button
                          size="small"
                          color="inherit"
                          onClick={() => navigateTo(actionDef.path)}
                          endIcon={<OpenInNewOutlined sx={{ fontSize: 14 }} />}
                        >
                          {actionDef.label}
                        </Button>
                      ) : null}
                    >
                      <AlertTitle>
                        {t(`dashboard.insights.${insight.key}`, { count: insight.count })}
                      </AlertTitle>
                    </Alert>
                  );
                })
              )}
            </Paper>
          </Grid>

          <Grid size={{ xs: 12, md: 4 }}>
            <Paper elevation={0} sx={{ p: 3, border: '1px solid', borderColor: 'divider', borderRadius: 3, height: '100%' }}>
              <SectionTitle>{t('dashboard.workflow.title')}</SectionTitle>
              {loading ? (
                [1, 2, 3, 4].map((item) => <Skeleton key={item} height={40} sx={{ mb: 1 }} />)
              ) : (
                <Box>
                  {[
                    { label: t('dashboard.workflow.approved'), value: workflowSummary.approved ?? 0, color: '#43a047' },
                    { label: t('dashboard.workflow.rejected'), value: workflowSummary.rejected ?? 0, color: '#ef5350' },
                    { label: t('dashboard.workflow.canceled'), value: workflowSummary.canceled ?? 0, color: '#64748b' },
                  ].map((item) => (
                    <Box key={item.label} sx={{ mb: 2 }}>
                      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
                        <Typography variant="body2" color="text.secondary">{item.label}</Typography>
                        <Typography variant="body2" sx={{ fontWeight: 600 }}>{item.value}</Typography>
                      </Box>
                      <LinearProgress
                        variant="determinate"
                        value={workflowSummary.total > 0 ? (item.value / workflowSummary.total) * 100 : 0}
                        sx={{
                          height: 6,
                          borderRadius: 3,
                          bgcolor: `${item.color}20`,
                          '& .MuiLinearProgress-bar': { bgcolor: item.color, borderRadius: 3 },
                        }}
                      />
                    </Box>
                  ))}
                  <Divider sx={{ my: 1.5 }} />
                  <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                    <Typography variant="body2" color="text.secondary">{t('dashboard.workflow.total')}</Typography>
                    <Typography variant="body2" sx={{ fontWeight: 700 }}>{workflowSummary.total ?? 0}</Typography>
                  </Box>
                </Box>
              )}
            </Paper>
          </Grid>
        </Grid>

        <Paper elevation={0} sx={{ p: 3, border: '1px solid', borderColor: 'divider', borderRadius: 3, mb: 4 }}>
          <SectionTitle>{t('dashboard.quick_actions.title')}</SectionTitle>
          <Grid container spacing={2}>
            {[
              { label: t('dashboard.quick_actions.upload'), icon: <UploadOutlined />, color: '#5e35b1', path: '/assets' },
              { label: t('dashboard.quick_actions.browse'), icon: <FolderOutlined />, color: '#00bcd4', path: '/folders' },
              { label: t('dashboard.quick_actions.search'), icon: <SearchOutlined />, color: '#ff7043', path: '/search' },
              { label: t('dashboard.quick_actions.workflow'), icon: <PlayArrowOutlined />, color: '#43a047', path: '/workflows' },
              { label: t('dashboard.quick_actions.analytics'), icon: <AnalyticsOutlined />, color: '#64748b', path: '/reports' },
            ].map((action) => (
              <Grid size={{ xs: 6, sm: 4, md: 'auto' }} key={action.label}>
                <Button
                  variant="outlined"
                  startIcon={action.icon}
                  onClick={() => navigateTo(action.path)}
                  sx={{
                    borderRadius: 3,
                    borderColor: action.color,
                    color: action.color,
                    px: 2.5,
                    py: 1,
                    fontWeight: 600,
                    '&:hover': { bgcolor: `${action.color}10`, borderColor: action.color },
                  }}
                >
                  {action.label}
                </Button>
              </Grid>
            ))}
          </Grid>
        </Paper>

        <Paper elevation={0} sx={{ p: 3, border: '1px solid', borderColor: 'divider', borderRadius: 3 }}>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
            <SectionTitle>{t('dashboard.recent_assets.title')}</SectionTitle>
            <Button
              size="small"
              endIcon={<OpenInNewOutlined sx={{ fontSize: 14 }} />}
              onClick={() => navigateTo('/assets')}
            >
              {t('dashboard.recent_assets.view_all')}
            </Button>
          </Box>
          {loading ? (
            [1, 2, 3, 4, 5].map((item) => <Skeleton key={item} height={52} sx={{ mb: 1, borderRadius: 1 }} />)
          ) : recentAssets.length === 0 ? (
            <Typography color="text.secondary">{t('dashboard.recent_assets.empty')}</Typography>
          ) : (
            recentAssets.map((asset) => {
              const typeKey = (asset.content_type || '').split('/')[0];
              const typeIcon = CONTENT_TYPE_ICONS[typeKey] || <ImageOutlined sx={{ fontSize: 16 }} />;
              const statusColors = { published: 'success', draft: 'default', approved: 'primary' };
              return (
                <Box
                  key={asset.id}
                  sx={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 2,
                    py: 1.5,
                    px: 2,
                    borderRadius: 2,
                    '&:hover': { bgcolor: 'action.hover' },
                  }}
                >
                  <Box sx={{ color: '#5e35b1' }}>{typeIcon}</Box>
                  <Box sx={{ flex: 1, minWidth: 0 }}>
                    <Typography variant="body2" sx={{ fontWeight: 600 }} noWrap>
                      {asset.title}
                    </Typography>
                    <Typography variant="caption" color="text.secondary">
                      {formatBytes(asset.file_size)} · {new Date(asset.created_at).toLocaleDateString()}
                    </Typography>
                  </Box>
                  <Chip
                    label={asset.status}
                    size="small"
                    color={statusColors[asset.status] || 'default'}
                    sx={{ textTransform: 'capitalize' }}
                  />
                  <Button
                    size="small"
                    variant="outlined"
                    onClick={() => navigateTo(`/assets?id=${asset.uuid}`)}
                    sx={{ borderRadius: 2, minWidth: 'auto', px: 1.5 }}
                  >
                    {t('dashboard.recent_assets.view')}
                  </Button>
                </Box>
              );
            })
          )}
        </Paper>
      </Box>
    </Box>
  );
}
