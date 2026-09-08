# A stored derivative of an {Asset}: a print-ready TIFF, a social crop, a proof
# PDF — anything that is *the same work* in a different form.
#
# WHY THIS IS NOT AN ASSET VERSION
# --------------------------------
# A version answers "what did this asset look like at time T"; it is a point on
# a timeline and the newest one wins. A rendition answers "give me this asset in
# form X", and all of them are current at once. Modelling a CMYK print file as a
# version would make it *the* asset the moment it was uploaded, and the web
# original would read as superseded history.
#
# WHY THE STORAGE BACKEND IS RECORDED PER ROW
# -------------------------------------------
# +storage_backend_id+ is NOT NULL because a rendition is a pointer to exactly
# one object in exactly one place. Resolving the backend at read time from
# whatever happens to be active would silently break every rendition uploaded
# before the organisation switched provider — the bytes do not move just because
# the setting did.
class Rendition < ApplicationRecord
  # Kinds the processing pipeline owns. A manual upload may not claim one:
  # other code is entitled to assume a "thumbnail" was produced by the
  # thumbnailer, and letting a person put an arbitrary file there would turn a
  # safe assumption into an intermittent bug.
  SYSTEM_KINDS = %w[thumbnail web_preview poster].freeze

  # Lowercase identifier, because the kind is a key other systems match on, not
  # a label. Which kinds exist beyond the reserved ones is an organisational
  # question — "print_cmyk", "social_square", "broadcast_proxy" — so the format
  # is constrained but the vocabulary is not.
  KIND_FORMAT = /\A[a-z0-9]+(?:_[a-z0-9]+)*\z/

  belongs_to :asset
  belongs_to :storage_backend

  validates :kind,
            presence: true,
            format: { with: KIND_FORMAT, message: "must be lowercase words separated by underscores" },
            length: { maximum: 50 },
            uniqueness: { scope: :asset_id, case_sensitive: false, message: "already exists for this asset" }
  validates :storage_key, presence: true
  validates :file_size, :width, :height,
            numericality: { only_integer: true, greater_than: 0, allow_nil: true }

  scope :manual,    -> { where("metadata->>'source' = ?", "manual") }
  scope :generated, -> { where("metadata->>'source' IS DISTINCT FROM ?", "manual") }

  # The stored object exists only because this row points at it. Once the row is
  # gone the object is unreachable garbage, so it goes too.
  #
  # +after_destroy_commit+, not +after_destroy+: deleting the object inside a
  # transaction that later rolls back would leave a live row pointing at bytes
  # that no longer exist — a worse outcome than an orphaned file.
  after_destroy_commit :purge_stored_object!

  def manual?
    metadata["source"] == "manual"
  end

  def system_kind?
    SYSTEM_KINDS.include?(kind)
  end

  # Resolved against the backend this rendition was actually written to, not
  # whichever one is active now.
  def url
    storage_backend.adapter.url(storage_key)
  end

  # Removes the bytes. Deliberately forgiving: an object that is already gone is
  # the state we wanted, and a storage outage must not leave a user unable to
  # delete a row they have every right to delete.
  def purge_stored_object!
    storage_backend&.adapter&.delete(storage_key)
  rescue StandardError => e
    Rails.logger.warn("Rendition #{id}: failed to purge #{storage_key}: #{e.message}")
    nil
  end
end
