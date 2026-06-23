import React from 'react';
import { Card, CardContent, Typography, Box, Skeleton } from '@mui/material';
import { TrendingUp, TrendingDown } from '@mui/icons-material';

export default function StatCard({
    label, value, icon, color = '#5e35b1', loading = false,
    trend = null,      // { value: '+12%', direction: 'up' | 'down' | 'neutral' }
    sub = null,        // secondary line below value
    onClick = null
}) {
    return (
        <Card
            elevation={0}
            onClick={onClick}
            sx={{
                border: '1px solid #e3e8ef', borderRadius: 3,
                cursor: onClick ? 'pointer' : 'default',
                transition: 'box-shadow 0.15s',
                '&:hover': onClick ? { boxShadow: '0 4px 12px rgba(0,0,0,0.08)', borderColor: color } : {}
            }}
        >
            <CardContent sx={{ p: 2.5, '&:last-child': { pb: 2.5 } }}>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                    <Box sx={{ flex: 1 }}>
                        <Typography variant="caption" sx={{ fontWeight: 700, color: '#64748b', textTransform: 'uppercase', letterSpacing: '0.06em' }}>
                            {label}
                        </Typography>
                        {loading ? (
                            <Skeleton variant="text" width={80} height={44} sx={{ mt: 0.5 }} />
                        ) : (
                            <Typography variant="h4" sx={{ fontWeight: 700, mt: 0.5, color: '#0f172a', lineHeight: 1.2 }}>
                                {value ?? '—'}
                            </Typography>
                        )}
                        {sub && !loading && (
                            <Typography variant="caption" color="textSecondary" sx={{ display: 'block', mt: 0.5 }}>
                                {sub}
                            </Typography>
                        )}
                    </Box>
                    {icon && (
                        <Box sx={{ p: 1.2, bgcolor: `${color}18`, borderRadius: 2, display: 'flex', ml: 1 }}>
                            {React.cloneElement(icon, { sx: { color, fontSize: 26 } })}
                        </Box>
                    )}
                </Box>
                {trend && !loading && (
                    <Box sx={{ mt: 1.5, display: 'flex', alignItems: 'center', gap: 0.5 }}>
                        {trend.direction === 'up'   && <TrendingUp  fontSize="small" sx={{ color: '#16a34a' }} />}
                        {trend.direction === 'down' && <TrendingDown fontSize="small" sx={{ color: '#dc2626' }} />}
                        <Typography variant="caption" sx={{
                            fontWeight: 600,
                            color: trend.direction === 'up' ? '#16a34a' : trend.direction === 'down' ? '#dc2626' : '#64748b'
                        }}>
                            {trend.value}
                        </Typography>
                        {trend.label && (
                            <Typography variant="caption" color="textSecondary">&nbsp;{trend.label}</Typography>
                        )}
                    </Box>
                )}
            </CardContent>
        </Card>
    );
}

