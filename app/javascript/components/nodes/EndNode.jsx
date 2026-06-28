import React from 'react';
import { Handle, Position } from '@xyflow/react';
import { Box, Typography } from '@mui/material';
import { Stop } from '@mui/icons-material';

export default function EndNode({ isConnectable }) {
    return (
        <Box sx={{
            px: 3, py: 1.5, borderRadius: 8, bgcolor: '#1e293b', color: 'white',
            border: '2px solid #0f172a', display: 'flex', alignItems: 'center', gap: 1,
            boxShadow: '0 4px 6px -1px rgb(0 0 0 / 0.1)'
        }}>
            {/* Only incoming connections allowed */}
            <Handle type="target" position={Position.Top} isConnectable={isConnectable} style={{ width: 12, height: 12, background: '#ef4444' }} />
            <Stop fontSize="small" sx={{ color: '#ef4444' }} />
            <Typography variant="subtitle2" fontWeight="bold" letterSpacing={1}>END</Typography>
        </Box>
    );
}
