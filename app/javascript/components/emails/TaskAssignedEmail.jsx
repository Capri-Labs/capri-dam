import React from 'react';

export default function TaskAssignedEmail({
                                              userName = "User",
                                              taskTitle = "Workflow Review",
                                              assetName = "Untitled Asset",
                                              assignedDate = new Date().toLocaleString(),
                                              actionUrl = "#"
                                          }) {
    const styles = {
        main: {
            fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
            backgroundColor: '#f8fafc',
            margin: 0,
            padding: '40px 20px',
            width: '100%'
        },
        container: {
            backgroundColor: '#ffffff',
            border: '1px solid #e2e8f0',
            borderRadius: '8px',
            overflow: 'hidden',
            margin: '0 auto',
            maxWidth: '600px',
            textAlign: 'left'
        },
        header: {
            backgroundColor: '#0f172a',
            padding: '20px 30px'
        },
        headerTitle: {
            color: '#f8fafc',
            margin: 0,
            fontSize: '20px',
            fontWeight: 700,
            letterSpacing: '0.5px'
        },
        body: {
            padding: '30px'
        },
        h3: {
            color: '#1e293b',
            marginTop: 0,
            fontSize: '18px'
        },
        text: {
            color: '#475569',
            fontSize: '16px',
            lineHeight: 1.5,
            marginBottom: '24px'
        },
        detailsBox: {
            backgroundColor: '#f1f5f9',
            borderLeft: '4px solid #3b82f6',
            padding: '15px 20px',
            marginBottom: '30px',
            borderRadius: '4px'
        },
        detailsText: {
            margin: '0 0 10px 0',
            color: '#1e293b',
            fontSize: '15px'
        },
        label: {
            color: '#64748b',
            fontWeight: 'bold'
        },
        buttonContainer: {
            textAlign: 'center',
            width: '100%'
        },
        button: {
            display: 'inline-block',
            backgroundColor: '#4f46e5',
            color: '#ffffff',
            textDecoration: 'none',
            fontWeight: 'bold',
            fontSize: '16px',
            padding: '14px 28px',
            borderRadius: '6px'
        },
        footer: {
            backgroundColor: '#f8fafc',
            borderTop: '1px solid #e2e8f0',
            padding: '20px',
            textAlign: 'center'
        },
        footerText: {
            color: '#94a3b8',
            fontSize: '12px',
            margin: 0,
            lineHeight: 1.5
        }
    };

    return (
        <div style={styles.main}>
            <table width="100%" cellPadding="0" cellSpacing="0" border="0" style={{ backgroundColor: '#f8fafc' }}>
                <tbody>
                <tr>
                    <td align="center">
                        <div style={styles.container}>

                            {/* Header */}
                            <div style={styles.header}>
                                <h2 style={styles.headerTitle}>HEADLESS DAM</h2>
                            </div>

                            {/* Body */}
                            <div style={styles.body}>
                                <h3 style={styles.h3}>Action Required: Asset Review</h3>

                                <p style={styles.text}>Hello {userName},</p>

                                <p style={styles.text}>
                                    A new workflow task has been assigned to you. Please review the following asset and submit your approval or rejection.
                                </p>

                                {/* Details Box */}
                                <div style={styles.detailsBox}>
                                    <p style={styles.detailsText}>
                                        <span style={styles.label}>Task: </span> {taskTitle}
                                    </p>
                                    <p style={styles.detailsText}>
                                        <span style={styles.label}>Asset: </span> {assetName}
                                    </p>
                                    <p style={{ ...styles.detailsText, marginBottom: 0 }}>
                                        <span style={styles.label}>Assigned: </span> {assignedDate}
                                    </p>
                                </div>

                                {/* Call to Action Button */}
                                <div style={styles.buttonContainer}>
                                    <a href={actionUrl} style={styles.button}>
                                        Open Asset for Review
                                    </a>
                                </div>
                            </div>

                            {/* Footer */}
                            <div style={styles.footer}>
                                <p style={styles.footerText}>
                                    This is an automated notification from your Digital Asset Management system.<br />
                                    Please do not reply directly to this email.
                                </p>
                            </div>

                        </div>
                    </td>
                </tr>
                </tbody>
            </table>
        </div>
    );
}