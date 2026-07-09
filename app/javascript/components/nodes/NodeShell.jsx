/**
 * NodeShell – shared chrome wrapper for every action / flow node.
 *
 * Provides:
 *   • Consistent card styling (colour accent top border, header row)
 *   • @xyflow/react Handle placement for 5 layouts:
 *       'linear'      → top target + bottom source (default)
 *       'branching'   → top target + two bottom sources (true/false)
 *       'multi'       → top target + N labelled bottom sources (switch / plugin)
 *       'source-only' → bottom source only (Start node)
 *       'target-only' → top target only (End node)
 *
 * Usage:
 *   <NodeShell color="#d97706" icon={Email} label="Send Email" isConnectable={…}>
 *     <Stack spacing={1.5} sx={{ p: 2 }}>…body…</Stack>
 *   </NodeShell>
 */

import React from 'react';
import { Handle, Position } from '@xyflow/react';
import { Box, Typography, Paper } from '@mui/material';
import PropTypes from 'prop-types';

export default function NodeShell({
  color = '#64748b',
  icon: Icon,
  label,
  handles = 'linear',
  branchLabels,
  branches,
  isConnectable,
  children,
}) {
  return (
    <Paper
      elevation={3}
      sx={{
        width: 320,
        borderRadius: 2,
        borderTop: `5px solid ${color}`,
        bgcolor: '#fff',
        overflow: 'hidden',
      }}
    >
      {/* Incoming handle */}
      {handles !== 'source-only' && (
        <Handle
          type="target"
          position={Position.Top}
          isConnectable={isConnectable}
          style={{ width: 12, height: 12, background: color }}
        />
      )}

      {/* Header */}
      <Box
        sx={{
          px: 2,
          py: 1.25,
          bgcolor: '#f8fafc',
          borderBottom: '1px solid #e2e8f0',
          display: 'flex',
          alignItems: 'center',
          gap: 1,
        }}
      >
        {Icon && <Icon sx={{ color, fontSize: 18 }} />}
        <Typography variant="subtitle2" sx={{ fontWeight: 800, color: '#1e293b' }}>
          {label}
        </Typography>
      </Box>

      {/* Body slot */}
      {children}

      {/* Outgoing handles */}
      {handles === 'branching' ? (
        <>
          <Handle
            type="source"
            position={Position.Bottom}
            id="true"
            style={{ left: '25%', background: '#22c55e', width: 12, height: 12 }}
            isConnectable={isConnectable}
          />
          <Handle
            type="source"
            position={Position.Bottom}
            id="false"
            style={{ left: '75%', background: '#ef4444', width: 12, height: 12 }}
            isConnectable={isConnectable}
          />
          <Box
            sx={{
              display: 'flex',
              justifyContent: 'space-between',
              px: 3,
              pb: 1,
              pt: 0.5,
              bgcolor: '#f8fafc',
              borderTop: '1px solid #e2e8f0',
            }}
          >
            <Typography variant="caption" sx={{ color: '#22c55e', fontWeight: 800 }}>
              {branchLabels?.true ?? 'TRUE'}
            </Typography>
            <Typography variant="caption" sx={{ color: '#ef4444', fontWeight: 800 }}>
              {branchLabels?.false ?? 'FALSE'}
            </Typography>
          </Box>
        </>
      ) : handles === 'multi' ? (
        <>
          {(branches || []).map((b, i) => {
            const left = `${((i + 1) / ((branches?.length || 0) + 1)) * 100}%`;
            return (
              <Handle
                key={b.id}
                type="source"
                position={Position.Bottom}
                id={b.id}
                style={{ left, background: b.color || color, width: 12, height: 12 }}
                isConnectable={isConnectable}
              />
            );
          })}
          <Box
            sx={{
              display: 'flex',
              justifyContent: 'space-around',
              gap: 0.5,
              px: 1.5,
              pb: 1,
              pt: 0.5,
              bgcolor: '#f8fafc',
              borderTop: '1px solid #e2e8f0',
            }}
          >
            {(branches || []).map((b) => (
              <Typography
                key={b.id}
                variant="caption"
                title={b.label}
                sx={{
                  color: b.color || color,
                  fontWeight: 800,
                  maxWidth: 90,
                  overflow: 'hidden',
                  textOverflow: 'ellipsis',
                  whiteSpace: 'nowrap',
                }}
              >
                {b.label}
              </Typography>
            ))}
          </Box>
        </>
      ) : handles !== 'target-only' ? (
        <Handle
          type="source"
          position={Position.Bottom}
          style={{ width: 12, height: 12, background: color }}
          isConnectable={isConnectable}
        />
      ) : null}
    </Paper>
  );
}

NodeShell.propTypes = {
  color: PropTypes.string,
  icon: PropTypes.elementType,
  label: PropTypes.string.isRequired,
  handles: PropTypes.oneOf(['linear', 'branching', 'multi', 'source-only', 'target-only']),
  branchLabels: PropTypes.shape({ true: PropTypes.string, false: PropTypes.string }),
  branches: PropTypes.arrayOf(PropTypes.shape({
    id: PropTypes.string.isRequired,
    label: PropTypes.string,
    color: PropTypes.string,
  })),
  isConnectable: PropTypes.bool,
  children: PropTypes.node,
};

