class InboxMessage < ApplicationRecord
  MESSAGE_TYPES = %w[mention notification workflow system announcement].freeze

  belongs_to :recipient, class_name: "User"
  belongs_to :sender, class_name: "User", optional: true
  belongs_to :email_template, optional: true

  validates :message_type, inclusion: { in: MESSAGE_TYPES }
  validates :subject, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :starred, -> { where.not(starred_at: nil) }
  scope :by_type, ->(type) { where(message_type: type) }
  scope :recent, -> { order(created_at: :desc) }

  def mark_read!
    update!(read_at: Time.current) if read_at.nil?
  end

  def mark_unread!
    update!(read_at: nil)
  end

  def archive!
    update!(archived_at: Time.current)
  end

  def star!
    update!(starred_at: starred_at.nil? ? Time.current : nil)
  end

  def read?
    read_at.present?
  end

  def archived?
    archived_at.present?
  end

  def starred?
    starred_at.present?
  end
end
