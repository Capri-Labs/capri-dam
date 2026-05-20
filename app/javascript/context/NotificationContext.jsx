import React, { createContext, useContext, useState, useCallback } from 'react';
import { Snackbar, Alert, Stack } from '@mui/material';

const NotificationContext = createContext(null);

export function NotificationProvider({ children }) {
    const [notifications, setNotifications] = useState([]);

    // Trigger an alert from anywhere. Severity can be: 'success', 'info', 'warning', 'error'
    const showNotification = useCallback((message, severity = 'info', duration = 4000) => {
        const id = Date.now() + Math.random(); // Unique key for stacking items
        setNotifications((prev) => [...prev, { id, message, severity, duration }]);
    }, []);

    const handleClose = (id) => {
        setNotifications((prev) => prev.filter((notification) => notification.id !== id));
    };

    return (
        <NotificationContext.Provider value={showNotification}>
            {children}

            {/* Floating Stack Container in the Top Right Corner */}
            <Stack
                spacing={1}
                sx={{
                    position: 'fixed',
                    top: 24,
                    right: 24,
                    zIndex: 9999,
                    maxWidth: 400,
                    width: '100%'
                }}
            >
                {notifications.map((notif) => (
                    <Snackbar
                        key={notif.id}
                        open={true}
                        autoHideDuration={notif.duration}
                        onClose={() => handleClose(notif.id)}
                        anchorOrigin={{ vertical: 'top', horizontal: 'right' }}
                        // Crucial styling shift: force relative positioning inside our custom stack wrapper
                        sx={{ position: 'relative', top: 'auto', right: 'auto' }}
                    >
                        <Alert
                            onClose={() => handleClose(notif.id)}
                            severity={notif.severity}
                            variant="filled"
                            elevation={6}
                            sx={{ width: '100%', borderRadius: 2 }}
                        >
                            {notif.message}
                        </Alert>
                    </Snackbar>
                ))}
            </Stack>
        </NotificationContext.Provider>
    );
}

// Custom Hook for clean execution across components
export const useNotify = () => {
    const context = useContext(NotificationContext);
    return context || ((msg, sev) => console.log(`[Notification Fallback] ${sev}: ${msg}`));
};