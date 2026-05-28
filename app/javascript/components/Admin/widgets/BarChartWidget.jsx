import React from 'react';
import { Card, CardContent, Typography, Box } from '@mui/material';
import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts';

export default function BarChartWidget({ title, data, dataKeyX, dataBars, height = 300 }) {
    return (
        <Card variant="outlined" sx={{ borderRadius: 2, height: '100%', bgcolor: 'white' }}>
            <CardContent>
                <Typography variant="h6" sx={{ mb: 2, fontWeight: 600 }}>{title}</Typography>
                <Box sx={{ width: '100%', height: height }}>
                    <ResponsiveContainer>
                        <BarChart data={data} margin={{ top: 5, right: 20, left: -20, bottom: 5 }}>
                            <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#e2e8f0" />
                            <XAxis dataKey={dataKeyX} tick={{ fontSize: 12, fill: '#64748b' }} axisLine={false} tickLine={false} />
                            <YAxis tick={{ fontSize: 12, fill: '#64748b' }} axisLine={false} tickLine={false} />
                            <Tooltip
                                contentStyle={{ borderRadius: '8px', border: 'none', boxShadow: '0 4px 6px -1px rgb(0 0 0 / 0.1)' }}
                                cursor={{ fill: '#f1f5f9' }}
                            />
                            <Legend wrapperStyle={{ fontSize: '12px' }} />
                            {dataBars.map((bar) => (
                                <Bar key={bar.key} dataKey={bar.key} name={bar.name} fill={bar.color} radius={[4, 4, 0, 0]} />
                            ))}
                        </BarChart>
                    </ResponsiveContainer>
                </Box>
            </CardContent>
        </Card>
    );
}