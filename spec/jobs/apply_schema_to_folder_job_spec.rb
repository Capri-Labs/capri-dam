# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplySchemaToFolderJob, type: :job do
  let!(:schema_a) { FactoryBot.create(:metadata_schema, name: 'Schema A', level: 'root') }
  let!(:schema_b) { FactoryBot.create(:metadata_schema, name: 'Schema B', level: 'root') }
  let!(:folder)   { FactoryBot.create(:folder, user: FactoryBot.create(:user)) }

  describe '#perform' do
    context 'when applying a schema for the first time' do
      it 'creates an assignment' do
        expect {
          described_class.perform_now(
            folder_id: folder.id, schema_id: schema_a.id, cascade: false
          )
        }.to change(MetadataSchemaFolderAssignment, :count).by(1)

        assignment = MetadataSchemaFolderAssignment.find_by(folder_id: folder.id)
        expect(assignment.metadata_schema_id).to eq(schema_a.id)
      end
    end

    context 'when changing the schema on a folder that already has one (regression: find_or_create_by bug)' do
      before do
        # Apply schema_a first
        described_class.perform_now(
          folder_id: folder.id, schema_id: schema_a.id, cascade: false
        )
      end

      it 'replaces the old assignment instead of creating a duplicate' do
        expect(MetadataSchemaFolderAssignment.where(folder_id: folder.id).count).to eq(1)

        # Now change to schema_b
        described_class.perform_now(
          folder_id: folder.id, schema_id: schema_b.id, cascade: false
        )

        assignments = MetadataSchemaFolderAssignment.where(folder_id: folder.id)
        expect(assignments.count).to eq(1), 'expected only one assignment (the updated one), not duplicates'
        expect(assignments.first.metadata_schema_id).to eq(schema_b.id),
          'expected the assignment to point at the new schema, not the old one'
      end
    end

    context 'when cascade is true' do
      let!(:child_folder) { FactoryBot.create(:folder, user: folder.user_id && FactoryBot.create(:user), parent_id: folder.id) }

      it 'assigns the schema to child folders too' do
        child = FactoryBot.create(:folder, user: FactoryBot.create(:user), parent_id: folder.id)

        described_class.perform_now(
          folder_id: folder.id, schema_id: schema_a.id, cascade: true
        )

        expect(MetadataSchemaFolderAssignment.find_by(folder_id: child.id)&.metadata_schema_id).to eq(schema_a.id)
      end
    end

    context 'when the schema does not exist' do
      it 'returns early without raising' do
        expect {
          described_class.perform_now(folder_id: folder.id, schema_id: 999_999, cascade: false)
        }.not_to raise_error
        expect(MetadataSchemaFolderAssignment.where(folder_id: folder.id)).to be_empty
      end
    end
  end
end
