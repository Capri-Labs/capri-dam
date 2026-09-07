# Records where an imported comment came from.
#
# Ingesting W3C Web Annotation documents raises an identity problem: the file
# names a creator, but honouring that name would let anyone fabricate a comment
# attributed to a colleague simply by editing a JSON file and uploading it —
# "the Creative Director approved this" is exactly the kind of claim a review
# trail must not be able to forge.
#
# So the +author+ of an imported comment is always the authenticated user who
# performed the import, who is accountable for it, and the *claimed* original
# creator is preserved here as untrusted provenance instead. The UI can then
# show "imported from Ziflow, originally by jane@agency.com" without ever
# asserting that Jane said it inside Capri.
class AddImportSourceToComments < ActiveRecord::Migration[8.1]
  def change
    add_column :comments, :import_source, :jsonb, null: false, default: {}

    # Partial: only imported rows carry provenance and they are a small
    # minority, so indexing the empty default would be mostly dead weight.
    add_index :comments, :import_source,
              using: :gin,
              where: "import_source <> '{}'::jsonb",
              name: "index_comments_on_import_source"
  end
end
