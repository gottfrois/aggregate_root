require 'spec_helper'

class Order
  include AggregateRoot::Base

  def initialize(id = generate_uuid)
    self.id = id
    @status = :draft
  end

  private
  attr_accessor :status

  def apply_order_created(event)
    @status = :created
  end

  def apply_order_completed(event)
    @status = :completed
  end
end

OrderCreated    = Class.new(RailsEventStore::Event)
OrderCompleted  = Class.new(RailsEventStore::Event)

module AggregateRoot
  describe Base do
    it "should be able to generate UUID if user won't provide it's own" do
      order1 = Order.new
      order2 = Order.new
      expect(order1.id).to_not eq(order2.id)
      expect(order1.id).to be_a(String)
    end

    it "should have ability to apply event on itself" do
      order = Order.new
      order_created = OrderCreated.new

      order.apply(order_created)
      expect(order.unpublished_events).to eq([order_created])
    end
  end

  describe Repository do
    let(:event_store) { FakeEventStore.new }

    it "should have ability to store & load aggregate" do
      aggregate_repository = Repository.new(event_store)
      order = Order.new
      order_created = OrderCreated.new
      order_id = order.id
      order.apply(order_created)

      aggregate_repository.store(order)

      stream = event_store.read_all_events(order.id)
      expect(stream.count).to eq(1)
      expect(stream.first).to be_event({
        event_type: 'OrderCreated',
        data: {}
      })

      order = Order.new(order_id)
      aggregate_repository.load(order)
      expect(order.unpublished_events).to be_empty
    end

    it "should initialize default RES client if event_store not provided" do
      aggregate_repository = Repository.new
      expect(aggregate_repository.event_store).to be_a(RailsEventStore::Client)
    end

    it 'should allow update with 2 or more event (checking expected version)' do
      aggregate_repository = Repository.new(event_store)
      order = Order.new
      order_id = order.id
      order.apply(OrderCreated.new)
      order.apply(order_completed = OrderCompleted.new)
      aggregate_repository.store(order)

      reloaded_order = Order.new(order_id)
      aggregate_repository.load(reloaded_order)
      expect(reloaded_order.version).to eq(order_completed.event_id)
    end

    it 'should fail when aggregate stream has been modified' do
      aggregate_repository = Repository.new(event_store)
      order = Order.new
      order_created = OrderCreated.new
      order_id = order.id
      order.apply(order_created)
      aggregate_repository.store(order)

      order1 = Order.new(order_id)
      aggregate_repository.load(order1)
      order2 = Order.new(order_id)
      aggregate_repository.load(order2)
      order1.apply(OrderCompleted.new)
      order2.apply(OrderCompleted.new)
      aggregate_repository.store(order1)

      expect { aggregate_repository.store(order2) }.to raise_error(AggregateRoot::HasBeenChanged)
    end
  end
end
