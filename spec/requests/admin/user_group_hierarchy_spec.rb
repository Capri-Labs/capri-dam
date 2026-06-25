require 'rails_helper'

# Integration specs for the group-in-group (child_groups) feature.
#
# These cover:
#   - add_group_member sets parent_id on the child
#   - show returns child_groups from the closure table (not the FK association)
#   - remove_group_member clears parent_id and removes closure records
#   - existing data with missing parent_ids is still served correctly
RSpec.describe 'Admin::UserGroups — hierarchy (child groups)', type: :request do
  let(:admin) { create(:user, :admin) }

  before { sign_in admin }

  # ---------------------------------------------------------------------------
  # Helper
  # ---------------------------------------------------------------------------

  def json
    JSON.parse(response.body)
  end

  # ---------------------------------------------------------------------------
  # POST /admin/user_groups/:id/add_group_member
  # ---------------------------------------------------------------------------

  describe 'POST /admin/user_groups/:id/add_group_member' do
    let!(:parent_group) { create(:user_group) }
    let!(:child_group)  { create(:user_group) }

    it 'returns success' do
      post add_group_member_admin_user_group_path(parent_group),
           params: { child_group_id: child_group.id }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['success']).to be true
    end

    it 'creates a closure record (distance: 1)' do
      expect {
        post add_group_member_admin_user_group_path(parent_group),
             params: { child_group_id: child_group.id }, as: :json
      }.to change { UserGroupClosure.where(ancestor_id: parent_group.id,
                                           descendant_id: child_group.id,
                                           distance: 1).count }.by(1)
    end

    it 'sets parent_id on the child group' do
      post add_group_member_admin_user_group_path(parent_group),
           params: { child_group_id: child_group.id }, as: :json

      expect(child_group.reload.parent_id).to eq(parent_group.id)
    end

    it 'returns 422 when trying to nest a group inside itself' do
      post add_group_member_admin_user_group_path(parent_group),
           params: { child_group_id: parent_group.id }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'returns 404 for a non-existent child group' do
      post add_group_member_admin_user_group_path(parent_group),
           params: { child_group_id: 999_999 }, as: :json

      expect(response).to have_http_status(:not_found)
    end

    context 'with multiple children' do
      let!(:child2) { create(:user_group) }

      it 'reflects all children in the show response' do
        post add_group_member_admin_user_group_path(parent_group),
             params: { child_group_id: child_group.id }, as: :json
        post add_group_member_admin_user_group_path(parent_group),
             params: { child_group_id: child2.id }, as: :json

        get admin_user_group_path(parent_group), as: :json

        child_ids = json.dig('group', 'child_groups').map { |c| c['id'] }
        expect(child_ids).to match_array([child_group.id, child2.id])
      end
    end
  end

  # ---------------------------------------------------------------------------
  # GET /admin/user_groups/:id (show with child_groups)
  # ---------------------------------------------------------------------------

  describe 'GET /admin/user_groups/:id — child_groups in response' do
    let!(:parent_group) { create(:user_group) }
    let!(:child_group)  { create(:user_group) }

    before do
      parent_group.add_child(child_group)
    end

    it 'includes child_groups in the group JSON' do
      get admin_user_group_path(parent_group), as: :json

      expect(json.dig('group', 'child_groups')).to be_an(Array)
      expect(json.dig('group', 'child_groups').map { |c| c['id'] }).to include(child_group.id)
    end

    it 'includes id, name, slug, description, is_system for each child' do
      get admin_user_group_path(parent_group), as: :json

      child_data = json.dig('group', 'child_groups').first
      expect(child_data.keys).to include('id', 'name', 'slug', 'description', 'is_system')
    end

    it 'returns an empty child_groups array for a leaf group' do
      get admin_user_group_path(child_group), as: :json

      expect(json.dig('group', 'child_groups')).to eq([])
    end

    context 'with legacy data (parent_id not set, only closure exists)' do
      let!(:legacy_parent) { create(:user_group) }
      let!(:legacy_child)  { create(:user_group) }

      before do
        # Simulate the old bug: closure exists but parent_id was never written
        UserGroupClosure.create!(ancestor_id: legacy_parent.id,
                                 descendant_id: legacy_child.id,
                                 distance: 1)
        legacy_child.update_column(:parent_id, nil)
      end

      it 'still returns the child via the closure table' do
        get admin_user_group_path(legacy_parent), as: :json

        child_ids = json.dig('group', 'child_groups').map { |c| c['id'] }
        expect(child_ids).to include(legacy_child.id)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE /admin/user_groups/:id/remove_group_member
  # ---------------------------------------------------------------------------

  describe 'DELETE /admin/user_groups/:id/remove_group_member' do
    let!(:parent_group) { create(:user_group) }
    let!(:child_group)  { create(:user_group) }

    before do
      parent_group.add_child(child_group)
    end

    it 'returns success' do
      delete remove_group_member_admin_user_group_path(parent_group),
             params: { child_group_id: child_group.id }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['success']).to be true
    end

    it 'removes the closure record' do
      delete remove_group_member_admin_user_group_path(parent_group),
             params: { child_group_id: child_group.id }, as: :json

      expect(
        UserGroupClosure.find_by(ancestor_id: parent_group.id,
                                 descendant_id: child_group.id,
                                 distance: 1)
      ).to be_nil
    end

    it 'clears parent_id on the child group' do
      delete remove_group_member_admin_user_group_path(parent_group),
             params: { child_group_id: child_group.id }, as: :json

      expect(child_group.reload.parent_id).to be_nil
    end

    it 'removes the child from the show response' do
      delete remove_group_member_admin_user_group_path(parent_group),
             params: { child_group_id: child_group.id }, as: :json

      get admin_user_group_path(parent_group), as: :json
      child_ids = json.dig('group', 'child_groups').map { |c| c['id'] }
      expect(child_ids).not_to include(child_group.id)
    end

    it 'does not clear parent_id when child belongs to a different parent' do
      other_parent = create(:user_group)
      other_parent.add_child(child_group)   # child now has parent_id = other_parent.id

      # Try to remove from the original parent (already removed)
      delete remove_group_member_admin_user_group_path(parent_group),
             params: { child_group_id: child_group.id }, as: :json

      # parent_id should still point to the real parent
      expect(child_group.reload.parent_id).to eq(other_parent.id)
    end

    it 'returns 200 gracefully for a non-existent child group' do
      delete remove_group_member_admin_user_group_path(parent_group),
             params: { child_group_id: 999_999 }, as: :json

      expect(response).to have_http_status(:ok)
      expect(json['success']).to be true
    end
  end
end

