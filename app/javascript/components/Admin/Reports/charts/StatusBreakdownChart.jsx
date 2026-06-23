import React from 'react';
import { Card, CardContent, Typography, Box, Skeleton } from '@mui/material';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, Cell, ResponsiveContainer, LabelList } from 'recharts';

const STATUS_COLORS = {
    'Ready':     '#16a34a',
    'Approved':  '#0ea5e9',
    'Pending':   '#f59e0b',
    'In Review': '#8b5cf6',
    'Rejected':  '#ef4444',
    'Draft':     '#94a3b8',
    'Processing': '#06b6d4',
    'Failed':    '#dc2626',
};

export default function StatusBreakdownChart({ data = [], loading = false }) {
    return (
        <Card elevation={0} sx={{ border: '1px solid #e3e8ef', borderRadius: 3, height: '100%' }}>
            <CardContent sx={{ p: 2.5 }}>
                <Typography variant="subtitle1" sx={{ fontWeight: 700, mb: 0.5 }}>Status Distribution</Typography>
                <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mb: 2 }}>
                    Assets by lifecycle state
                </Typography>
                {loading ? (
                    <Skeleton variant="rectangular" height={200} sx={{ borderRadius: 2 }} />
                ) : (
                    <ResponsiveContainer width="100%" height={200}>
                        <BarChart data={data} layout="vertical" margin={{ top: 0, right: 30, left: 10, bottom: 0 }}>
                            <CartesianGrid strokeDasharray="3 3" horizontal={false} stroke="#f1f5f9" />
                            <XAxis type="number" tick={{ fontSize: 11, fill: '#94a3b8' }} axisLine={false} tickLine={false} />
                            <YAxis type="category" dataKey="status" tick={{ fontSize: 11, fill: '#475569' }} axisLine={false} tickLine={false} width={72} />
                            <Tooltip
                                formatter={(v) => [v.toLocaleString(), 'Assets']}
                                contentStyle={{ borderRadius: 8, border: 'none', boxShadow: '0 4px 12px rgba(0,0,0,0.1)' }}
                            />
                            <Bar dataKey="count" radius={[0, 4, 4, 0]} maxBarSize={18}>
                                {data.map((entry, i) => (
                                    <Cell key={i} fill={STATUS_COLORS[entry.status] || '#5e35b1'} />
                                ))}
                                <LabelList dataKey="count" position="right" style={{ fontSize: 11, fill: '#64748b', fontWeight: 600 }} />
                            </Bar>
                        </BarChart>
                    </ResponsiveContainer>
                )}
            </CardContent>
        </Card>
    );
}

