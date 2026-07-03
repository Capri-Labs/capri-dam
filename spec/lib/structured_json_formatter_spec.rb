require 'rails_helper'

RSpec.describe StructuredJsonFormatter do
  subject(:formatter) { described_class.new }

  let(:timestamp) { Time.utc(2026, 7, 3, 7, 27, 45, 123_000) }

  describe '#call' do
    it 'formats plain string messages as JSON' do
      payload = JSON.parse(formatter.call('INFO', timestamp, nil, 'hello world'))

      expect(payload).to include(
        'timestamp' => '2026-07-03T07:27:45.123Z',
        'level' => 'INFO',
        'message' => 'hello world',
        'environment' => Rails.env
      )
    end

    it 'adds OpenTelemetry trace identifiers when the current span is valid' do
      context = instance_double('OpenTelemetry::Context', valid?: true, hex_trace_id: 'abc123', hex_span_id: 'def456')
      span = instance_double('OpenTelemetry::Trace::Span', context: context)
      trace_module = Class.new do
        def self.current_span; end
      end

      stub_const('OpenTelemetry', Module.new)
      stub_const('OpenTelemetry::Trace', trace_module)
      allow(OpenTelemetry::Trace).to receive(:current_span).and_return(span)

      payload = JSON.parse(formatter.call('INFO', timestamp, nil, 'hello world'))

      expect(payload).to include('trace_id' => 'abc123', 'span_id' => 'def456')
    end

    it 'skips trace identifiers when the current span context is invalid' do
      context = instance_double('OpenTelemetry::Context', valid?: false)
      span = instance_double('OpenTelemetry::Trace::Span', context: context)
      trace_module = Class.new do
        def self.current_span; end
      end

      stub_const('OpenTelemetry', Module.new)
      stub_const('OpenTelemetry::Trace', trace_module)
      allow(OpenTelemetry::Trace).to receive(:current_span).and_return(span)

      payload = JSON.parse(formatter.call('INFO', timestamp, nil, 'hello world'))

      expect(payload).not_to have_key('trace_id')
      expect(payload).not_to have_key('span_id')
    end

    it 'formats exceptions with their class and backtrace' do
      error = RuntimeError.new('boom')
      error.set_backtrace([ 'line one', 'line two' ])

      payload = JSON.parse(formatter.call('ERROR', timestamp, nil, error))

      expect(payload['message']).to include('boom (RuntimeError)', 'line one', 'line two')
    end

    it 'formats exceptions without a backtrace' do
      error = RuntimeError.new('boom')
      error.set_backtrace(nil)

      payload = JSON.parse(formatter.call('ERROR', timestamp, nil, error))

      expect(payload['message']).to eq("boom (RuntimeError)\n")
    end

    it 'falls back to inspect for non-string, non-exception objects' do
      payload = JSON.parse(formatter.call('INFO', timestamp, nil, { ok: true }))

      expect(payload['message']).to eq('{ok: true}')
    end
  end
end
