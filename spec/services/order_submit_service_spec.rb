require 'rails_helper'
require 'support/gravity_helper'

describe OrderSubmitService, type: :services do
  include_context 'use stripe mock'

  let(:partner_id) { 'partner-1' }
  let(:credit_card_id) { 'cc-1' }
  let(:order) { Fabricate(:order, partner_id: partner_id, credit_card_id: credit_card_id, fulfillment_type: Order::PICKUP) }
  let!(:line_items) { [Fabricate(:line_item, order: order, price_cents: 2000_00, artwork_id: 'a-1', quantity: 1), Fabricate(:line_item, order: order, price_cents: 8000_00, artwork_id: 'a-2', edition_set_id: 'es-1', quantity: 2)] }
  let(:credit_card) { { external_id: stripe_customer.default_source, customer_account: { external_id: stripe_customer.id }, deactivated_at: nil } }
  let(:merchant_account_id) { 'ma-1' }
  let(:partner_merchant_accounts) { [{ external_id: 'ma-1' }, { external_id: 'some_account' }] }
  let(:authorize_charge_params) do
    {
      source_id: credit_card[:external_id],
      destination_id: merchant_account_id,
      customer_id: credit_card[:customer_account][:external_id],
      amount: order.buyer_total_cents,
      currency_code: order.currency_code
    }
  end

  describe '#submit!' do
    context 'with a partner with a merchant account' do
      let(:inventory_deduct_request_status) { 200 }
      let(:artwork_inventory_deduct_request) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1/inventory").with(body: { deduct: 1 }).to_return(status: inventory_deduct_request_status, body: {}.to_json) }
      let(:edition_set_inventory_deduct_request) { stub_request(:put, "#{Rails.application.config_for(:gravity)['api_v1_root']}/artwork/a-1/edition_set/es-1/inventory").with(body: { deduct: 2 }).to_return(status: inventory_deduct_request_status, body: {}.to_json) }
      before do
        allow(GravityService).to receive(:get_merchant_account).with(partner_id).and_return(partner_merchant_accounts.first)
        allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(credit_card)
        allow(Adapters::GravityV1).to receive(:get).with("/partner/#{partner_id}/all").and_return(gravity_v1_partner)
      end
      context 'with failed inventory deduct' do
        let(:inventory_deduct_request_status) { 400 }
        before do
          artwork_inventory_deduct_request
          edition_set_inventory_deduct_request
        end
        it 'raises error' do
          expect do
            OrderSubmitService.submit!(order)
          end.to raise_error(Errors::OrderError).and change(order.transactions, :count).by(0)
        end
      end
      context 'with a successful transaction' do
        before(:each) do
          OrderSubmitService.submit!(order)
        end

        it 'creates a record of the transaction' do
          expect(order.transactions.last.external_id).not_to be_nil
          expect(order.transactions.last.transaction_type).to eq Transaction::HOLD
          expect(order.transactions.last.status).to eq Transaction::SUCCESS
        end

        it 'updates the order expiration time' do
          expect(order.state_expires_at).to eq(order.state_updated_at + 2.days)
        end

        it 'updates the order state to SUBMITTED' do
          expect(order.state).to eq Order::SUBMITTED
          expect(order.state_updated_at).not_to be_nil
        end

        it 'updates external_charge_id with the id of the charge' do
          expect(order.external_charge_id).not_to be_nil
        end

        it 'queues a job for posting event' do
          expect(PostNotificationJob).to have_been_enqueued
        end

        it 'queues a job for rejecting the order when it expires' do
          job = ActiveJob::Base.queue_adapter.enqueued_jobs.detect { |j| j[:job] == OrderFollowUpJob }
          expect(job).to_not be_nil
          expect(job[:at].to_i).to eq order.reload.state_expires_at.to_i
          expect(job[:args][0]).to eq order.id
          expect(job[:args][1]).to eq Order::SUBMITTED
        end

        it 'sets commission_fee_cents' do
          expect(order.commission_fee_cents).to eq 8000_00
        end

        it 'sets transaction_fee_cents' do
          expect(order.transaction_fee_cents).to eq 290_30
        end
      end

      context 'with an unsuccessful transaction' do
        it 'creates a record of the transaction' do
          StripeMock.prepare_card_error(:card_declined, :new_charge)
          allow(GravityService).to receive(:get_merchant_account).with(partner_id).and_return(partner_merchant_accounts.first)
          allow(GravityService).to receive(:get_credit_card).with(credit_card_id).and_return(credit_card)
          expect { OrderSubmitService.submit!(order) }.to raise_error(Errors::PaymentError)
          expect(order.transactions.last.transaction_type).to eq Transaction::HOLD
          expect(order.transactions.last.status).to eq Transaction::FAILURE
        end
      end
    end
  end

  describe '#validate_credit_card!' do
    it 'raises an error if the credit card does not have an external id' do
      expect { OrderSubmitService.validate_credit_card!(customer_account: { external_id: 'cust-1' }, deactivated_at: nil) }.to raise_error(Errors::OrderError)
    end

    it 'raises an error if the credit card does not have a customer id' do
      expect { OrderSubmitService.validate_credit_card!(external_id: 'cc-1') }.to raise_error(Errors::OrderError)
      expect { OrderSubmitService.validate_credit_card!(external_id: 'cc-1', customer_account: { some_prop: 'some_val' }, deactivated_at: nil) }.to raise_error(Errors::OrderError)
    end

    it 'raises an error if the card is deactivated' do
      expect { OrderSubmitService.validate_credit_card!(external_id: 'cc-1', customer_account: { external_id: 'cust-1' }, deactivated_at: 'today') }.to raise_error(Errors::OrderError)
    end
  end

  describe '#calculate_commission' do
    context 'with successful gravity call' do
      before do
        stub_request(:get, %r{partner\/#{partner_id}/all}).to_return(status: 200, body: gravity_v1_partner.to_json)
      end
      it 'returns calculated commission fee' do
        expect(OrderSubmitService.calculate_commission(order)).to eq 8000_00.0
      end
    end
  end

  describe '#calculate_transaction' do
    it 'returns proper transaction fee' do
      expect(OrderSubmitService.calculate_transaction_fee(order)).to eq 290_30
    end
  end
end
