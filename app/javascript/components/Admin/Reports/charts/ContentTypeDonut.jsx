import React from 'react';
import { Card, CardContent, Typography, Box, Skeleton } from '@mui/material';
import { PieChart, Pie, Cell, Tooltip, Legend, ResponsiveContainer } from 'recharts';

const PALETTE = ['#5e35b1', '#0ea5e9', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#06b6d4', '#84cc16'];

const CustomTooltip = ({ active, payload }) => {
    if (!active || !payload?.length) return null;
    return (
        <Box sx={{ bgcolor: 'white', p: 1.5, borderRadius: 2, boxShadow: '0 4px 12px rgba(0,0,0,0.1)', border: '1px solid #e2e8f0' }}>
            <Typography variant="caption" sx={{ fontWeight: 700, display: 'block' }}>{payload[0].name}</Typography>
            <Typography variant="caption" color="textSecondary">{payload[0].value.toLocaleString()} assets</Typography>
        </Box>
    );
};

export default function ContentTypeDonut({ data = [], loading = false }) {
    const total = data.reduce((s, d) => s + d.count, 0);
    return (
        <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '100%' }}>
            <CardContent sx={{ p: 2.5 }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 0.5 }}>Asset Type Breakdown</Typography>
                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 1 }}>
                    {total.toLocaleString()} total assets
                </Typography>
                {loading ? (
                    <Skeleton variant="circular" width={180} height={180} sx={{ mx: 'auto', mt: 2 }} />
                ) : data.length === 0 ? (
                    <Typography color="textSecondary" variant="body2" sx={{ mt: 4, textAlign: 'center' }}>No data</Typography>
                ) : (
                    <ResponsiveContainer width="100%" height={220}>
                        <PieChart>
                            <Pie data={data} cx="50%" cy="50%" innerRadius={55} outerRadius={85}
                                dataKey="count" nameKey="type" paddingAngle={2}>
                                {data.map((_, i) => (
                                    <Cell key={i} fill={PALETTE[i % PALETTE.length]} />
                                ))}
                            </Pie>
                            <Tooltip content={<CustomTooltip />} />
                            <Legend formatter={(v) => <span style={{ fontSize: 11, color: '#475569' }}>{v}</span>}
                                iconType="circle" iconSize={8} />
                        </PieChart>
                    </ResponsiveContainer>
                )}
            </CardContent>
        </Card>
    );
}

