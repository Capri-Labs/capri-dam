class ReportSnapshot < ApplicationRecord
  belongs_to :report_definition

  # ActiveStorage attachment for the generated file
  has_one_attached :generated_file

  # Rails 7+ Enum syntax
  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :format, presence: true, inclusion: { in: %w[csv pdf xlsx] }
end