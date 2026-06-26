require "rails_helper"

RSpec.describe DuplicateGroup, type: :model do
  subject(:group) { build(:duplicate_group) }

  # ---------------------------------------------------------------------------
  # Factories
  # ---------------------------------------------------------------------------
  describe "factory" do
    it "builds a valid instance" do
      expect(group).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  describe "validations" do
    it { is_expected.to validate_presence_of(:checksum) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[pending resolved dismissed]) }

    context "when a pending group already exists for the checksum" do
      before { create(:duplicate_group, checksum: group.checksum, status: "pending") }

      it "is invalid (uniqueness on checksum + pending status)" do
        expect(group).not_to be_valid
        expect(group.errors[:checksum]).to be_present
      end
    end

    it "allows a second group with the same checksum when the existing group is resolved" do
      create(:duplicate_group, checksum: group.checksum, status: "resolved")
      expect(group).to be_valid
    end
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  describe "scopes" do
    let!(:pending_group)   { create(:duplicate_group, status: "pending") }
    let!(:resolved_group)  { create(:duplicate_group, :resolved) }
    let!(:dismissed_group) { create(:duplicate_group, :dismissed) }

    describe ".pending" do
      it "returns only pending groups" do
        expect(DuplicateGroup.pending).to match_array([ pending_group ])
      end
    end

    describe ".resolved" do
      it "returns only resolved groups" do
        expect(DuplicateGroup.resolved).to match_array([ resolved_group ])
      end
    end

    describe ".dismissed" do
      it "returns only dismissed groups" do
        expect(DuplicateGroup.dismissed).to match_array([ dismissed_group ])
      end
    end

    describe ".for_display" do
      it "returns at most DISPLAY_LIMIT pending groups ordered newest first" do
        result = DuplicateGroup.for_display
        expect(result.count).to be <= DuplicateGroup::DISPLAY_LIMIT
        expect(result).to include(pending_group)
        expect(result).not_to include(resolved_group, dismissed_group)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  describe "associations" do
    it { is_expected.to have_many(:duplicate_group_assets).dependent(:destroy) }
    it { is_expected.to have_many(:assets).through(:duplicate_group_assets) }
    it { is_expected.to belong_to(:resolved_by).optional }
  end

  # ---------------------------------------------------------------------------
  # Instance methods
  # ---------------------------------------------------------------------------
  describe "#resolve!" do
    let(:group) { create(:duplicate_group, status: "pending") }
    let(:user)  { create(:user) }

    it "marks the group as resolved" do
      group.resolve!(action: "kept_all", user: user)
      expect(group.reload.status).to eq("resolved")
    end

    it "sets resolution_action" do
      group.resolve!(action: "deleted_duplicates", user: user)
      expect(group.reload.resolution_action).to eq("deleted_duplicates")
    end

    it "records resolved_by and resolved_at" do
      group.resolve!(action: "kept_all", user: user)
      expect(group.reload.resolved_by).to eq(user)
      expect(group.reload.resolved_at).to be_within(2.seconds).of(Time.current)
    end
  end

  describe "#dismiss!" do
    let(:group) { create(:duplicate_group, status: "pending") }
    let(:user)  { create(:user) }

    it "marks the group as dismissed" do
      group.dismiss!(user: user)
      expect(group.reload.status).to eq("dismissed")
    end

    it "records the user who dismissed it" do
      group.dismiss!(user: user)
      expect(group.reload.resolved_by).to eq(user)
    end
  end

  describe "#summary" do
    it "returns a human-readable string" do
      group = build(:duplicate_group, checksum: "abc123def456", total_count: 3)
      expect(group.summary).to include("3 asset(s)")
      expect(group.summary).to include("abc123def4")
    end
  end
end
