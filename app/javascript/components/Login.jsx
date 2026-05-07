import React, { useState } from 'react';
import {
    Box, TextField, Button, Typography, Container,
    Paper, Avatar, CssBaseline, Divider
} from '@mui/material';
import LockOutlinedIcon from '@mui/icons-material/LockOutlined';
import VpnKeyIcon from '@mui/icons-material/VpnKey'; // Icon for SSO

export default function Login() {
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');

    // Handle Local Login (JSON API)
    const handleSubmit = async (event) => {
        event.preventDefault();
        const response = await fetch('/users/sign_in.json', {
            method: 'POST',
            headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content,
            },
            body: JSON.stringify({ user: { email, password } }),
        });

        if (response.ok) {
            window.location.href = '/dashboard';
        } else {
            alert('Login failed. Please check your credentials.');
        }
    };

    // Handle Keycloak SSO Login (Full Page Redirect)
    const handleSSO = () => {
        // OmniAuth 2.0+ requires a POST request to initiate.
        // We create a hidden form and submit it to handle CSRF properly.
        const form = document.createElement('form');
        form.method = 'POST';
        form.action = '/users/auth/keycloak_openid';

        const csrfToken = document.querySelector('[name="csrf-token"]').content;
        const csrfInput = document.createElement('input');
        csrfInput.type = 'hidden';
        csrfInput.name = 'authenticity_token';
        csrfInput.value = csrfToken;

        form.appendChild(csrfInput);
        document.body.appendChild(form);
        form.submit();
    };

    return (
        <Container component="main" maxWidth="xs">
            <CssBaseline />
            <Paper elevation={6} sx={{ mt: 15, p: 4, display: 'flex', flexDirection: 'column', alignItems: 'center', borderRadius: 2 }}>
                <Avatar sx={{ m: 1, bgcolor: 'primary.main' }}>
                    <LockOutlinedIcon />
                </Avatar>
                <Typography component="h1" variant="h5">
                    Headless DAM Login
                </Typography>

                <Box component="form" onSubmit={handleSubmit} sx={{ mt: 1, width: '100%' }}>
                    <TextField
                        margin="normal"
                        required
                        fullWidth
                        label="Email Address"
                        autoComplete="email"
                        autoFocus
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                    />
                    <TextField
                        margin="normal"
                        required
                        fullWidth
                        label="Password"
                        type="password"
                        autoComplete="current-password"
                        value={password}
                        onChange={(e) => setPassword(e.target.value)}
                    />
                    <Button
                        type="submit"
                        fullWidth
                        variant="contained"
                        sx={{ mt: 3, mb: 2, py: 1.5, fontWeight: 'bold' }}
                    >
                        Sign In
                    </Button>

                    <Divider sx={{ my: 2 }}>
                        <Typography variant="body2" sx={{ color: 'text.secondary' }}>
                            OR
                        </Typography>
                    </Divider>

                    <Button
                        fullWidth
                        variant="outlined"
                        color="secondary"
                        startIcon={<VpnKeyIcon />}
                        onClick={handleSSO}
                        sx={{ py: 1.5, fontWeight: 'bold', textTransform: 'none' }}
                    >
                        Sign in with Enterprise SSO
                    </Button>
                </Box>
            </Paper>
        </Container>
    );
}