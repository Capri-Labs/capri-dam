namespace :demo do
  desc "Creates/updates the throwaway 'MAM Global' demo Metadata Schema (cascading dropdowns) " \
       "for a customer demo. Safe to re-run — updates the schema in place by slug."
  task seed_mam_global: :environment do
    schema = MamGlobalDemoSchemaSeeder.seed!
    puts "✅ MAM Global demo schema ready: id=#{schema.id} slug=#{schema.slug}"
    puts "   Apply it to a folder via Tools → Metadata Schemas, or:"
    puts "   POST /api/v1/metadata_schemas/#{schema.id}/apply_to_folder?folder_id=<FOLDER_ID>"
  end

  desc "Removes the throwaway 'MAM Global' demo Metadata Schema created by demo:seed_mam_global"
  task remove_mam_global: :environment do
    MamGlobalDemoSchemaSeeder.remove!
    puts "✅ MAM Global demo schema removed (if it existed)."
  end
end
