require "rails_helper"

# End-to-end coverage of the unauthenticated guest review surface. The
# security-relevant cases (scope, visibility, revocation, download gating) are
# the point of this file: everything here is reachable by anyone holding a URL.
RSpec.describe "Guest review flow", type: :request do
  let(:user)  { create(:user) }
  let(:asset) { create(:asset, user: user, title: "Hero shot", properties: { "content_type" => "image/jpeg" }) }
  let(:other_asset) { create(:asset, user: user, title: "Secret") }

  def mint(**opts)
    ReviewLink.mint(target: asset, created_by: user, name: "Client review", **opts)
  end

  it "shows the review shell for a valid token" do
    link, token = mint
    get "/s/reviews/#{token}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("guest-review-root")
    expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
    expect(link.reload.access_count).to eq(1)
  end

  it "refuses an unknown token" do
    get "/s/reviews/#{SecureRandom.urlsafe_base64(32)}"
    expect(response).to have_http_status(:gone)
    expect(response.body).to include("unavailable")
  end

  it "refuses a revoked token" do
    link, token = mint
    link.revoke!
    get "/s/reviews/#{token}"
    expect(response).to have_http_status(:gone)
    expect(response.body).to include("withdrawn")
  end

  it "refuses an expired token" do
    link, token = mint
    link.update_column(:expires_at, 1.day.ago)
    get "/s/reviews/#{token}"
    expect(response).to have_http_status(:gone)
    expect(response.body).to include("expired")
  end

  it "gates on a passphrase and lets a correct one through" do
    link, token = mint
    link.passphrase = "open sesame"
    link.save!

    get "/s/reviews/#{token}"
    expect(response).to have_http_status(:unauthorized)

    post "/s/reviews/#{token}/unlock", params: { passphrase: "wrong" }, as: :json
    expect(response).to have_http_status(:unauthorized)

    post "/s/reviews/#{token}/unlock", params: { passphrase: "open sesame" }, as: :json
    expect(response).to have_http_status(:ok)

    get "/s/reviews/#{token}"
    expect(response).to have_http_status(:ok)
  end

  it "lists only the assets the link covers" do
    _link, token = mint
    other_asset
    get "/s/reviews/#{token}/assets", headers: { "Accept" => "application/json" }
    body = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(body["assets"].map { |a| a["id"] }).to eq([ asset.id ])
    expect(body["review"]["name"]).to eq("Client review")
  end

  it "blocks pivoting to an asset outside the link" do
    _link, token = mint
    get "/s/reviews/#{token}/assets/#{other_asset.id}/threads", headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:not_found)
  end

  it "captures a guest identity and reuses it" do
    _link, token = mint
    post "/s/reviews/#{token}/identify", params: { email: " Priya@Client.COM ", name: "Priya" }, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["guest"]["email"]).to eq("priya@client.com")

    get "/s/reviews/#{token}/assets", headers: { "Accept" => "application/json" }
    expect(response.parsed_body["guest"]["display_name"]).to eq("Priya")
  end

  it "rejects an invalid guest email" do
    _link, token = mint
    post "/s/reviews/#{token}/identify", params: { email: "nope" }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  context "commenting" do
    it "requires identification when the link demands it" do
      _link, token = mint
      post "/s/reviews/#{token}/assets/#{asset.id}/comments", params: { body: "Crop tighter" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "creates an annotated guest thread" do
      _link, token = mint
      post "/s/reviews/#{token}/identify", params: { email: "priya@client.com", name: "Priya" }, as: :json

      post "/s/reviews/#{token}/assets/#{asset.id}/comments",
           params: { body: "Logo is clipped", annotations: [ { shape: "rect", x: 0.1, y: 0.2, width: 0.3, height: 0.4 } ] },
           as: :json
      expect(response).to have_http_status(:created), response.body

      body = response.parsed_body
      expect(body["thread"]).not_to have_key("visibility")
      comment = body["thread"]["comments"].first
      expect(comment["author"]["display_name"]).to eq("Priya")
      expect(comment["author"]).not_to have_key("email")
      expect(comment["annotations"].size).to eq(1)

      thread = CommentThread.order(:created_at).last
      expect(thread.visibility).to eq("guest")
      expect(thread.created_by_id).to be_nil
      expect(thread.created_by_guest).to be_present
      expect(thread.review_link).to be_present
    end

    it "refuses when the link disallows comments" do
      _link, token = mint(allow_comments: false, require_email: false)
      post "/s/reviews/#{token}/assets/#{asset.id}/comments", params: { body: "hi" }, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "hides internal threads and never leaks staff email" do
      _link, token = mint(require_email: false)
      CommentThread.create!(asset: asset, created_by: user, visibility: "internal")
      shown = CommentThread.create!(asset: asset, created_by: user, visibility: "guest")
      Comment.create!(comment_thread: shown, author: user, body: "Sharing for review")

      get "/s/reviews/#{token}/assets/#{asset.id}/threads", headers: { "Accept" => "application/json" }
      body = response.parsed_body
      expect(body["threads"].size).to eq(1)
      expect(body["threads"].first["id"]).to eq(shown.id)
      expect(response.body).not_to include(user.email)
    end

    it "lets a guest reply to a visible thread" do
      _link, token = mint(require_email: false)
      thread = CommentThread.create!(asset: asset, created_by: user, visibility: "guest")

      post "/s/reviews/#{token}/threads/#{thread.id}/comments", params: { body: "Agreed" }, as: :json
      expect(response).to have_http_status(:created), response.body
      expect(thread.reload.comments.count).to eq(1)
    end

    it "refuses a reply to an internal thread" do
      _link, token = mint(require_email: false)
      thread = CommentThread.create!(asset: asset, created_by: user, visibility: "internal")

      post "/s/reviews/#{token}/threads/#{thread.id}/comments", params: { body: "Sneaky" }, as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  it "refuses a download when the link does not allow it" do
    _link, token = mint(require_email: false)
    get "/s/reviews/#{token}/assets/#{asset.id}/download"
    expect(response).to have_http_status(:forbidden)
  end

  it "covers a collection target" do
    collection = create(:collection, user: user, name: "Autumn campaign")
    collection.assets << asset
    link, token = ReviewLink.mint(target: collection, created_by: user, name: "Campaign review")
    expect(link.collection_id).to eq(collection.id)

    get "/s/reviews/#{token}/assets", headers: { "Accept" => "application/json" }
    expect(response.parsed_body["assets"].map { |a| a["id"] }).to eq([ asset.id ])
  end

  describe "the rendered page shell" do
    it "serves the guest bundle and mount point, not the internal app" do
      _link, token = ReviewLink.mint(target: asset, created_by: user, name: "Client review")

      get "/s/reviews/#{token}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="guest-review-root"')
      expect(response.body).to include('data-token="' + token + '"')
      expect(response.body).to include("guest_review")
      expect(response.body).to include("noindex, nofollow")
    end

    it "does not ship the internal bundle or chrome to an external party" do
      _link, token = ReviewLink.mint(target: asset, created_by: user, name: "Client review")

      get "/s/reviews/#{token}"

      expect(response.body).not_to include("/assets/application.js")
      expect(response.body).not_to include('id="react-sidebar-root"')
    end

    # Guests write (comment, reply, identify), so the layout must carry the
    # CSRF token. The test environment disables forgery protection globally,
    # which would make the tag render empty and hide a real regression.
    it "emits a CSRF token when forgery protection is enabled" do
      _link, token = ReviewLink.mint(target: asset, created_by: user, name: "Client review")

      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      begin
        get "/s/reviews/#{token}"
        expect(response.body).to include('name="csrf-token"')
      ensure
        ActionController::Base.allow_forgery_protection = original
      end
    end
  end
end
