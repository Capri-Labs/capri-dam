import React from 'react';
import { Card, CardContent, Typography, Skeleton } from '@mui/material';
import { FunnelChart, Funnel, Tooltip, LabelList, Cell, ResponsiveContainer } from 'recharts';

// Recharts FunnelChart for workflow stages
const STAGE_COLORS = ['#5e35b1', '#0ea5e9', '#16a34a', '#ef4444'];

export default function WorkflowFunnelChart({ data = [], loading = false }) {
    return (
        <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '100%' }}>
            <CardContent sx={{ p: 2.5 }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 0.5 }}>Workflow Funnel</Typography>
                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 2 }}>
                    Asset journey through approval stages
                </Typography>
                {loading ? (
                    <Skeleton variant="rectangular" height={220} sx={{ borderRadius: 2 }} />
                ) : data.length === 0 ? (
                    <Typography color="textSecondary" variant="body2" sx={{ mt: 4, textAlign: 'center' }}>No workflow data</Typography>
                ) : (
                    <ResponsiveContainer width="100%" height={220}>
                        <FunnelChart>
                            <Tooltip
                                formatter={(v) => [v.toLocaleString(), 'Assets']}
                                contentStyle={{ borderRadius: 8, border: 'none', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}
                            />
                            <Funnel dataKey="count" data={data} isAnimationActive>
                                {data.map((_, i) => (
                                    <Cell key={i} fill={STAGE_COLORS[i % STAGE_COLORS.length]} />
                                ))}
                                <LabelList
                                    position="right"
                                    fill="#475569"
                                    stroke="none"
                                    dataKey="stage"
                                    style={{ fontSize: 12, fontWeight: 600 }}
                                />
                            </Funnel>
                        </FunnelChart>
                    </ResponsiveContainer>
                )}
            </CardContent>
        </Card>
    );
}

