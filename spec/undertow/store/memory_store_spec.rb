# frozen_string_literal: true

RSpec.describe Undertow::Store::MemoryStore do
  let(:store) { described_class.new }
  let(:lock_key) { 'undertow:test:lock' }
  let(:lock_reacquire_while_held) { true }

  it_behaves_like 'a Undertow store adapter'
end
