class Rendition < ApplicationRecord
  belongs_to :asset
  belongs_to :storage_backend
end
