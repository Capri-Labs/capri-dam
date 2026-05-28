import React from 'react';
import { Handle, Position } from 'reactflow';
import { Box, Typography } from '@mui/material';
import { PlayArrow } from '@mui/icons-material';

export default function StartNode({ isConnectable }) {
    return (
        <Box sx={{
            px: 3, py: 1.5, borderRadius: 8, bgcolor: '#1e293b', color: 'white',
            border: '2px solid #0f172a', display: 'flex', alignItems: 'center', gap: 1,
            boxShadow: '0 4px 6px -1px rgb(0 0 0 / 0.1)'
        }}>
            <PlayArrow fontSize="small" sx={{ color: '#22c55e' }} />
            <Typography variant="subtitle2" fontWeight="bold" letterSpacing={1}>START</Typography>
            {/* Only outgoing connections allowed */}
            <Handle type="source" position={Position.Bottom} isConnectable={isConnectable} style={{ width: 12, height: 12, background: '#22c55e' }} />
        </Box>
    );
}