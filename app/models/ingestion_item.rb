class IngestionItem < ApplicationRecord
  belongs_to :ingestion_batch

  # The Item State Machine
  enum :status, {
    pending: 0,           # Extracted, waiting for AI
    ai_processing: 1,     # Sent to Python MCP Gateway
    flagged_duplicate: 2, # Conflict! Exact hash exists in live DB
    flagged_error: 3,     # Corrupted file or missing usage rights
    ready_for_import: 4,  # Pristine and ready to commit
    committed: 5,         # Successfully moved to Asset table
    rejected: 6           # Admin manually discarded this file
  }

  validates :original_filename, presence: true

  # Helper to track potential financial savings from deduplication
  def self.total_duplicate_savings_bytes
    flagged_duplicate.sum(:file_size)
  end
end