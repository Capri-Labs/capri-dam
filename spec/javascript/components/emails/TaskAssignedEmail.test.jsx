import React from 'react';
import { render, screen } from '@testing-library/react';
import TaskAssignedEmail from '../../../../app/javascript/components/emails/TaskAssignedEmail';

describe('TaskAssignedEmail', () => {
  it('renders the email template shell', () => {
    render(<TaskAssignedEmail />);
    expect(screen.getByText('HEADLESS DAM')).toBeInTheDocument();
    expect(screen.getByText('Action Required: Asset Review')).toBeInTheDocument();
    expect(screen.getByText('Open Asset for Review')).toBeInTheDocument();
  });

  it('shows the provided task details', () => {
    render(
      <TaskAssignedEmail
        userName="Casey"
        taskTitle="Legal Review"
        assetName="Brand Book.pdf"
        assignedDate="2026-07-01 10:00"
        actionUrl="https://example.com/tasks/5"
      />,
    );

    expect(screen.getByText('Hello Casey,')).toBeInTheDocument();
    expect(screen.getByText(/Legal Review/)).toBeInTheDocument();
    expect(screen.getByText(/Brand Book.pdf/)).toBeInTheDocument();
    expect(screen.getByText(/2026-07-01 10:00/)).toBeInTheDocument();
  });
});
