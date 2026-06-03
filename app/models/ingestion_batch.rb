class IngestionBatch < ApplicationRecord
  has_many :ingestion_items, dependent: :destroy
  # belongs_to :user, optional: true # Link to your admin user model

  validates :name, :source_type, presence: true

  # The Batch State Machine
  enum :status, {
    initializing: 0,  # Setting up the extraction connection
    extracting: 1,    # Pulling files into staging
    transforming: 2,  # AI is actively cleaning metadata
    review_needed: 3, # Waiting for a human architect to approve
    committed: 4,     # Successfully imported to live DAM
    failed: 5         # Connection dropped or fatal error
  }

  def calculate_progress!
    update!(
      processed_count: ingestion_items.where.not(status: :pending).count,
      total_count: ingestion_items.count
    )
  end
end