class WorkflowTask < ApplicationRecord
  belongs_to :workflow_instance
  belongs_to :workflow_step
  belongs_to :user

  enum :status, { pending: 'pending', approved: 'approved', rejected: 'rejected', canceled: 'canceled' }
end