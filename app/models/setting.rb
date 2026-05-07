class Setting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  # Usage: Setting.get('site_name')
  def self.get(key, default = nil)
    find_by(key: key)&.value || default
  end

  # Usage: Setting.set('site_name', 'My Headless DAM')
  def self.set(key, value)
    setting = find_or_initialize_by(key: key)
    setting.update(value: value)
  end
end