class ReportDefinition < ApplicationRecord
  has_many :report_snapshots, dependent: :destroy

  validates :name, presence: true
  validates :report_type, presence: true
end
