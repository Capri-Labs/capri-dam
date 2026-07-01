require 'rails_helper'

RSpec.describe WorkflowEvaluatorService, type: :service do
  let(:folder_id) { SecureRandom.uuid }
  let(:asset) { build_stubbed(:asset, id: SecureRandom.uuid, folder_id: folder_id) }
  let(:specific_workflow) do
    instance_double(
      Workflow,
      id: 1,
      name: 'Specific workflow',
      folder_scope: 'specific',
      target_folder_ids: [ folder_id ],
      exclude_folder_ids: []
    )
  end
  let(:excluded_workflow) do
    instance_double(
      Workflow,
      id: 2,
      name: 'Excluded workflow',
      folder_scope: 'all',
      target_folder_ids: [],
      exclude_folder_ids: [ folder_id ]
    )
  end
  let(:global_workflow) do
    instance_double(
      Workflow,
      id: 3,
      name: 'Global workflow',
      folder_scope: 'all',
      target_folder_ids: [],
      exclude_folder_ids: []
    )
  end

  before do
    allow(WorkflowInitiatorWorker).to receive(:perform_async)
    allow(Rails.logger).to receive(:info)
  end

  describe '.call' do
    it 'delegates to an instance evaluator' do
      evaluator = instance_double(described_class, evaluate_and_trigger!: true)

      expect(described_class).to receive(:new).with(asset, 'on_upload').and_return(evaluator)

      described_class.call(asset, trigger_event: 'on_upload')
    end
  end

  describe '#evaluate_and_trigger!' do
    it 'enqueues matching workflows and skips excluded ones' do
      allow(Workflow).to receive(:where).with(status: 'active', trigger_type: 'on_upload')
                                     .and_return([ specific_workflow, excluded_workflow, global_workflow ])

      described_class.new(asset, 'on_upload').evaluate_and_trigger!

      expect(WorkflowInitiatorWorker).to have_received(:perform_async).with(asset.id, 1)
      expect(WorkflowInitiatorWorker).to have_received(:perform_async).with(asset.id, 3)
      expect(WorkflowInitiatorWorker).not_to have_received(:perform_async).with(asset.id, 2)
    end

    it 'skips specific-folder workflows when the asset folder is not targeted' do
      unmatched_workflow = instance_double(
        Workflow,
        id: 4,
        name: 'Unmatched workflow',
        folder_scope: 'specific',
        target_folder_ids: [ 'folder-2' ],
        exclude_folder_ids: []
      )
      allow(Workflow).to receive(:where).and_return([ unmatched_workflow ])

      described_class.new(asset, 'on_upload').evaluate_and_trigger!

      expect(WorkflowInitiatorWorker).not_to have_received(:perform_async)
    end
  end
end
