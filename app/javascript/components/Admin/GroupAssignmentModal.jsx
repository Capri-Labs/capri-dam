import React, { useState, useEffect } from 'react';
import {
    Dialog, DialogTitle, DialogContent, DialogActions,
    Button, Typography, Checkbox, Box, List, ListItem, ListItemIcon, ListItemText, Divider
} from '@mui/material';

export default function GroupAssignmentModal({ open, user, allGroups, onClose, onSave }) {
    const [checkedGroups, setCheckedGroups] = useState([]);

    useEffect(() => {
        if (open && user) {
            setCheckedGroups(user.group_ids || []);
        }
    }, [open, user]);

    // Recursive helper to get all child IDs
    const getAllChildrenIds = (parentId) => {
        const children = allGroups.filter(g => g.parent_id === parentId);
        let ids = children.map(c => c.id);
        children.forEach(c => ids = [...ids, ...getAllChildrenIds(c.id)]);
        return ids;
    };

    const handleToggle = (group) => {
        const isCurrentlyChecked = checkedGroups.includes(group.id);
        const childrenIds = getAllChildrenIds(group.id);

        if (!isCurrentlyChecked) {
            // Cascade Select: Add self + all children
            setCheckedGroups(prev => [...new Set([...prev, group.id, ...childrenIds])]);
        } else {
            // Cascade Deselect: Remove self + all children
            setCheckedGroups(prev => prev.filter(id => id !== group.id && !childrenIds.includes(id)));
        }
    };

    const buildTree = (groups, parentId = null) => {
        return groups
            .filter(g => g.parent_id === parentId)
            .map(g => ({ ...g, children: buildTree(groups, g.id) }));
    };

    const renderTree = (nodes, depth = 0) => nodes.map((node) => (
        <Box key={node.id}>
            <ListItem button onClick={() => handleToggle(node)} sx={{ pl: 2 + (depth * 3) }}>
                <ListItemIcon sx={{ minWidth: 36 }}>
                    <Checkbox size="small" checked={checkedGroups.includes(node.id)} />
                </ListItemIcon>
                <ListItemText primary={node.name} secondary={node.description} />
            </ListItem>
            {node.children && renderTree(node.children, depth + 1)}
        </Box>
    ));

    return (
        <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
            <DialogTitle>Group Hierarchy & Access</DialogTitle>
            <DialogContent dividers sx={{ p: 0 }}>
                <List>{renderTree(buildTree(allGroups))}</List>
            </DialogContent>
            <DialogActions>
                <Button onClick={onClose}>Cancel</Button>
                <Button variant="contained" onClick={() => onSave(user.id, checkedGroups)}>Save Hierarchy</Button>
            </DialogActions>
        </Dialog>
    );
}