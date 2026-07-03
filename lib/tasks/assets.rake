namespace :assets do
  desc "Backfill flattened PNG previews for non-web-native images (PSD/TIFF/HEIC) that lack one"
  task backfill_previews: :environment do
    scope = Asset.where(deleted_at: nil)
    total = 0
    generated = 0
    skipped = 0

    scope.find_each do |asset|
      total += 1
      path = AssetProcessorWorker.backfill_preview(asset)
      if path
        generated += 1
        puts "✅ #{asset.id} → #{path}"
      else
        skipped += 1
      end
    rescue StandardError => e
      skipped += 1
      warn "⚠️  #{asset.id}: #{e.message}"
    end

    puts "Done. Scanned #{total}, generated #{generated}, skipped #{skipped}."
  end
end
