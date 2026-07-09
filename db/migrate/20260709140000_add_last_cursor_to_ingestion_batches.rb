# frozen_string_literal: true

class AddLastCursorToIngestionBatches < ActiveRecord::Migration[8.1]
  def change
    # ExtractionWorker#process_chunk persists pagination progress here so a
    # multi-page migration (any connector with more items than one page size)
    # correctly advances instead of re-fetching offset 0 forever. Previously
    # this column did not exist, so `batch.respond_to?(:last_cursor)` was
    # always false and the cursor was silently discarded on every chunk —
    # causing an infinite loop that reprocessed (and skipped, as duplicates)
    # the same first page indefinitely.
    add_column :ingestion_batches, :last_cursor, :string
  end
end
