class MentionDetectionService
  MENTION_PATTERN = /(?<![\w.])@([a-zA-Z0-9_\-.]+)/.freeze

  def self.extract_mentions(text)
    return [] if text.blank?

    matches = text.to_enum(:scan, MENTION_PATTERN).map do
      match = Regexp.last_match
      {
        username: match[1],
        start: match.begin(0),
        end: match.end(0),
      }
    end

    lowered_usernames = matches.map { |match| match[:username].downcase }.uniq
    return [] if lowered_usernames.empty?

    users_by_handle = User.where(
      "LOWER(username) IN (:values) OR LOWER(SPLIT_PART(email, '@', 1)) IN (:values)",
      values: lowered_usernames
    ).each_with_object({}) do |user, memo|
      handles = [ user.username, user.email.split("@").first ].compact.map(&:downcase)
      handles.each { |handle| memo[handle] ||= user }
    end

    matches.each_with_object([]) do |match, found|
      user = users_by_handle[match[:username].downcase]
      next unless user
      next if found.any? { |entry| entry[:user].id == user.id }

      username = user.username.presence || user.email.split("@").first
      found << match.merge(user: user, username: username)
    end
  end

  def self.replace_mentions(text, users_map = {})
    return text if text.blank?

    text.gsub(MENTION_PATTERN) do |match|
      username = Regexp.last_match(1)
      user = users_map[username] || users_map[username.downcase]
      if user
        %(<span class="mention" data-user-id="#{ERB::Util.html_escape(user.id)}">@#{ERB::Util.html_escape(username)}</span>)
      else
        match
      end
    end
  end
end
