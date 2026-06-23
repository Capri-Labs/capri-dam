import React from 'react';
import { Card, CardContent, Typography, Box, Skeleton } from '@mui/material';
import {
    XAxis, YAxis, CartesianGrid, Tooltip, Legend,
    ResponsiveContainer, Area, AreaChart
} from 'recharts';

const CustomTooltip = ({ active, payload, label }) => {
    if (!active || !payload?.length) return null;
    return (
        <Box sx={{ bgcolor: 'white', p: 1.5, borderRadius: 2, boxShadow: '0 4px 12px rgba(0,0,0,0.1)', border: '1px solid #e2e8f0' }}>
            <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748b', display: 'block', mb: 0.5 }}>{label}</Typography>
            {payload.map((p, i) => (
                <Typography key={i} variant="caption" sx={{ display: 'block', color: p.color, fontWeight: 600 }}>
                    {p.name}: {p.value.toLocaleString()}
                </Typography>
            ))}
        </Box>
    );
};

export default function AssetTrendChart({ data = [], loading = false }) {
    return (
        <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '100%' }}>
            <CardContent sx={{ p: 2.5 }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 0.5 }}>Asset Activity Trend</Typography>
                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 2 }}>
                    Daily uploads and workflow completions
                </Typography>
                {loading ? (
                    <Skeleton variant="rectangular" height={240} sx={{ borderRadius: 2 }} />
                ) : (
                    <ResponsiveContainer width="100%" height={240}>
                        <AreaChart data={data} margin={{ top: 5, right: 10, left: -20, bottom: 0 }}>
                            <defs>
                                <linearGradient id="gradAssets" x1="0" y1="0" x2="0" y2="1">
                                    <stop offset="5%" stopColor="#5e35b1" stopOpacity={0.15} />
                                    <stop offset="95%" stopColor="#5e35b1" stopOpacity={0} />
                                </linearGradient>
                                <linearGradient id="gradWorkflows" x1="0" y1="0" x2="0" y2="1">
                                    <stop offset="5%" stopColor="#0ea5e9" stopOpacity={0.12} />
                                    <stop offset="95%" stopColor="#0ea5e9" stopOpacity={0} />
                                </linearGradient>
                            </defs>
                            <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#f1f5f9" />
                            <XAxis dataKey="date" tick={{ fontSize: 11, fill: '#94a3b8' }} axisLine={false} tickLine={false}
                                tickFormatter={(v) => v?.slice(5)} />
                            <YAxis tick={{ fontSize: 11, fill: '#94a3b8' }} axisLine={false} tickLine={false} />
                            <Tooltip content={<CustomTooltip />} />
                            <Legend wrapperStyle={{ fontSize: 12, paddingTop: 8 }} />
                            <Area type="monotone" dataKey="assets" name="Assets Uploaded" stroke="#5e35b1" strokeWidth={2}
                                fill="url(#gradAssets)" dot={false} activeDot={{ r: 4 }} />
                            <Area type="monotone" dataKey="workflows" name="Workflows Completed" stroke="#0ea5e9" strokeWidth={2}
                                fill="url(#gradWorkflows)" dot={false} activeDot={{ r: 4 }} />
                        </AreaChart>
                    </ResponsiveContainer>
                )}
            </CardContent>
        </Card>
    );
}

